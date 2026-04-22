import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/web_invite_view_data.dart';
import '../models/web_withdraw_config.dart';
import '../services/api_config.dart';
import '../services/app_api.dart';
import '../services/web_app_facade.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/web_error_text.dart';
import '../widgets/action_button.dart';
import '../widgets/animated_card.dart';
import '../widgets/capybara_loader.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_layout_metrics.dart';
import '../widgets/web_page_frame.dart';

typedef WebInviteDataLoader = Future<WebInviteViewData> Function();
typedef WebInvitePagedDataLoader = Future<WebInviteViewData> Function({
  required int page,
  required int pageSize,
});
typedef WebInviteCodeCreator = Future<void> Function();
typedef WebInviteBalanceTransfer = Future<void> Function(int amountCents);
typedef WebInviteWithdrawConfigLoader = Future<WebWithdrawConfig> Function();
typedef WebInviteWithdrawalRequester = Future<void> Function({
  required String method,
  required String account,
});

class WebInvitePage extends StatefulWidget {
  const WebInvitePage({
    super.key,
    this.dataLoader,
    this.pagedDataLoader,
    this.codeCreator,
    this.balanceTransfer,
    this.withdrawConfigLoader,
    this.withdrawalRequester,
    this.onUnauthorized,
  });

  final WebInviteDataLoader? dataLoader;
  final WebInvitePagedDataLoader? pagedDataLoader;
  final WebInviteCodeCreator? codeCreator;
  final WebInviteBalanceTransfer? balanceTransfer;
  final WebInviteWithdrawConfigLoader? withdrawConfigLoader;
  final WebInviteWithdrawalRequester? withdrawalRequester;
  final VoidCallback? onUnauthorized;

  @override
  State<WebInvitePage> createState() => _WebInvitePageState();
}

class _WebInvitePageState extends State<WebInvitePage> {
  static const int _recordsPageSize = 10;

  final _facade = WebAppFacade();
  Future<WebInviteViewData>? _future;
  bool _isGeneratingCode = false;
  bool _isTransferring = false;
  bool _isWithdrawing = false;
  int _recordsPage = 1;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  Future<WebInviteViewData> _loadData() async {
    if (widget.pagedDataLoader != null) {
      return widget.pagedDataLoader!(
        page: _recordsPage,
        pageSize: _recordsPageSize,
      );
    }
    if (widget.dataLoader != null) {
      return widget.dataLoader!();
    }

    return _facade.loadInviteData(
      page: _recordsPage,
      pageSize: _recordsPageSize,
    );
  }

  Future<void> _createInviteCode(bool isChinese) async {
    setState(() => _isGeneratingCode = true);
    try {
      if (widget.codeCreator != null) {
        await widget.codeCreator!();
      } else {
        await _facade.createInviteCode();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isChinese ? '邀请码已生成。' : 'Invite code generated.'),
        ),
      );
      _reload();
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isGeneratingCode = false);
    }
  }

  Future<void> _copyInvite(
    BuildContext context,
    bool isChinese,
    String inviteUrl,
  ) async {
    await Clipboard.setData(ClipboardData(text: inviteUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isChinese ? '邀请链接已复制到剪贴板。' : 'Invite link copied to clipboard.',
        ),
      ),
    );
  }

  Future<void> _transferToBalance(
    WebInviteViewData data,
    bool isChinese, {
    required int amount,
  }) async {
    if (amount <= 0 || _isTransferring) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _TransferConfirmDialog(
        title: isChinese ? '转为余额' : 'Transfer to Balance',
        message: isChinese
            ? '确认将 ${_money(amount)} 佣金全部转为账户余额？'
            : 'Transfer all available commission (${_money(amount)}) to account balance?',
        cancelLabel: isChinese ? '取消' : 'Cancel',
        confirmLabel: isChinese ? '确认转入' : 'Confirm',
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isTransferring = true);
    try {
      if (widget.balanceTransfer != null) {
        await widget.balanceTransfer!(amount);
      } else {
        await _facade.transferReferralBalance(amount);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isChinese
                ? '佣金已转为账户余额。'
                : 'Commission transferred to account balance.',
          ),
        ),
      );
      _reload();
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _transferAllToBalance(
    WebInviteViewData data,
    bool isChinese,
  ) {
    return _transferToBalance(
      data,
      isChinese,
      amount: data.metrics.withdrawableAmount,
    );
  }

  Future<void> _transferCustomAmount(
    WebInviteViewData data,
    bool isChinese,
  ) async {
    final available = data.metrics.withdrawableAmount;
    if (available <= 0) {
      _showSnack(isChinese ? '当前没有可转入的佣金。' : 'No commission available.');
      return;
    }

    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _TransferAmountDialog(
        isChinese: isChinese,
        maxAmountCents: available,
        moneyFormatter: _money,
      ),
    );
    if (amount == null || !mounted) return;
    await _transferToBalance(data, isChinese, amount: amount);
  }

  Future<void> _requestWithdrawal(
    WebInviteViewData data,
    bool isChinese,
  ) async {
    if (_isWithdrawing) return;
    if (data.metrics.withdrawableAmount <= 0) {
      _showSnack(isChinese ? '当前没有可提现佣金。' : 'No commission to withdraw.');
      return;
    }

    WebWithdrawConfig config;
    setState(() => _isWithdrawing = true);
    try {
      config = widget.withdrawConfigLoader == null
          ? await _facade.loadWithdrawConfig()
          : await widget.withdrawConfigLoader!();
    } catch (error) {
      _handleActionError(error, isChinese);
      return;
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }

    if (!mounted) return;
    if (config.closed) {
      _showSnack(isChinese
          ? '当前暂未开放佣金提现，请稍后再试。'
          : 'Commission withdrawal is not available right now.');
      return;
    }
    if (config.methods.isEmpty) {
      _showSnack(isChinese
          ? '当前暂未提供提现方式，请联系客服协助。'
          : 'No withdrawal method is available right now. Please contact support.');
      return;
    }

    final request = await showDialog<WebWithdrawalRequest>(
      context: context,
      builder: (dialogContext) => _WithdrawDialog(
        isChinese: isChinese,
        methods: config.methods,
        amountLabel: _money(data.metrics.withdrawableAmount),
      ),
    );
    if (request == null || !mounted) return;

    setState(() => _isWithdrawing = true);
    try {
      if (widget.withdrawalRequester != null) {
        await widget.withdrawalRequester!(
          method: request.method,
          account: request.account,
        );
      } else {
        await _facade.requestReferralWithdrawal(
          method: request.method,
          account: request.account,
        );
      }
      if (!mounted) return;
      _showSnack(isChinese ? '提现工单已创建。' : 'Withdrawal ticket created.');
      _reload();
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  void _handleActionError(Object error, bool isChinese) {
    if (error is AppApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      _handleUnauthorized();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          webErrorText(
            error,
            isChinese: isChinese,
            context: WebErrorContext.general,
          ),
        ),
      ),
    );
  }

  void _handleUnauthorized() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ApiConfig().clearAuth();
      if (mounted) widget.onUnauthorized?.call();
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _reload() {
    setState(() {
      _future = _loadData();
    });
  }

  void _changeRecordsPage(int page) {
    if (page <= 0 || page == _recordsPage) return;
    setState(() {
      _recordsPage = page;
      _future = _loadData();
    });
  }

  String _inviteUrl(String code) {
    final base = Uri.base;
    final origin = base.hasScheme && base.host.isNotEmpty
        ? '${base.scheme}://${base.authority}'
        : 'http://localhost';
    return Uri.parse('$origin/').replace(
        queryParameters: <String, String>{'invite_code': code}).toString();
  }

  String _money(int cents) => '¥${Formatters.formatCurrency(cents)}';

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final future = _future;
    if (future == null) {
      return const Center(child: CapybaraLoader());
    }

    return FutureBuilder<WebInviteViewData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is AppApiException &&
              (error.statusCode == 401 || error.statusCode == 403)) {
            _handleUnauthorized();
            return const Center(child: CapybaraLoader());
          }
          return _InviteErrorState(
            isChinese: isChinese,
            message: webErrorText(
              error ?? StateError('invite.load.failed'),
              isChinese: isChinese,
              context: WebErrorContext.pageLoad,
            ),
            onReload: _reload,
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CapybaraLoader());
        }

        return _InviteContent(
          data: snapshot.data!,
          isChinese: isChinese,
          isGeneratingCode: _isGeneratingCode,
          isTransferring: _isTransferring,
          isWithdrawing: _isWithdrawing,
          inviteUrlBuilder: _inviteUrl,
          moneyFormatter: _money,
          onCopyInvite: (inviteUrl) =>
              _copyInvite(context, isChinese, inviteUrl),
          onCreateCode: () => _createInviteCode(isChinese),
          onTransferAll: () => _transferAllToBalance(snapshot.data!, isChinese),
          onTransferCustom: () =>
              _transferCustomAmount(snapshot.data!, isChinese),
          onWithdraw: () => _requestWithdrawal(snapshot.data!, isChinese),
          onRecordsPageChanged: _changeRecordsPage,
        );
      },
    );
  }
}

class _InviteContent extends StatelessWidget {
  const _InviteContent({
    required this.data,
    required this.isChinese,
    required this.isGeneratingCode,
    required this.isTransferring,
    required this.isWithdrawing,
    required this.inviteUrlBuilder,
    required this.moneyFormatter,
    required this.onCopyInvite,
    required this.onCreateCode,
    required this.onTransferAll,
    required this.onTransferCustom,
    required this.onWithdraw,
    required this.onRecordsPageChanged,
  });

  final WebInviteViewData data;
  final bool isChinese;
  final bool isGeneratingCode;
  final bool isTransferring;
  final bool isWithdrawing;
  final String Function(String code) inviteUrlBuilder;
  final String Function(int cents) moneyFormatter;
  final ValueChanged<String> onCopyInvite;
  final VoidCallback onCreateCode;
  final VoidCallback onTransferAll;
  final VoidCallback onTransferCustom;
  final VoidCallback onWithdraw;
  final ValueChanged<int> onRecordsPageChanged;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = WebLayoutMetrics.useWideProfileRow(width);
    final primaryCode = data.primaryCode;
    final inviteUrl =
        primaryCode == null ? '' : inviteUrlBuilder(primaryCode.code);

    return WebPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientCard(
            borderRadius: 32,
            padding: EdgeInsets.all(WebLayoutMetrics.cardPadding(width)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InviteStatBlock(
                        title: isChinese ? '当前剩余佣金' : 'Available Commission',
                        value: moneyFormatter(data.metrics.withdrawableAmount),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _InviteStatBlock(
                        title: isChinese ? '累计获得佣金' : 'Total Commission',
                        value: moneyFormatter(data.metrics.settledAmount),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: WebLayoutMetrics.sectionGap(width)),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: wide ? 260 : double.infinity,
                      child: SizedBox(
                        key: const Key('web-invite-withdraw-button'),
                        child: ActionButton(
                          icon: Icons.account_balance_wallet_outlined,
                          label: isChinese ? '佣金提现' : 'Withdraw Commission',
                          isLoading: isWithdrawing,
                          onPressed: isWithdrawing ? null : onWithdraw,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: wide ? 260 : double.infinity,
                      child: _TransferButton(
                        cardKey: const Key('web-invite-transfer-button'),
                        enabled: data.metrics.withdrawableAmount > 0 &&
                            !isTransferring,
                        isLoading: isTransferring,
                        icon: Icons.input_rounded,
                        label: isChinese ? '一键全部转入' : 'Transfer All',
                        onTap: onTransferAll,
                      ),
                    ),
                    SizedBox(
                      width: wide ? 260 : double.infinity,
                      child: _TransferButton(
                        cardKey: const Key('web-invite-transfer-custom-button'),
                        enabled: data.metrics.withdrawableAmount > 0 &&
                            !isTransferring,
                        isLoading: false,
                        icon: Icons.tune_rounded,
                        label: isChinese ? '自定义金额转入' : 'Custom Transfer',
                        onTap: onTransferCustom,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: width >= 860 ? 24 : 20),
                _InviteCodePanel(
                  isChinese: isChinese,
                  primaryCode: primaryCode,
                  inviteUrl: inviteUrl,
                  invitedUsers: data.metrics.registeredUsers,
                  commissionRate: data.metrics.ratePercent,
                  isGeneratingCode: isGeneratingCode,
                  onCopyInvite: onCopyInvite,
                  onCreateCode: onCreateCode,
                  wide: wide,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _CommissionRecordsCard(
            isChinese: isChinese,
            records: data.records,
            page: data.page,
            pageSize: data.pageSize,
            total: data.total,
            hasMore: data.hasMore,
            moneyFormatter: moneyFormatter,
            onPageChanged: onRecordsPageChanged,
          ),
        ],
      ),
    );
  }
}

class _InviteCodePanel extends StatelessWidget {
  const _InviteCodePanel({
    required this.isChinese,
    required this.primaryCode,
    required this.inviteUrl,
    required this.invitedUsers,
    required this.commissionRate,
    required this.isGeneratingCode,
    required this.onCopyInvite,
    required this.onCreateCode,
    required this.wide,
  });

  final bool isChinese;
  final WebInviteCodeData? primaryCode;
  final String inviteUrl;
  final int invitedUsers;
  final int commissionRate;
  final bool isGeneratingCode;
  final ValueChanged<String> onCopyInvite;
  final VoidCallback onCreateCode;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final hasCode = primaryCode != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isChinese ? '邀请码' : 'Invite Link',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  hasCode
                      ? inviteUrl
                      : (isChinese
                          ? '还没有可用邀请码，先生成一个。'
                          : 'No available invite code yet. Generate one first.'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              if (hasCode)
                FilledButton.icon(
                  key: const Key('web-invite-copy-button'),
                  onPressed: () => onCopyInvite(inviteUrl),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(isChinese ? '复制邀请码' : 'Copy Invite Link'),
                )
              else
                FilledButton.icon(
                  key: const Key('web-invite-generate-button'),
                  onPressed: isGeneratingCode ? null : onCreateCode,
                  icon: isGeneratingCode
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 18),
                  label: Text(isChinese ? '生成邀请码' : 'Generate Code'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (wide)
            Row(
              children: [
                Expanded(
                  child: _MetaStat(
                    label: isChinese ? '已邀请用户数' : 'Invited Users',
                    value: '$invitedUsers',
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _MetaStat(
                    label: isChinese ? '佣金比例' : 'Commission Rate',
                    value: '$commissionRate%',
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _MetaStat(
                  label: isChinese ? '已邀请用户数' : 'Invited Users',
                  value: '$invitedUsers',
                ),
                const SizedBox(height: 12),
                _MetaStat(
                  label: isChinese ? '佣金比例' : 'Commission Rate',
                  value: '$commissionRate%',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CommissionRecordsCard extends StatelessWidget {
  const _CommissionRecordsCard({
    required this.isChinese,
    required this.records,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasMore,
    required this.moneyFormatter,
    required this.onPageChanged,
  });

  final bool isChinese;
  final List<WebInviteRecordData> records;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;
  final String Function(int cents) moneyFormatter;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 30,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isChinese ? '佣金发放记录' : 'Commission Records',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 30,
                    ),
              ),
              const Spacer(),
              Text(
                isChinese
                    ? '第 $page 页 / 共 ${_totalPages(total, pageSize)} 页'
                    : 'Page $page / ${_totalPages(total, pageSize)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isChinese ? '创建时间' : 'Created At',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    isChinese ? '订单金额' : 'Order Amount',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  isChinese ? '佣金金额' : 'Amount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (records.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 38),
                child: Text(
                  isChinese ? '没有历史记录' : 'No records yet',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            )
          else
            ...records.map(
              (record) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _CommissionRecordRow(
                  record: record,
                  moneyFormatter: moneyFormatter,
                ),
              ),
            ),
          if (records.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _PageButton(
                  label: isChinese ? '上一页' : 'Previous',
                  enabled: page > 1,
                  onTap: () => onPageChanged(page - 1),
                ),
                const SizedBox(width: 10),
                _PageButton(
                  label: isChinese ? '下一页' : 'Next',
                  enabled: hasMore,
                  onTap: () => onPageChanged(page + 1),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CommissionRecordRow extends StatelessWidget {
  const _CommissionRecordRow({
    required this.record,
    required this.moneyFormatter,
  });

  final WebInviteRecordData record;
  final String Function(int cents) moneyFormatter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              Formatters.formatEpoch(record.createdAt),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              moneyFormatter(record.orderAmount),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            moneyFormatter(record.amount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _TransferButton extends StatelessWidget {
  const _TransferButton({
    this.cardKey,
    required this.enabled,
    required this.isLoading,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key? cardKey;
  final bool enabled;
  final bool isLoading;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? AppColors.textPrimary
        : AppColors.textSecondary.withValues(alpha: 0.56);
    return AnimatedCard(
      key: cardKey,
      onTap: enabled ? onTap : null,
      enableBreathing: false,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      gradientColors: enabled
          ? null
          : [
              AppColors.surface.withValues(alpha: 0.48),
              AppColors.surfaceAlt.withValues(alpha: 0.28),
            ],
      baseBorderColor: enabled ? null : AppColors.border.withValues(alpha: 0.7),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(
                icon,
                size: 18,
                color: enabled ? AppColors.accent : foreground,
              ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DialogCardButton(
      label: label,
      emphasized: false,
      onTap: enabled ? onTap : null,
    );
  }
}

class _TransferAmountDialog extends StatefulWidget {
  const _TransferAmountDialog({
    required this.isChinese,
    required this.maxAmountCents,
    required this.moneyFormatter,
  });

  final bool isChinese;
  final int maxAmountCents;
  final String Function(int cents) moneyFormatter;

  @override
  State<_TransferAmountDialog> createState() => _TransferAmountDialogState();
}

class _TransferAmountDialogState extends State<_TransferAmountDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = _parseAmountToCents(_controller.text);
    if (amount == null || amount <= 0) {
      setState(() {
        _error = widget.isChinese ? '请输入正确金额。' : 'Enter a valid amount.';
      });
      return;
    }
    if (amount > widget.maxAmountCents) {
      setState(() {
        _error = widget.isChinese
            ? '输入金额超出可转范围。'
            : 'The amount exceeds the available commission.';
      });
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = widget.isChinese;
    return Dialog(
      key: const Key('web-invite-transfer-amount-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isChinese ? '自定义转入金额' : 'Custom Transfer Amount',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 34,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                isChinese
                    ? '当前最多可转入 ${widget.moneyFormatter(widget.maxAmountCents)}。'
                    : 'You can transfer up to ${widget.moneyFormatter(widget.maxAmountCents)}.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 22),
              TextField(
                key: const Key('web-invite-transfer-amount-input'),
                controller: _controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: isChinese ? '输入金额' : 'Amount',
                  hintText:
                      isChinese ? '例如 10 或 10.50' : 'For example 10 or 10.50',
                  errorText: _error,
                  prefixText: '¥ ',
                  filled: true,
                  fillColor: AppColors.surfaceAlt.withValues(alpha: 0.72),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _DialogCardButton(
                      label: isChinese ? '取消' : 'Cancel',
                      emphasized: false,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogCardButton(
                      key: const Key(
                          'web-invite-transfer-amount-confirm-button'),
                      label: isChinese ? '确认转入' : 'Transfer',
                      emphasized: true,
                      onTap: _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferConfirmDialog extends StatelessWidget {
  const _TransferConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-invite-transfer-confirm-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 34,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 17,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 360;
                  final buttons = [
                    _DialogCardButton(
                      key: const Key('web-invite-transfer-cancel-button'),
                      label: cancelLabel,
                      emphasized: false,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                    _DialogCardButton(
                      key: const Key('web-invite-transfer-confirm-button'),
                      label: confirmLabel,
                      emphasized: true,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ];

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buttons[1],
                        const SizedBox(height: 12),
                        buttons[0],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: buttons[0]),
                      const SizedBox(width: 12),
                      Expanded(child: buttons[1]),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WithdrawDialog extends StatefulWidget {
  const _WithdrawDialog({
    required this.isChinese,
    required this.methods,
    required this.amountLabel,
  });

  final bool isChinese;
  final List<String> methods;
  final String amountLabel;

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  late String _selectedMethod;
  final TextEditingController _accountController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.methods.first;
  }

  @override
  void dispose() {
    _accountController.dispose();
    super.dispose();
  }

  void _submit() {
    final account = _accountController.text.trim();
    if (account.isEmpty) {
      setState(() {
        _error = widget.isChinese ? '请填写提现账号。' : 'Enter withdrawal account.';
      });
      return;
    }
    Navigator.of(context).pop(
      WebWithdrawalRequest(method: _selectedMethod, account: account),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = widget.isChinese;
    return Dialog(
      key: const Key('web-invite-withdraw-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isChinese ? '佣金提现' : 'Withdraw Commission',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 34,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                isChinese
                    ? '当前可提现佣金：${widget.amountLabel}'
                    : 'Available commission: ${widget.amountLabel}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 22),
              Text(
                isChinese ? '选择提现方式' : 'Withdrawal Method',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final method in widget.methods)
                    _WithdrawMethodChip(
                      method: method,
                      selected: method == _selectedMethod,
                      onTap: () => setState(() => _selectedMethod = method),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                isChinese ? '提现账号' : 'Withdrawal Account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  key: const Key('web-invite-withdraw-account-field'),
                  controller: _accountController,
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    hintText: isChinese ? '请输入收款账号' : 'Enter payout account',
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.accent,
                      ),
                ),
              ],
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 360;
                  final cancel = _DialogCardButton(
                    key: const Key('web-invite-withdraw-cancel-button'),
                    label: isChinese ? '取消' : 'Cancel',
                    emphasized: false,
                    onTap: () => Navigator.of(context).pop(),
                  );
                  final submit = _DialogCardButton(
                    key: const Key('web-invite-withdraw-submit-button'),
                    label: isChinese ? '提交提现' : 'Submit',
                    emphasized: true,
                    onTap: _submit,
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        submit,
                        const SizedBox(height: 12),
                        cancel,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: cancel),
                      const SizedBox(width: 12),
                      Expanded(child: submit),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WithdrawMethodChip extends StatelessWidget {
  const _WithdrawMethodChip({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final String method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      onTap: onTap,
      enableBreathing: false,
      borderRadius: 18,
      hoverScale: 1.01,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      gradientColors: selected
          ? null
          : [
              AppColors.surface.withValues(alpha: 0.5),
              AppColors.surfaceAlt.withValues(alpha: 0.34),
            ],
      baseBorderColor:
          selected ? null : AppColors.border.withValues(alpha: 0.82),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18,
            color: selected ? AppColors.accent : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            method,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                ),
          ),
        ],
      ),
    );
  }
}

class _DialogCardButton extends StatelessWidget {
  const _DialogCardButton({
    super.key,
    required this.label,
    required this.emphasized,
    required this.onTap,
  });

  final String label;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor =
        emphasized ? AppColors.textPrimary : AppColors.textSecondary;
    return SizedBox(
      height: 52,
      child: AnimatedCard(
        onTap: onTap,
        enableBreathing: false,
        borderRadius: 18,
        hoverScale: 1.01,
        padding: EdgeInsets.zero,
        gradientColors: emphasized
            ? null
            : [
                AppColors.surface.withValues(alpha: 0.62),
                AppColors.surfaceAlt.withValues(alpha: 0.44),
              ],
        baseBorderColor:
            emphasized ? null : AppColors.border.withValues(alpha: 0.85),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteStatBlock extends StatelessWidget {
  const _InviteStatBlock({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontSize: 44,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetaStat extends StatelessWidget {
  const _MetaStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 22,
                ),
          ),
        ],
      ),
    );
  }
}

class _InviteErrorState extends StatelessWidget {
  const _InviteErrorState({
    required this.isChinese,
    required this.message,
    required this.onReload,
  });

  final bool isChinese;
  final String message;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GradientCard(
        borderRadius: 30,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline_rounded,
              color: AppColors.textSecondary,
              size: 46,
            ),
            const SizedBox(height: 18),
            Text(
              isChinese ? '邀请页加载失败' : 'Failed to load invite content',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 28,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isChinese ? '重新加载' : 'Reload'),
            ),
          ],
        ),
      ),
    );
  }
}

int _totalPages(int total, int pageSize) {
  if (total <= 0 || pageSize <= 0) return 1;
  return ((total + pageSize - 1) / pageSize).ceil();
}

int? _parseAmountToCents(String raw) {
  final normalized = raw.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || value <= 0) return null;
  return (value * 100).round();
}

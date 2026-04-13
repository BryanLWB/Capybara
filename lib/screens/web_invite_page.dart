import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/web_mock_content.dart';
import '../theme/app_colors.dart';
import '../widgets/action_button.dart';
import '../widgets/animated_card.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_page_frame.dart';

class WebInvitePage extends StatelessWidget {
  const WebInvitePage({super.key});

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  Future<void> _copyInvite(BuildContext context, bool isChinese) async {
    await Clipboard.setData(
      ClipboardData(text: webInviteMock.inviteUrl),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isChinese ? '邀请码已复制到剪贴板。' : 'Invite link copied to clipboard.',
        ),
      ),
    );
  }

  void _showPendingAction(BuildContext context, bool isChinese) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isChinese
              ? '壳子阶段先不接真实提现与转余额操作。'
              : 'Withdraw and balance transfer stay disabled in the shell stage.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final wide = MediaQuery.of(context).size.width >= 1080;

    return WebPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GradientCard(
            borderRadius: 32,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InviteStatBlock(
                        title: isChinese ? '当前剩余佣金' : 'Available Commission',
                        value: webInviteMock.currentCommission,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _InviteStatBlock(
                        title: isChinese ? '累计获得佣金' : 'Total Commission',
                        value: webInviteMock.totalCommission,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        key: const Key('web-invite-withdraw-button'),
                        child: ActionButton(
                          icon: Icons.account_balance_wallet_outlined,
                          label: isChinese ? '佣金提现' : 'Withdraw Commission',
                          onPressed: () =>
                              _showPendingAction(context, isChinese),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedCard(
                        key: const Key('web-invite-transfer-button'),
                        onTap: () => _showPendingAction(context, isChinese),
                        enableBreathing: false,
                        borderRadius: 12,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        gradientColors: [
                          Colors.white.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.08),
                        ],
                        baseBorderColor: Colors.white.withValues(alpha: 0.2),
                        hoverBorderColor: AppColors.accent.withValues(
                          alpha: 0.6,
                        ),
                        baseBoxShadows: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        hoverBoxShadows: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.25),
                            blurRadius: 30,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.swap_horiz_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.87),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isChinese ? '转为余额' : 'Transfer to Balance',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.87),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
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
                              webInviteMock.inviteUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontSize: 18,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () => _copyInvite(context, isChinese),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: Text(
                              isChinese ? '复制邀请码' : 'Copy Invite Link',
                            ),
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
                                value: '${webInviteMock.invitedUsers}',
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: _MetaStat(
                                label: isChinese ? '佣金比例' : 'Commission Rate',
                                value: webInviteMock.commissionRate,
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _MetaStat(
                              label: isChinese ? '已邀请用户数' : 'Invited Users',
                              value: '${webInviteMock.invitedUsers}',
                            ),
                            const SizedBox(height: 12),
                            _MetaStat(
                              label: isChinese ? '佣金比例' : 'Commission Rate',
                              value: webInviteMock.commissionRate,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GradientCard(
            borderRadius: 30,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isChinese ? '佣金发放记录' : 'Commission Records',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 30,
                              ),
                    ),
                    const Spacer(),
                    Text(
                      isChinese ? '每页显示数量：10' : 'Rows per page: 10',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                      Text(
                        isChinese ? '佣金金额' : 'Amount',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 38),
                    child: Text(
                      isChinese ? '没有历史记录' : 'No records yet',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 28,
                                color: AppColors.textSecondary,
                              ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

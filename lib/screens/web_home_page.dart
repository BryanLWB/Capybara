import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/web_client_download.dart';
import '../models/web_home_view_data.dart';
import '../models/web_shell_section.dart';
import '../services/api_config.dart';
import '../services/app_api.dart';
import '../services/panel_api.dart';
import '../services/web_app_facade.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/animated_card.dart';
import '../widgets/capybara_loader.dart';
import '../widgets/gradient_card.dart';

typedef WebHomeDataLoader = Future<WebHomeViewData> Function(bool forceRefresh);
typedef WebSubscriptionAccessLinkCreator = Future<String> Function(
    String? flag);
typedef WebClientDownloadsLoader = Future<List<WebClientDownloadItem>>
    Function();

class WebHomePage extends StatefulWidget {
  const WebHomePage({
    super.key,
    required this.onNavigate,
    required this.onUnauthorized,
    this.dataLoader,
    this.subscriptionLinkCreator,
    this.downloadsLoader,
  });

  final ValueChanged<WebShellSection> onNavigate;
  final VoidCallback onUnauthorized;
  final WebHomeDataLoader? dataLoader;
  final WebSubscriptionAccessLinkCreator? subscriptionLinkCreator;
  final WebClientDownloadsLoader? downloadsLoader;

  @override
  State<WebHomePage> createState() => _WebHomePageState();
}

class _WebHomePageState extends State<WebHomePage> {
  final _facade = WebAppFacade();
  late Future<WebHomeViewData> _future;
  String _selectedPlatform = 'ios';
  bool _quickActionBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _load(false);
  }

  Future<WebHomeViewData> _load([bool forceRefresh = false]) async {
    if (widget.dataLoader != null) {
      return widget.dataLoader!(forceRefresh);
    }

    return _facade.loadHomeData(forceRefresh: forceRefresh);
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  void _handleUnauthorized() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ApiConfig().clearAuth();
      if (mounted) {
        widget.onUnauthorized();
      }
    });
  }

  Future<String> _createAccessLink() async {
    final flag = _flagForPlatform(_selectedPlatform);
    if (widget.subscriptionLinkCreator != null) {
      return widget.subscriptionLinkCreator!(flag);
    }
    return _facade.createSubscriptionAccessLink(flag: flag);
  }

  Future<List<WebClientDownloadItem>> _loadDownloads() async {
    if (widget.downloadsLoader != null) {
      return widget.downloadsLoader!();
    }
    return _facade.loadClientDownloads();
  }

  Future<void> _copySubscriptionLink(bool isChinese) async {
    if (_quickActionBusy) return;
    setState(() => _quickActionBusy = true);
    try {
      final link = await _createAccessLink();
      if (link.isEmpty) {
        throw AppApiException(statusCode: 502, message: 'Request failed');
      }
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      _showSnack(
        isChinese ? '订阅链接已复制到剪贴板。' : 'Subscription link copied.',
      );
    } catch (error) {
      _handleQuickActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _quickActionBusy = false);
    }
  }

  Future<void> _showSubscriptionQr(bool isChinese) async {
    if (_quickActionBusy) return;
    setState(() => _quickActionBusy = true);
    try {
      final link = await _createAccessLink();
      if (link.isEmpty) {
        throw AppApiException(statusCode: 502, message: 'Request failed');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _SubscriptionQrDialog(
          title: isChinese ? '二维码订阅' : 'QR Subscribe',
          subtitle: isChinese
              ? '使用客户端扫描此二维码导入订阅。'
              : 'Scan this code with a client to import the subscription.',
          closeLabel: isChinese ? '关闭' : 'Close',
          link: link,
        ),
      );
    } catch (error) {
      _handleQuickActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _quickActionBusy = false);
    }
  }

  Future<void> _downloadClient(bool isChinese) async {
    if (_quickActionBusy) return;
    setState(() => _quickActionBusy = true);
    try {
      final downloads = await _loadDownloads();
      WebClientDownloadItem? selected;
      for (final item in downloads) {
        if (item.platform.toLowerCase() == _selectedPlatform) {
          selected = item;
          break;
        }
      }
      final url = selected?.downloadUrl;
      if (selected == null || !selected.available || url == null) {
        if (!mounted) return;
        _showSnack(
          isChinese
              ? '后台还没有配置该平台下载地址，已切到帮助页。'
              : 'No download is configured for this platform. Opening Help.',
        );
        widget.onNavigate(WebShellSection.help);
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null) {
        throw AppApiException(statusCode: 502, message: 'Request failed');
      }
      final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
      if (!opened && mounted) {
        _showSnack(isChinese ? '无法打开下载地址。' : 'Unable to open download.');
      }
    } catch (error) {
      _handleQuickActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _quickActionBusy = false);
    }
  }

  void _handleQuickActionError(Object error, bool isChinese) {
    if (error is AppApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      _handleUnauthorized();
      return;
    }
    if (!mounted) return;
    _showSnack(error.toString());
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _flagForPlatform(String platform) {
    switch (platform) {
      case 'ios':
        return 'shadowrocket';
      case 'android':
        return 'clashmetaforandroid';
      case 'macos':
        return 'clash';
      case 'windows':
        return 'clash';
      default:
        return 'clash';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);

    return FutureBuilder<WebHomeViewData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is PanelApiException &&
              (error.statusCode == 401 || error.statusCode == 403)) {
            _handleUnauthorized();
            return const Center(child: CapybaraLoader());
          }
          return _buildErrorState(context, isChinese, '$error');
        }

        if (!snapshot.hasData) {
          return const Center(child: CapybaraLoader(showTips: true));
        }

        final data = snapshot.data!;
        final width = MediaQuery.of(context).size.width;
        final isWide = width >= 1180;
        final isMedium = width >= 900;
        const desktopPanelHeight = 560.0;

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _future = _load(true);
            });
            await _future;
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              isWide ? 24 : 16,
              16,
              isWide ? 24 : 16,
              88,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNoticeCard(context, data, isChinese),
                    const SizedBox(height: 16),
                    _buildSubscriptionCard(context, data, isChinese),
                    const SizedBox(height: 16),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: desktopPanelHeight,
                              child: _buildQuickUsageSection(
                                context,
                                isChinese,
                                dense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: desktopPanelHeight,
                              child: _buildQuickLinksSection(
                                context,
                                isChinese,
                                true,
                                dense: true,
                              ),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildQuickUsageSection(context, isChinese),
                      const SizedBox(height: 16),
                      _buildQuickLinksSection(context, isChinese, isMedium),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    bool isChinese,
    String message,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GradientCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  color: AppColors.accentWarm,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(
                  isChinese ? '主页数据加载失败' : 'Failed to load dashboard data',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _future = _load(true);
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(isChinese ? '重新加载' : 'Reload'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeCard(
    BuildContext context,
    WebHomeViewData data,
    bool isChinese,
  ) {
    final latestNotice = data.latestNotice;
    final extraNotices = data.notices.skip(1).take(3).toList();

    return GradientCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                      icon: Icons.campaign_rounded,
                      text: isChinese ? '公告' : 'Announcements',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isChinese
                          ? '首页公告已同步面板最新内容'
                          : 'Latest panel notices synced into the web home',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              if (data.notices.isNotEmpty)
                _CountBadge(
                  label: isChinese
                      ? '共 ${data.notices.length} 条'
                      : '${data.notices.length} total',
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (latestNotice == null)
            _buildEmptyCard(
              context,
              icon: Icons.campaign_outlined,
              title: isChinese ? '暂无公告' : 'No announcements yet',
              subtitle: isChinese
                  ? '面板还没有发布公告，后续内容会直接显示在这里。'
                  : 'No notice has been published yet. New items will appear here automatically.',
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.14),
                    AppColors.surfaceAlt.withValues(alpha: 0.88),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CountBadge(
                        label: isChinese ? '最新公告' : 'Latest Notice',
                        compact: true,
                      ),
                      const Spacer(),
                      Text(
                        Formatters.formatEpoch(latestNotice.createdAt),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    latestNotice.title.isEmpty
                        ? (isChinese ? '系统公告' : 'System Notice')
                        : latestNotice.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                          height: 1.1,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    latestNotice.body.isEmpty
                        ? (isChinese
                            ? '该公告暂无详细内容。'
                            : 'No detailed content provided for this notice.')
                        : latestNotice.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
                  ),
                  if (extraNotices.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: extraNotices
                          .map(
                            (notice) => _NoticeChip(
                              label: notice.title.isEmpty
                                  ? (isChinese ? '未命名公告' : 'Untitled Notice')
                                  : notice.title,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(
    BuildContext context,
    WebHomeViewData data,
    bool isChinese,
  ) {
    return GradientCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionLabel(
                  icon: Icons.inventory_2_outlined,
                  text: isChinese ? '订阅概览' : 'Subscription',
                ),
              ),
              _CountBadge(
                label: data.hasSubscription
                    ? (isChinese ? '已开通' : 'Active')
                    : (isChinese ? '待购买' : 'Pending'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!data.hasSubscription)
            _InteractiveSubscriptionPlaceholder(
              title: isChinese ? '你还没有有效订阅' : 'No active subscription',
              subtitle: isChinese
                  ? '悬浮后点击这张卡片，直接跳转到购买页面。'
                  : 'Hover and click this card to jump to the purchase page.',
              onTap: () => widget.onNavigate(WebShellSection.purchase),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    label: isChinese ? '当前套餐' : 'Current Plan',
                    value: data.planName.isEmpty
                        ? (isChinese ? '已开通' : 'Active')
                        : data.planName,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricPill(
                    label: isChinese ? '余额' : 'Balance',
                    value: Formatters.formatCurrency(data.balance),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isChinese ? '流量使用' : 'Traffic Usage',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                        ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    minHeight: 10,
                    value: data.usagePercent,
                    backgroundColor: AppColors.surface,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${Formatters.formatBytes(data.usedBytes)} / ${Formatters.formatBytes(data.totalBytes)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    label: isChinese ? '上传' : 'Upload',
                    value: Formatters.formatBytes(data.uploadBytes),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricPill(
                    label: isChinese ? '下载' : 'Download',
                    value: Formatters.formatBytes(data.downloadBytes),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    label: isChinese ? '到期时间' : 'Expiry Date',
                    value: Formatters.formatEpoch(data.expiryAt),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricPill(
                    label: isChinese ? '重置日' : 'Reset Day',
                    value: data.resetDay > 0
                        ? data.resetDay.toString()
                        : (isChinese ? '未设置' : 'N/A'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickUsageSection(
    BuildContext context,
    bool isChinese, {
    bool dense = false,
  }) {
    final platformButtons = [
      const _PlatformOption(keyName: 'ios', label: 'iOS'),
      const _PlatformOption(keyName: 'android', label: 'Android'),
      const _PlatformOption(keyName: 'macos', label: 'macOS'),
      const _PlatformOption(keyName: 'windows', label: 'Windows'),
    ];

    final actions = [
      _UsageAction(
        icon: Icons.download_rounded,
        title: isChinese ? '下载客户端' : 'Download Client',
        subtitle: isChinese
            ? '从后台配置的下载入口获取当前平台客户端。'
            : 'Open the configured download for the selected platform.',
        statusLabel: _quickActionBusy
            ? (isChinese ? '处理中' : 'Working')
            : (isChinese ? '打开' : 'Open'),
        onTap: () => _downloadClient(isChinese),
      ),
      _UsageAction(
        icon: Icons.link_rounded,
        title: isChinese ? '复制订阅链接' : 'Copy Subscription Link',
        subtitle: isChinese
            ? '复制中性订阅链接，不暴露上游面板地址。'
            : 'Copy a neutral subscription link without exposing upstream.',
        statusLabel: _quickActionBusy
            ? (isChinese ? '处理中' : 'Working')
            : (isChinese ? '复制' : 'Copy'),
        onTap: () => _copySubscriptionLink(isChinese),
      ),
      _UsageAction(
        icon: Icons.qr_code_2_rounded,
        title: isChinese ? '二维码订阅' : 'QR Subscribe',
        subtitle: isChinese
            ? '生成当前平台可用的中性订阅二维码。'
            : 'Generate a neutral subscription QR for this platform.',
        statusLabel: _quickActionBusy
            ? (isChinese ? '处理中' : 'Working')
            : (isChinese ? '生成' : 'Show'),
        onTap: () => _showSubscriptionQr(isChinese),
      ),
    ];

    return GradientCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon: Icons.link_rounded,
            text: isChinese ? '开始使用' : 'Quick Start',
          ),
          const SizedBox(height: 10),
          Text(
            isChinese
                ? '选择平台后，可以下载客户端、复制订阅或扫码导入。'
                : 'Choose a platform, then download, copy, or import by QR.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          SizedBox(height: dense ? 10 : 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: platformButtons
                .map(
                  (platform) => _PlatformGhostButton(
                    label: platform.label,
                    selected: _selectedPlatform == platform.keyName,
                    onTap: () {
                      setState(() => _selectedPlatform = platform.keyName);
                    },
                  ),
                )
                .toList(),
          ),
          SizedBox(height: dense ? 10 : 14),
          Column(
            children: actions
                .map(
                  (action) => Padding(
                    padding: EdgeInsets.only(bottom: dense ? 6 : 10),
                    child: _UsageActionTile(
                      title: action.title,
                      subtitle: action.subtitle,
                      icon: action.icon,
                      statusLabel: action.statusLabel,
                      onTap: _quickActionBusy ? null : action.onTap,
                      dense: dense,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinksSection(
    BuildContext context,
    bool isChinese,
    bool isMedium, {
    bool dense = false,
  }) {
    final cards = [
      _QuickLinkCardData(
        section: WebShellSection.purchase,
        title: isChinese ? '购买套餐' : 'Purchase',
        subtitle: isChinese ? '查看套餐与购买流程。' : 'Check plans and purchase flow.',
      ),
      _QuickLinkCardData(
        section: WebShellSection.help,
        title: isChinese ? '帮助中心' : 'Help Center',
        subtitle: isChinese
            ? '查看帮助内容或使用右下角客服。'
            : 'Open help content or use the Crisp bubble.',
      ),
      _QuickLinkCardData(
        section: WebShellSection.invite,
        title: isChinese ? '邀请返利' : 'Invite Program',
        subtitle: isChinese
            ? '邀请与返利入口将在这里补齐。'
            : 'Referral entry will be completed here.',
      ),
      _QuickLinkCardData(
        section: WebShellSection.account,
        title: isChinese ? '账号设置' : 'Account',
        subtitle: isChinese
            ? '个人资料与偏好后续集中放这里。'
            : 'Profile and preferences will live here later.',
      ),
    ];

    return GradientCard(
      padding: EdgeInsets.all(dense ? 18 : 20),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon: Icons.dashboard_customize_outlined,
            text: isChinese ? '快捷入口' : 'Shortcuts',
          ),
          SizedBox(height: dense ? 12 : 14),
          if (dense)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final rowSpacing = 12.0;
                  final cardHeight = isMedium
                      ? ((constraints.maxHeight - rowSpacing) / 2)
                          .clamp(170.0, 260.0)
                      : 154.0;

                  return _buildQuickLinksGrid(
                    context,
                    cards: cards,
                    isMedium: isMedium,
                    mainAxisExtent: cardHeight,
                  );
                },
              ),
            )
          else
            _buildQuickLinksGrid(
              context,
              cards: cards,
              isMedium: isMedium,
              shrinkWrap: true,
              mainAxisExtent: isMedium ? 196 : 154,
            ),
        ],
      ),
    );
  }

  Widget _buildQuickLinksGrid(
    BuildContext context, {
    required List<_QuickLinkCardData> cards,
    required bool isMedium,
    required double mainAxisExtent,
    bool shrinkWrap = false,
  }) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMedium ? 2 : 1,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: mainAxisExtent,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return AnimatedCard(
          onTap: () => widget.onNavigate(card.section),
          padding: const EdgeInsets.all(18),
          enableBreathing: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.accent.withValues(alpha: 0.14),
                    ),
                    child: Icon(
                      card.section.icon,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.arrow_outward_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                    ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    card.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.border,
          width: 1,
        ),
        color: AppColors.surfaceAlt.withValues(alpha: 0.64),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent, size: 28),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 20,
              ),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}

class _InteractiveSubscriptionPlaceholder extends StatelessWidget {
  const _InteractiveSubscriptionPlaceholder({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      key: const Key('web-subscription-empty-card'),
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      enableBreathing: false,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: AppColors.accent.withValues(alpha: 0.14),
            ),
            child: const Icon(
              Icons.add_shopping_cart_rounded,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.arrow_forward_rounded,
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceAlt.withValues(alpha: 0.6),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlatformGhostButton extends StatelessWidget {
  const _PlatformGhostButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.16)
                : AppColors.surfaceAlt.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      selected ? AppColors.textPrimary : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _PlatformOption {
  const _PlatformOption({
    required this.keyName,
    required this.label,
  });

  final String keyName;
  final String label;
}

class _SubscriptionQrDialog extends StatelessWidget {
  const _SubscriptionQrDialog({
    required this.title,
    required this.subtitle,
    required this.closeLabel,
    required this.link,
  });

  final String title;
  final String subtitle;
  final String closeLabel;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-home-subscription-qr-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GradientCard(
          borderRadius: 32,
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 30,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: QrImageView(
                    data: link,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                link,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: AnimatedCard(
                  onTap: () => Navigator.of(context).pop(),
                  enableBreathing: false,
                  borderRadius: 18,
                  hoverScale: 1.01,
                  padding: EdgeInsets.zero,
                  child: Center(
                    child: Text(
                      closeLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageAction {
  const _UsageAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String statusLabel;
  final VoidCallback onTap;
}

class _UsageActionTile extends StatelessWidget {
  const _UsageActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.statusLabel,
    required this.onTap,
    this.dense = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String statusLabel;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      width: double.infinity,
      padding: EdgeInsets.all(dense ? 10 : 14),
      onTap: onTap,
      enableBreathing: false,
      borderRadius: 18,
      hoverScale: 1.01,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.accent.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 20, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                      ),
                ),
                SizedBox(height: dense ? 4 : 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _CountBadge(label: statusLabel, compact: true),
        ],
      ),
    );
  }
}

class _NoticeChip extends StatelessWidget {
  const _NoticeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
      ),
    );
  }
}

class _QuickLinkCardData {
  const _QuickLinkCardData({
    required this.section,
    required this.title,
    required this.subtitle,
  });

  final WebShellSection section;
  final String title;
  final String subtitle;
}

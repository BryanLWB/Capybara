import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/web_client_import_option.dart';
import '../models/web_client_download.dart';
import '../models/web_home_view_data.dart';
import '../models/web_shell_section.dart';
import '../services/api_config.dart';
import '../services/app_api.dart';
import '../services/panel_api.dart';
import '../services/web_app_facade.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/web_error_text.dart';
import '../widgets/animated_card.dart';
import '../widgets/capybara_loader.dart';
import '../widgets/gradient_card.dart';
import '../widgets/rich_content_view.dart';
import '../widgets/web_layout_metrics.dart';
import '../widgets/web_page_frame.dart';

typedef WebHomeDataLoader = Future<WebHomeViewData> Function(bool forceRefresh);
typedef WebSubscriptionAccessLinkCreator = Future<String> Function(
    String? flag);
typedef WebClientDownloadsLoader = Future<List<WebClientDownloadItem>>
    Function();
typedef WebClientImportOptionsLoader = Future<List<WebClientImportOptionData>>
    Function(String platform);

class WebHomePage extends StatefulWidget {
  const WebHomePage({
    super.key,
    required this.onNavigate,
    required this.onUnauthorized,
    this.dataLoader,
    this.subscriptionLinkCreator,
    this.downloadsLoader,
    this.importOptionsLoader,
  });

  final ValueChanged<WebShellSection> onNavigate;
  final VoidCallback onUnauthorized;
  final WebHomeDataLoader? dataLoader;
  final WebSubscriptionAccessLinkCreator? subscriptionLinkCreator;
  final WebClientDownloadsLoader? downloadsLoader;
  final WebClientImportOptionsLoader? importOptionsLoader;

  @override
  State<WebHomePage> createState() => _WebHomePageState();
}

class _WebHomePageState extends State<WebHomePage> {
  final _facade = WebAppFacade();
  late Future<WebHomeViewData> _future;
  String _selectedPlatform = 'ios';
  bool _quickActionBusy = false;
  Future<List<WebClientDownloadItem>>? _downloadsFuture;
  final Map<String, Future<String>> _subscriptionLinkFutures =
      <String, Future<String>>{};
  final Map<String, Future<List<WebClientImportOptionData>>>
      _importOptionsFutures =
      <String, Future<List<WebClientImportOptionData>>>{};
  Timer? _noticeTimer;
  int _noticeIndex = 0;
  int _noticeCount = 0;
  bool _noticeDialogOpen = false;
  String _noticeSignature = '';

  @override
  void initState() {
    super.initState();
    _future = _load(false);
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
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
    return _subscriptionLinkFutures.putIfAbsent(flag, () async {
      try {
        final link = widget.subscriptionLinkCreator != null
            ? await widget.subscriptionLinkCreator!(flag)
            : await _facade.createSubscriptionAccessLink(flag: flag);
        if (link.isEmpty) {
          _subscriptionLinkFutures.remove(flag);
        }
        return link;
      } catch (_) {
        _subscriptionLinkFutures.remove(flag);
        rethrow;
      }
    });
  }

  Future<List<WebClientDownloadItem>> _loadDownloads() async {
    final existing = _downloadsFuture;
    if (existing != null) {
      return existing;
    }
    final future = () async {
      try {
        if (widget.downloadsLoader != null) {
          return await widget.downloadsLoader!();
        }
        return await _facade.loadClientDownloads();
      } catch (_) {
        _downloadsFuture = null;
        rethrow;
      }
    }();
    _downloadsFuture = future;
    return future;
  }

  Future<List<WebClientImportOptionData>> _loadImportOptions(
    String platform,
  ) async {
    if (widget.importOptionsLoader != null) {
      return widget.importOptionsLoader!(platform);
    }
    return _facade.loadClientImportOptions(platform);
  }

  Future<void> _copySubscriptionLink(
    bool isChinese, {
    required bool hasSubscription,
  }) async {
    if (_quickActionBusy) return;
    if (!hasSubscription) {
      _showSnack(isChinese ? '开通套餐后即可使用订阅链接。' : 'Subscription unavailable.');
      return;
    }
    setState(() => _quickActionBusy = true);
    try {
      final link = await _createAccessLink();
      if (link.isEmpty) {
        if (!mounted) return;
        _showSnack(
          isChinese
              ? '暂时无法获取订阅链接，请稍后再试。'
              : 'The subscription link is not available right now. Please try again later.',
        );
        return;
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

  Future<void> _showSubscriptionQr(
    bool isChinese, {
    required bool hasSubscription,
  }) async {
    if (_quickActionBusy) return;
    if (!hasSubscription) {
      _showSnack(isChinese ? '开通套餐后即可使用订阅链接。' : 'Subscription unavailable.');
      return;
    }
    setState(() => _quickActionBusy = true);
    try {
      final link = await _createAccessLink();
      if (link.isEmpty) {
        if (!mounted) return;
        _showSnack(
          isChinese
              ? '暂时无法生成二维码，请稍后再试。'
              : 'The QR code is not available right now. Please try again later.',
        );
        return;
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
              ? '当前平台暂未提供下载入口，已为你打开帮助中心。'
              : 'This platform download is not available right now. Opening Help.',
        );
        widget.onNavigate(WebShellSection.help);
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null) {
        if (!mounted) return;
        _showSnack(
          isChinese
              ? '下载入口暂时不可用，请稍后再试。'
              : 'The download link is not available right now. Please try again later.',
        );
        return;
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

  Future<void> _openClientImport(
    WebClientImportOptionData option,
    bool isChinese, {
    required bool hasSubscription,
  }) async {
    if (_quickActionBusy) return;
    if (!hasSubscription) {
      _showSnack(isChinese ? '开通套餐后即可使用导入功能。' : 'Subscription unavailable.');
      return;
    }
    if (!option.supported || option.actionValue.isEmpty) {
      _showSnack(
        isChinese
            ? '当前客户端暂未提供导入入口，请先使用订阅链接。'
            : 'This client import option is not available right now.',
      );
      return;
    }

    setState(() => _quickActionBusy = true);
    try {
      if (option.isDeepLink) {
        final uri = Uri.tryParse(option.actionValue);
        if (uri == null || !uri.hasScheme) {
          throw StateError('client.import.deep_link.invalid');
        }
        final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
        if (!opened && mounted) {
          _showSnack(
            isChinese ? '无法打开导入入口。' : 'Unable to open the import action.',
          );
        }
      } else {
        await Clipboard.setData(ClipboardData(text: option.actionValue));
        if (mounted) {
          _showSnack(
            isChinese
                ? '${option.displayName} 导入链接已复制。'
                : '${option.displayName} import link copied.',
          );
        }
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
    _showSnack(
      webErrorText(
        error,
        isChinese: isChinese,
        context: WebErrorContext.quickAction,
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _syncNoticeRotation(List<WebNoticeViewData> notices) {
    final count = notices.length;
    final signature = notices
        .map((notice) =>
            '${notice.id}:${notice.createdAt}:${notice.title}:${notice.body}')
        .join('|');
    if (_noticeCount == count && _noticeSignature == signature) {
      return;
    }

    _noticeCount = count;
    _noticeSignature = signature;
    _noticeIndex = 0;
    _restartNoticeRotation();
  }

  void _restartNoticeRotation() {
    _noticeTimer?.cancel();
    if (_noticeCount <= 1) {
      return;
    }

    _noticeTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _noticeDialogOpen || _noticeCount <= 1) {
        return;
      }
      setState(() {
        _noticeIndex = (_noticeIndex + 1) % _noticeCount;
      });
    });
  }

  void _selectNotice(int index) {
    if (_noticeCount <= 0) {
      return;
    }
    setState(() {
      _noticeIndex = index % _noticeCount;
    });
    _restartNoticeRotation();
  }

  Future<void> _openNoticeDialog(
    WebNoticeViewData notice,
    bool isChinese,
  ) async {
    _noticeDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => _NoticeDetailDialog(
          notice: notice,
          isChinese: isChinese,
        ),
      );
    } finally {
      _noticeDialogOpen = false;
      _restartNoticeRotation();
    }
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
          return _buildErrorState(
            context,
            isChinese,
            webErrorText(
              error ?? StateError('home.load.failed'),
              isChinese: isChinese,
              context: WebErrorContext.pageLoad,
            ),
          );
        }

        if (!snapshot.hasData) {
          return _buildLoadingState(context, isChinese);
        }

        final data = snapshot.data!;
        _syncNoticeRotation(data.notices);
        final width = MediaQuery.of(context).size.width;
        final isWide = WebLayoutMetrics.useWidePanels(width);
        final isMedium = WebLayoutMetrics.useMediumGrid(width);
        final compact = WebLayoutMetrics.compact(width);
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _future = _load(true);
              _importOptionsFutures.clear();
            });
            await _future;
          },
          child: WebPageFrame(
            maxWidth: 1520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNoticeCard(context, data, isChinese),
                SizedBox(height: WebLayoutMetrics.sectionGap(width)),
                _buildSubscriptionCard(context, data, isChinese),
                SizedBox(height: WebLayoutMetrics.sectionGap(width)),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildQuickUsageSection(
                          context,
                          isChinese,
                          hasSubscription: data.hasSubscription,
                          dense: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildQuickLinksSection(
                          context,
                          isChinese,
                          true,
                          dense: true,
                        ),
                      ),
                    ],
                  )
                else ...[
                  _buildQuickUsageSection(
                    context,
                    isChinese,
                    hasSubscription: data.hasSubscription,
                    dense: compact,
                  ),
                  SizedBox(height: WebLayoutMetrics.sectionGap(width)),
                  _buildQuickLinksSection(
                    context,
                    isChinese,
                    isMedium,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(BuildContext context, bool isChinese) {
    final width = MediaQuery.of(context).size.width;
    final isWide = WebLayoutMetrics.useWidePanels(width);
    final compact = WebLayoutMetrics.compact(width);

    return WebPageFrame(
      key: const Key('web-home-loading-state'),
      maxWidth: 1520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLoadingCard(
            context,
            title: isChinese ? '公告' : 'Notices',
            subtitle: isChinese
                ? '页面已经可用，正在同步实时公告。'
                : 'The page is ready. Syncing the latest notices.',
            lines: const [0.42, 0.88, 0.72],
          ),
          SizedBox(height: WebLayoutMetrics.sectionGap(width)),
          _buildLoadingCard(
            context,
            title: isChinese ? '订阅概览' : 'Subscription overview',
            subtitle: isChinese
                ? '套餐、流量与到期时间会在后台同步。'
                : 'Plan, traffic, and expiry data are loading in the background.',
            lines: const [0.3, 0.64, 0.48, 0.82],
          ),
          SizedBox(height: WebLayoutMetrics.sectionGap(width)),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildLoadingCard(
                    context,
                    title: isChinese ? '快速开始' : 'Quick start',
                    lines:
                        compact ? const [0.74, 0.64] : const [0.84, 0.7, 0.56],
                    showLoader: false,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildLoadingCard(
                    context,
                    title: isChinese ? '常用入口' : 'Quick links',
                    lines:
                        compact ? const [0.76, 0.66] : const [0.8, 0.68, 0.6],
                    showLoader: false,
                  ),
                ),
              ],
            )
          else ...[
            _buildLoadingCard(
              context,
              title: isChinese ? '快速开始' : 'Quick start',
              lines: compact ? const [0.74, 0.64] : const [0.84, 0.7, 0.56],
              showLoader: false,
            ),
            SizedBox(height: WebLayoutMetrics.sectionGap(width)),
            _buildLoadingCard(
              context,
              title: isChinese ? '常用入口' : 'Quick links',
              lines: compact ? const [0.76, 0.66] : const [0.8, 0.68, 0.6],
              showLoader: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingCard(
    BuildContext context, {
    required String title,
    required List<double> lines,
    String? subtitle,
    bool showLoader = true,
  }) {
    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (showLoader) const CapybaraLoader(size: 20),
        ],
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
      const SizedBox(height: 20),
    ];

    for (var i = 0; i < lines.length; i++) {
      children.add(_buildLoadingLine(lines[i]));
      if (i != lines.length - 1) {
        children.add(const SizedBox(height: 12));
      }
    }

    return GradientCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildLoadingLine(double widthFactor) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
      ),
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
    final currentNotice = data.currentNoticeAt(_noticeIndex);
    final width = MediaQuery.of(context).size.width;
    final compact = WebLayoutMetrics.compact(width);
    final mediumDesktop = WebLayoutMetrics.mediumDesktop(width);

    return GradientCard(
      padding: EdgeInsets.all(mediumDesktop
          ? 14
          : compact
              ? 18
              : 20),
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
                    if (!mediumDesktop) ...[
                      const SizedBox(height: 10),
                      Text(
                        isChinese
                            ? '点击公告即可查看完整内容。'
                            : 'Tap an announcement to view the full message.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: mediumDesktop ? 13 : null,
                            ),
                      ),
                    ],
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
          SizedBox(height: mediumDesktop ? 10 : 16),
          if (currentNotice == null)
            _buildEmptyCard(
              context,
              icon: Icons.campaign_outlined,
              title: isChinese ? '暂无公告' : 'No announcements yet',
              subtitle: isChinese
                  ? '暂时还没有新的公告，新的通知会显示在这里。'
                  : 'There are no announcements right now. New updates will appear here.',
            )
          else
            AnimatedCard(
              key: Key('web-home-notice-card-${currentNotice.id}'),
              onTap: () => _openNoticeDialog(currentNotice, isChinese),
              padding: EdgeInsets.all(mediumDesktop ? 14 : 20),
              enableBreathing: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _CountBadge(
                        label: data.notices.length > 1
                            ? (isChinese
                                ? '第 ${(_noticeIndex % data.notices.length) + 1} / ${data.notices.length} 条'
                                : '${(_noticeIndex % data.notices.length) + 1} / ${data.notices.length}')
                            : (isChinese ? '最新公告' : 'Latest'),
                        compact: true,
                      ),
                      const Spacer(),
                      Text(
                        Formatters.formatEpoch(currentNotice.createdAt),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: mediumDesktop ? 10 : 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Text(
                      key: ValueKey(currentNotice.id),
                      currentNotice.title.isEmpty
                          ? (isChinese ? '系统公告' : 'System Announcement')
                          : currentNotice.title,
                      maxLines: mediumDesktop ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: mediumDesktop
                                    ? 20
                                    : compact
                                        ? 24
                                        : 28,
                                height: 1.1,
                              ),
                    ),
                  ),
                  if (!mediumDesktop) ...[
                    SizedBox(height: mediumDesktop ? 6 : 12),
                    Text(
                      isChinese
                          ? '点击查看公告详情'
                          : 'Tap to read the full announcement',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: mediumDesktop ? 12.5 : 14,
                          ),
                    ),
                  ],
                  if (data.notices.length > 1) ...[
                    SizedBox(height: mediumDesktop ? 10 : 16),
                    Center(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: List<Widget>.generate(
                          data.notices.length,
                          (index) => _NoticeDot(
                            key: Key('web-home-notice-dot-$index'),
                            active:
                                index == (_noticeIndex % data.notices.length),
                            onTap: () => _selectNotice(index),
                          ),
                        ),
                      ),
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
    final width = MediaQuery.of(context).size.width;
    final compact = WebLayoutMetrics.compact(width);
    final mediumDesktop = WebLayoutMetrics.mediumDesktop(width);
    return GradientCard(
      padding: EdgeInsets.all(mediumDesktop
          ? 14
          : compact
              ? 18
              : 20),
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
          SizedBox(height: mediumDesktop ? 10 : 16),
          if (!data.hasSubscription)
            _InteractiveSubscriptionPlaceholder(
              title: isChinese ? '你还没有有效订阅' : 'No active subscription',
              subtitle: isChinese
                  ? '点击这张卡片即可查看可选套餐。'
                  : 'Open this card to view available plans.',
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
            SizedBox(height: compact ? 12 : 14),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(mediumDesktop ? 12 : 16),
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
                          fontSize: mediumDesktop ? 14 : 16,
                        ),
                  ),
                  SizedBox(height: mediumDesktop ? 6 : 10),
                  LinearProgressIndicator(
                    minHeight: 10,
                    value: data.usagePercent,
                    backgroundColor: AppColors.surface,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  SizedBox(height: mediumDesktop ? 6 : 10),
                  Text(
                    '${Formatters.formatBytes(data.usedBytes)} / ${Formatters.formatBytes(data.totalBytes)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
            SizedBox(height: mediumDesktop ? 8 : 12),
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
            SizedBox(height: mediumDesktop ? 6 : 10),
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
    required bool hasSubscription,
    bool dense = false,
  }) {
    final width = MediaQuery.of(context).size.width;
    final compact = dense || WebLayoutMetrics.compact(width);
    final mediumDesktop = WebLayoutMetrics.mediumDesktop(width);
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
            ? '打开当前平台可用的客户端下载入口。'
            : 'Open the available download for the selected platform.',
        statusLabel: _quickActionBusy
            ? (isChinese ? '处理中' : 'Working')
            : (isChinese ? '打开' : 'Open'),
        onTap: () => _downloadClient(isChinese),
      ),
      _UsageAction(
        icon: Icons.link_rounded,
        title: isChinese ? '复制订阅链接' : 'Copy Subscription Link',
        subtitle: isChinese
            ? '复制可直接导入客户端的订阅链接。'
            : 'Copy a subscription link that can be imported into your client.',
        statusLabel: _quickActionBusy
            ? (isChinese ? '处理中' : 'Working')
            : (isChinese ? '复制' : 'Copy'),
        onTap: () => _copySubscriptionLink(
          isChinese,
          hasSubscription: hasSubscription,
        ),
      ),
      _UsageAction(
        icon: Icons.qr_code_2_rounded,
        title: isChinese ? '二维码订阅' : 'QR Subscribe',
        subtitle: isChinese
            ? '生成可用于导入客户端的订阅二维码。'
            : 'Generate a QR code for importing this subscription.',
        statusLabel: _quickActionBusy
            ? (isChinese ? '处理中' : 'Working')
            : (isChinese ? '生成' : 'Show'),
        onTap: () => _showSubscriptionQr(
          isChinese,
          hasSubscription: hasSubscription,
        ),
      ),
    ];
    final importOptionsFuture = hasSubscription
        ? (_importOptionsFutures[_selectedPlatform] ??=
            _loadImportOptions(_selectedPlatform))
        : null;

    return GradientCard(
      padding: EdgeInsets.all(mediumDesktop
          ? 14
          : compact
              ? 18
              : 20),
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
                  fontSize: mediumDesktop ? 13 : null,
                ),
          ),
          SizedBox(
              height: mediumDesktop
                  ? 6
                  : compact
                      ? 10
                      : 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: platformButtons
                .map(
                  (platform) => _PlatformGhostButton(
                    label: platform.label,
                    selected: _selectedPlatform == platform.keyName,
                    onTap: () {
                      setState(() {
                        _selectedPlatform = platform.keyName;
                      });
                    },
                  ),
                )
                .toList(),
          ),
          SizedBox(
              height: mediumDesktop
                  ? 6
                  : compact
                      ? 10
                      : 14),
          Column(
            children: actions
                .map(
                  (action) => Padding(
                    padding: EdgeInsets.only(bottom: compact ? 6 : 10),
                    child: _UsageActionTile(
                      title: action.title,
                      subtitle: action.subtitle,
                      icon: action.icon,
                      statusLabel: action.statusLabel,
                      onTap: _quickActionBusy ? null : action.onTap,
                      dense: compact,
                    ),
                  ),
                )
                .toList(),
          ),
          SizedBox(
              height: mediumDesktop
                  ? 6
                  : compact
                      ? 10
                      : 14),
          _SectionLabel(
            icon: Icons.rocket_launch_outlined,
            text: isChinese ? '一键导入' : 'Client Import',
          ),
          const SizedBox(height: 10),
          if (!hasSubscription)
            _QuickUsageHintCard(
              icon: Icons.lock_outline_rounded,
              message: isChinese
                  ? '开通套餐后，即可查看当前平台支持的一键导入客户端。'
                  : 'Activate a plan to unlock one-click client import.',
            )
          else
            FutureBuilder<List<WebClientImportOptionData>>(
              future: importOptionsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _QuickUsageHintCard(
                    icon: Icons.error_outline_rounded,
                    message: webErrorText(
                      snapshot.error!,
                      isChinese: isChinese,
                      context: WebErrorContext.quickAction,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: CapybaraLoader(size: 22),
                  );
                }

                final options =
                    snapshot.data ?? const <WebClientImportOptionData>[];
                if (options.isEmpty) {
                  return _QuickUsageHintCard(
                    icon: Icons.info_outline_rounded,
                    message: isChinese
                        ? '当前平台暂未提供专用导入入口，你仍可使用订阅链接导入。'
                        : 'No dedicated client import is available for this platform yet.',
                  );
                }

                return Column(
                  children: options
                      .map(
                        (option) => Padding(
                          padding: EdgeInsets.only(bottom: compact ? 6 : 10),
                          child: _ImportOptionTile(
                            option: option,
                            isChinese: isChinese,
                            onTap: _quickActionBusy
                                ? null
                                : () => _openClientImport(
                                      option,
                                      isChinese,
                                      hasSubscription: hasSubscription,
                                    ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
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
            ? '查看使用说明，或直接联系在线客服。'
            : 'Read help articles or contact support directly.',
      ),
      _QuickLinkCardData(
        section: WebShellSection.invite,
        title: isChinese ? '邀请返利' : 'Invite Program',
        subtitle: isChinese
            ? '查看邀请链接、返利和佣金记录。'
            : 'View your invite link, rewards, and commission records.',
      ),
      _QuickLinkCardData(
        section: WebShellSection.account,
        title: isChinese ? '用户中心' : 'User Center',
        subtitle: isChinese
            ? '管理余额、通知、订单与账户安全设置。'
            : 'Manage balance, notifications, orders, and account security.',
      ),
    ];

    return GradientCard(
      padding: EdgeInsets.all(dense ? 16 : 18),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon: Icons.dashboard_customize_outlined,
            text: isChinese ? '快捷入口' : 'Shortcuts',
          ),
          SizedBox(height: dense ? 10 : 12),
          _buildQuickLinksGrid(
            context,
            cards: cards,
            isMedium: isMedium,
            shrinkWrap: true,
            mainAxisExtent:
                isMedium ? (dense ? 156 : 172) : (dense ? 132 : 140),
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
    final width = MediaQuery.of(context).size.width;
    final compact = WebLayoutMetrics.compact(width);
    final mediumDesktop = WebLayoutMetrics.mediumDesktop(width);
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
          padding: EdgeInsets.all(mediumDesktop
              ? 14
              : compact
                  ? 16
                  : 18),
          enableBreathing: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: mediumDesktop
                        ? 36
                        : compact
                            ? 38
                            : 42,
                    height: mediumDesktop
                        ? 36
                        : compact
                            ? 38
                            : 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.accent.withValues(alpha: 0.14),
                    ),
                    child: Icon(
                      card.section.icon,
                      color: AppColors.accent,
                      size: mediumDesktop ? 18 : 20,
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
              SizedBox(
                  height: mediumDesktop
                      ? 12
                      : compact
                          ? 14
                          : 18),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: mediumDesktop
                          ? 15
                          : compact
                              ? 16
                              : 17,
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
                          fontSize: mediumDesktop ? 12.5 : null,
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
    final width = MediaQuery.of(context).size.width;
    final compact = WebLayoutMetrics.compact(width);
    final mediumDesktop = WebLayoutMetrics.mediumDesktop(width);
    return Row(
      children: [
        Icon(icon, size: mediumDesktop ? 16 : 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: mediumDesktop
                    ? 17
                    : compact
                        ? 18
                        : 20,
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
    final mediumDesktop =
        WebLayoutMetrics.mediumDesktop(MediaQuery.of(context).size.width);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mediumDesktop
            ? 10
            : compact
                ? 10
                : 12,
        vertical: mediumDesktop
            ? 5
            : compact
                ? 6
                : 8,
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
          fontSize: mediumDesktop
              ? 10.5
              : compact
                  ? 11
                  : 12,
        ),
      ),
    );
  }
}

class _NoticeDetailDialog extends StatelessWidget {
  const _NoticeDetailDialog({
    required this.notice,
    required this.isChinese,
  });

  final WebNoticeViewData notice;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-home-notice-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: GradientCard(
          borderRadius: 30,
          padding: const EdgeInsets.all(24),
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
                        Text(
                          notice.title.isEmpty
                              ? (isChinese ? '系统公告' : 'System Announcement')
                              : notice.title,
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(fontSize: 30, height: 1.15),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          Formatters.formatEpoch(notice.createdAt),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: isChinese ? '关闭' : 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: notice.bodyHtml.isEmpty
                      ? Text(
                          notice.body.isEmpty
                              ? (isChinese
                                  ? '这条公告暂时没有更多内容。'
                                  : 'No more details are available for this announcement.')
                              : notice.body,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textPrimary,
                                    height: 1.65,
                                  ),
                        )
                      : RichContentView(html: notice.bodyHtml),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeDot extends StatelessWidget {
  const _NoticeDot({
    super.key,
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: active ? 24 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent
                : AppColors.textSecondary.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.28),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

class _InteractiveSubscriptionPlaceholder extends StatelessWidget {
  const _InteractiveSubscriptionPlaceholder({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mediumDesktop = WebLayoutMetrics.mediumDesktop(width);
    return AnimatedCard(
      key: const Key('web-subscription-empty-card'),
      onTap: onTap,
      padding: EdgeInsets.all(mediumDesktop ? 14 : 20),
      enableBreathing: false,
      child: Row(
        children: [
          Container(
            width: mediumDesktop ? 46 : 52,
            height: mediumDesktop ? 46 : 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(mediumDesktop ? 16 : 18),
              color: AppColors.accent.withValues(alpha: 0.14),
            ),
            child: const Icon(
              Icons.add_shopping_cart_rounded,
              color: AppColors.accent,
            ),
          ),
          SizedBox(width: mediumDesktop ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: mediumDesktop ? 16 : null,
                      ),
                ),
                SizedBox(height: mediumDesktop ? 4 : 6),
                Text(
                  subtitle,
                  maxLines: mediumDesktop ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: mediumDesktop ? 13 : null,
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
    final mediumDesktop =
        WebLayoutMetrics.mediumDesktop(MediaQuery.of(context).size.width);
    return Container(
      padding: EdgeInsets.all(mediumDesktop ? 12 : 14),
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
          SizedBox(height: mediumDesktop ? 6 : 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: mediumDesktop ? 15 : 16,
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
    final mediumDesktop =
        WebLayoutMetrics.mediumDesktop(MediaQuery.of(context).size.width);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: mediumDesktop ? 12 : 14,
            vertical: mediumDesktop ? 8 : 10,
          ),
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
                  fontSize: mediumDesktop ? 13 : null,
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
    final mediumDesktop =
        WebLayoutMetrics.mediumDesktop(MediaQuery.of(context).size.width);
    return AnimatedCard(
      width: double.infinity,
      padding: EdgeInsets.all(
        mediumDesktop
            ? 8
            : dense
                ? 10
                : 14,
      ),
      onTap: onTap,
      enableBreathing: false,
      borderRadius: 18,
      hoverScale: 1.01,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: mediumDesktop ? 38 : 42,
            height: mediumDesktop ? 38 : 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.accent.withValues(alpha: 0.14),
            ),
            child: Icon(icon,
                size: mediumDesktop ? 18 : 20, color: AppColors.accent),
          ),
          SizedBox(width: mediumDesktop ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: mediumDesktop ? 15 : 16,
                      ),
                ),
                SizedBox(
                    height: mediumDesktop
                        ? 3
                        : dense
                            ? 4
                            : 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                        color: AppColors.textSecondary,
                        fontSize: mediumDesktop ? 12.5 : null,
                      ),
                ),
              ],
            ),
          ),
          SizedBox(width: mediumDesktop ? 10 : 12),
          _CountBadge(label: statusLabel, compact: true),
        ],
      ),
    );
  }
}

class _QuickUsageHintCard extends StatelessWidget {
  const _QuickUsageHintCard({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportOptionTile extends StatelessWidget {
  const _ImportOptionTile({
    required this.option,
    required this.isChinese,
    required this.onTap,
  });

  final WebClientImportOptionData option;
  final bool isChinese;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _clientImportIcon(option.clientKey);
    final hint = option.protocolHint?.trim();
    final actionLabel = option.isDeepLink
        ? (isChinese ? '立即导入' : 'Import Now')
        : (isChinese ? '复制链接' : 'Copy Link');

    return AnimatedCard(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
                  option.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  hint == null || hint.isEmpty
                      ? (isChinese
                          ? '为当前平台准备的客户端导入入口。'
                          : 'Client import option for this platform.')
                      : (isChinese ? '适用协议：$hint' : 'Protocol: $hint'),
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
          _CountBadge(label: actionLabel, compact: true),
        ],
      ),
    );
  }
}

IconData _clientImportIcon(String clientKey) {
  switch (clientKey) {
    case 'clash':
      return Icons.flash_on_rounded;
    case 'hiddify':
      return Icons.public_rounded;
    case 'sing_box':
      return Icons.graphic_eq_rounded;
    case 'shadowrocket':
      return Icons.rocket_launch_rounded;
    case 'quantumult_x':
      return Icons.all_inclusive_rounded;
    case 'surge':
      return Icons.bolt_rounded;
    default:
      return Icons.open_in_browser_rounded;
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

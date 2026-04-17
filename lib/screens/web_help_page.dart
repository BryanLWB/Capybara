import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/help_article.dart';
import '../services/api_config.dart';
import '../services/app_api.dart';
import '../services/crisp_service.dart';
import '../services/web_app_facade.dart';
import '../services/web_crisp_actions.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/web_error_text.dart';
import '../widgets/action_button.dart';
import '../widgets/animated_card.dart';
import '../widgets/capybara_loader.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_page_frame.dart';
import '../widgets/web_page_hero.dart';

typedef WebHelpCategoriesLoader = Future<List<HelpCategory>> Function(
  String language,
);
typedef WebHelpArticleLoader = Future<HelpArticleDetail> Function(
  int articleId,
  String language,
);
typedef WebHelpChatOpener = Future<bool> Function();
typedef WebHelpFallbackChatOpener = Future<void> Function();

class WebHelpPage extends StatefulWidget {
  const WebHelpPage({
    super.key,
    this.categoriesLoader,
    this.articleLoader,
    this.chatOpener,
    this.fallbackChatOpener,
    this.onUnauthorized,
  });

  final WebHelpCategoriesLoader? categoriesLoader;
  final WebHelpArticleLoader? articleLoader;
  final WebHelpChatOpener? chatOpener;
  final WebHelpFallbackChatOpener? fallbackChatOpener;
  final VoidCallback? onUnauthorized;

  @override
  State<WebHelpPage> createState() => _WebHelpPageState();
}

class _WebHelpPageState extends State<WebHelpPage> {
  final WebAppFacade _facade = WebAppFacade();
  String? _language;
  Future<List<HelpCategory>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = _languageTag(context);
    if (_future == null || _language != language) {
      _language = language;
      _future = _loadCategories(language);
    }
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  String _languageTag(BuildContext context) => 'zh-CN';

  Future<List<HelpCategory>> _loadCategories(String language) async {
    if (widget.categoriesLoader != null) {
      return widget.categoriesLoader!(language);
    }
    return _facade.loadHelpCategories(language);
  }

  Future<HelpArticleDetail> _loadArticleDetail(
    int articleId,
    String language,
  ) async {
    if (widget.articleLoader != null) {
      return widget.articleLoader!(articleId, language);
    }
    return _facade.loadHelpArticleDetail(articleId, language);
  }

  Future<void> _openChat(BuildContext context, bool isChinese) async {
    final openChat = widget.chatOpener ?? WebCrispActions.openChat;
    final openFallbackChat = widget.fallbackChatOpener ?? CrispService.openChat;
    final opened = await openChat();
    if (opened) return;

    await openFallbackChat();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isChinese
              ? '已为你尝试打开在线客服；如果浮窗没有展开，会自动切换到客服页面。'
              : 'We tried to open live support. If the chat widget does not expand, a support page will open instead.',
        ),
      ),
    );
  }

  void _handleUnauthorized() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ApiConfig().clearAuth());
      if (mounted) {
        widget.onUnauthorized?.call();
      }
    });
  }

  Future<void> _showArticleDialog(
    BuildContext context,
    HelpArticleSummary article,
  ) async {
    final language = _language ?? _languageTag(context);
    final isChinese = _isChinese(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _HelpArticleDialog(
        article: article,
        isChinese: isChinese,
        language: language,
        articleLoader: _loadArticleDetail,
        onUnauthorized: _handleUnauthorized,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final future = _future;
    if (future == null) {
      return const Center(child: CapybaraLoader(showTips: true));
    }

    return FutureBuilder<List<HelpCategory>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is AppApiException &&
              (error.statusCode == 401 || error.statusCode == 403)) {
            _handleUnauthorized();
            return const Center(child: CapybaraLoader());
          }
          return _HelpErrorState(
            isChinese: isChinese,
            message: webErrorText(
              error ?? StateError('help.load.failed'),
              isChinese: isChinese,
              context: WebErrorContext.pageLoad,
            ),
            onReload: () {
              setState(() {
                _future = _loadCategories(_language ?? _languageTag(context));
              });
            },
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CapybaraLoader(showTips: true));
        }

        final categories = snapshot.data!;

        return WebPageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WebPageHero(
                title:
                    isChinese ? '帮助中心与知识库' : 'Support Center & Knowledge Base',
                subtitle: isChinese
                    ? '在这里查看使用说明、常见问题和客户端下载信息。需要人工协助时，可直接联系在线客服。'
                    : 'Find guides, FAQs, and client download information here. Contact support anytime if you need direct help.',
                child: ActionButton(
                  key: const Key('web-help-chat-button'),
                  icon: Icons.chat_bubble_outline_rounded,
                  label: isChinese ? '在线聊天' : 'Chat with Support',
                  onPressed: () => _openChat(context, isChinese),
                ),
              ),
              const SizedBox(height: 18),
              if (categories.isEmpty)
                _HelpEmptyState(isChinese: isChinese)
              else
                ...categories.map(
                  (category) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _HelpCategoryCard(
                      category: category,
                      isChinese: isChinese,
                      onTapArticle: (article) =>
                          _showArticleDialog(context, article),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HelpCategoryCard extends StatelessWidget {
  const _HelpCategoryCard({
    required this.category,
    required this.isChinese,
    required this.onTapArticle,
  });

  final HelpCategory category;
  final bool isChinese;
  final ValueChanged<HelpArticleSummary> onTapArticle;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      key: Key('web-help-category-${category.name}'),
      borderRadius: 28,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.name,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: AppColors.surfaceAlt,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  isChinese
                      ? '${category.articles.length} 篇文章'
                      : '${category.articles.length} articles',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...category.articles.map(
            (article) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnimatedCard(
                key: Key('web-help-article-${article.id}'),
                onTap: () => onTapArticle(article),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                enableBreathing: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.title.isEmpty
                                ? (isChinese ? '未命名文章' : 'Untitled Article')
                                : article.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontSize: 20),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isChinese
                                ? '更新时间 ${Formatters.formatEpoch(article.updatedAt)}'
                                : 'Updated ${Formatters.formatEpoch(article.updatedAt)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpEmptyState extends StatelessWidget {
  const _HelpEmptyState({required this.isChinese});

  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      key: const Key('web-help-empty-state'),
      borderRadius: 28,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.menu_book_rounded,
            size: 36,
            color: AppColors.accent,
          ),
          const SizedBox(height: 16),
          Text(
            isChinese ? '暂时还没有帮助文章' : 'No help articles yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 26,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            isChinese
                ? '当前还没有可阅读的帮助文章。你可以先使用上方在线客服，我们会持续补充更多内容。'
                : 'There are no help articles available yet. You can contact support from the button above while we keep adding more content.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.55,
                ),
          ),
        ],
      ),
    );
  }
}

class _HelpErrorState extends StatelessWidget {
  const _HelpErrorState({
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GradientCard(
            borderRadius: 28,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.help_center_rounded,
                  color: AppColors.accentWarm,
                  size: 42,
                ),
                const SizedBox(height: 16),
                Text(
                  isChinese ? '帮助页加载失败' : 'Failed to load help content',
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
                  onPressed: onReload,
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
}

class _HelpArticleDialog extends StatefulWidget {
  const _HelpArticleDialog({
    required this.article,
    required this.isChinese,
    required this.language,
    required this.articleLoader,
    required this.onUnauthorized,
  });

  final HelpArticleSummary article;
  final bool isChinese;
  final String language;
  final WebHelpArticleLoader articleLoader;
  final VoidCallback onUnauthorized;

  @override
  State<_HelpArticleDialog> createState() => _HelpArticleDialogState();
}

class _HelpArticleDialogState extends State<_HelpArticleDialog> {
  late Future<HelpArticleDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.articleLoader(widget.article.id, widget.language);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-help-article-dialog'),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 760),
        child: GradientCard(
          borderRadius: 30,
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<HelpArticleDetail>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                if (error is AppApiException &&
                    (error.statusCode == 401 || error.statusCode == 403)) {
                  widget.onUnauthorized();
                  return const Center(child: CapybaraLoader());
                }
                return _buildDialogError(
                  context,
                  webErrorText(
                    error ?? StateError('help.article.failed'),
                    isChinese: widget.isChinese,
                    context: WebErrorContext.pageLoad,
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CapybaraLoader(showTips: true));
              }

              final article = snapshot.data!;
              return Column(
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
                              article.title.isEmpty
                                  ? (widget.isChinese
                                      ? '未命名文章'
                                      : 'Untitled Article')
                                  : article.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .displayMedium
                                  ?.copyWith(fontSize: 30, height: 1.15),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.isChinese
                                  ? '${article.category} · 更新于 ${Formatters.formatEpoch(article.updatedAt)}'
                                  : '${article.category} · Updated ${Formatters.formatEpoch(article.updatedAt)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
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
                        tooltip: widget.isChinese ? '关闭' : 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 18),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Html(
                        data: _sanitizeHtml(article.bodyHtml),
                        onLinkTap: (url, _, __) => _openLink(url),
                        style: {
                          'html': Style(
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                            color: AppColors.textPrimary,
                            backgroundColor: Colors.transparent,
                          ),
                          'body': Style(
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                            color: AppColors.textPrimary,
                            fontSize: FontSize(15),
                            lineHeight: const LineHeight(1.7),
                          ),
                          'p': Style(margin: Margins.only(bottom: 16)),
                          'a': Style(
                            color: AppColors.accent,
                            textDecoration: TextDecoration.none,
                          ),
                          'h1': Style(
                            margin: Margins.only(bottom: 16),
                            fontSize: FontSize(28),
                            fontWeight: FontWeight.w800,
                          ),
                          'h2': Style(
                            margin: Margins.only(bottom: 14),
                            fontSize: FontSize(24),
                            fontWeight: FontWeight.w800,
                          ),
                          'h3': Style(
                            margin: Margins.only(bottom: 12),
                            fontSize: FontSize(20),
                            fontWeight: FontWeight.w700,
                          ),
                          'ul': Style(margin: Margins.only(bottom: 16)),
                          'ol': Style(margin: Margins.only(bottom: 16)),
                          'li': Style(margin: Margins.only(bottom: 8)),
                          'strong': Style(fontWeight: FontWeight.w800),
                          'code': Style(
                            backgroundColor:
                                AppColors.surfaceAlt.withValues(alpha: 0.92),
                            padding: HtmlPaddings.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          ),
                          'pre': Style(
                            backgroundColor:
                                AppColors.surfaceAlt.withValues(alpha: 0.92),
                            padding: HtmlPaddings.all(14),
                          ),
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDialogError(BuildContext context, String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: widget.isChinese ? '关闭' : 'Close',
          ),
        ),
        const SizedBox(height: 12),
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.accentWarm,
          size: 40,
        ),
        const SizedBox(height: 16),
        Text(
          widget.isChinese ? '文章加载失败' : 'Failed to load article',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Future<void> _openLink(String? rawUrl) async {
    final url = rawUrl?.trim();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final scheme = uri.scheme.toLowerCase();
    if (scheme.isNotEmpty &&
        scheme != 'http' &&
        scheme != 'https' &&
        scheme != 'mailto') {
      return;
    }
    await launchUrl(uri);
  }

  String _sanitizeHtml(String value) {
    if (value.isEmpty) return '';
    return value
        .replaceAll(
          RegExp(r'<script[^>]*>.*?</script>',
              caseSensitive: false, dotAll: true),
          '',
        )
        .replaceAll(
          RegExp(
            "\\son\\w+=(\".*?\"|'.*?'|[^\\s>]+)",
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            "(href|src)=(\"|')\\s*javascript:[^\"']*(\"|')",
            caseSensitive: false,
          ),
          '',
        );
  }
}

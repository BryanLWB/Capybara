import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

class RichContentView extends StatelessWidget {
  const RichContentView({
    super.key,
    required this.html,
  });

  final String html;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return Html(
      data: html,
      onLinkTap: (url, _, __) => _openLink(url),
      style: <String, Style>{
        'html': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          color: AppColors.textPrimary,
          fontSize: FontSize(bodyStyle?.fontSize ?? 15),
        ),
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          color: AppColors.textPrimary,
          lineHeight: LineHeight(1.6),
          fontSize: FontSize(bodyStyle?.fontSize ?? 15),
        ),
        'p': Style(
          margin: Margins.only(bottom: 14),
          color: AppColors.textPrimary,
        ),
        'ul': Style(
          margin: Margins.only(bottom: 16),
          padding: HtmlPaddings.only(left: 10),
        ),
        'ol': Style(
          margin: Margins.only(bottom: 16),
          padding: HtmlPaddings.only(left: 10),
        ),
        'li': Style(
          color: AppColors.textPrimary,
          margin: Margins.only(bottom: 8),
          lineHeight: LineHeight(1.55),
        ),
        'h1': Style(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: FontSize((titleStyle?.fontSize ?? 20) + 8),
          margin: Margins.only(bottom: 12),
        ),
        'h2': Style(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: FontSize((titleStyle?.fontSize ?? 20) + 4),
          margin: Margins.only(bottom: 12),
        ),
        'h3': Style(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: FontSize(titleStyle?.fontSize ?? 20),
          margin: Margins.only(bottom: 10),
        ),
        'strong': Style(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        'em': Style(
          color: AppColors.textPrimary,
          fontStyle: FontStyle.italic,
        ),
        'blockquote': Style(
          color: AppColors.textSecondary,
          margin: Margins.only(bottom: 16),
          padding: HtmlPaddings.only(left: 14, top: 10, right: 10, bottom: 10),
          border: Border(
            left: BorderSide(
              color: AppColors.accent.withValues(alpha: 0.45),
              width: 3,
            ),
          ),
          backgroundColor: AppColors.surfaceAlt.withValues(alpha: 0.72),
        ),
        'code': Style(
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceAlt,
          padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 4),
        ),
        'pre': Style(
          color: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceAlt,
          padding: HtmlPaddings.all(12),
          margin: Margins.only(bottom: 16),
        ),
        'a': Style(
          color: AppColors.accent,
          textDecoration: TextDecoration.none,
          fontWeight: FontWeight.w700,
        ),
        'img': Style(
          margin: Margins.only(top: 10, bottom: 14),
        ),
      },
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
}

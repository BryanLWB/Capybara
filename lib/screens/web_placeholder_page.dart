import 'package:flutter/material.dart';

import '../models/web_shell_section.dart';
import '../theme/app_colors.dart';
import '../widgets/action_button.dart';
import '../widgets/gradient_card.dart';

class WebPlaceholderPage extends StatelessWidget {
  const WebPlaceholderPage({
    super.key,
    required this.section,
    required this.onGoHome,
  });

  final WebShellSection section;
  final VoidCallback onGoHome;

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
        'zh',
      );

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final title = section.label(isChinese);
    final subtitle = switch (section) {
      WebShellSection.help => isChinese
          ? '帮助页面将在后续版本开放，当前可通过右下角客服浮窗联系支持。'
          : 'Help center is coming soon. Use the Crisp bubble in the lower right for support.',
      _ => isChinese ? '该页面正在开发中，稍后开放。' : 'This page is under construction and will be available soon.',
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GradientCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    section.icon,
                    color: AppColors.accent,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 24),
                ActionButton(
                  icon: Icons.arrow_back_rounded,
                  label: isChinese ? '返回主页' : 'Back to Home',
                  onPressed: onGoHome,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

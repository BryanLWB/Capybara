import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'gradient_card.dart';
import 'web_layout_metrics.dart';

class WebPageHero extends StatelessWidget {
  const WebPageHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.child,
  });

  final String title;
  final String subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final padding = WebLayoutMetrics.heroPadding(width);
    final titleSize = WebLayoutMetrics.heroTitleSize(width);
    final subtitleSize = WebLayoutMetrics.heroSubtitleSize(width);

    return SizedBox(
      key: const Key('web-page-hero'),
      width: double.infinity,
      child: GradientCard(
        borderRadius: WebLayoutMetrics.heroRadius(width),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: titleSize,
                    height: 1.05,
                  ),
            ),
            SizedBox(
                height: width >= 980
                    ? 10
                    : width >= 640
                        ? 12
                        : 10),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: subtitleSize,
                    height: width >= 980 ? 1.45 : 1.6,
                    color: AppColors.textSecondary,
                  ),
            ),
            if (child != null) ...[
              SizedBox(
                  height: width >= 980
                      ? 16
                      : width >= 640
                          ? 20
                          : 18),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}

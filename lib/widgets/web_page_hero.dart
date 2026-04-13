import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'gradient_card.dart';

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
    return SizedBox(
      key: const Key('web-page-hero'),
      width: double.infinity,
      child: GradientCard(
        borderRadius: 32,
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 42,
                    height: 1.05,
                  ),
            ),
            const SizedBox(height: 14),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 17,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
            ),
            if (child != null) ...[
              const SizedBox(height: 22),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}

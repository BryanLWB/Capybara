import 'package:flutter/material.dart';

import 'web_layout_metrics.dart';

class WebPageFrame extends StatelessWidget {
  const WebPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 1520,
    this.padding = const EdgeInsets.fromLTRB(24, 14, 24, 88),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontal = WebLayoutMetrics.horizontalPadding(width);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        width >= 980 ? 12 : padding.top,
        horizontal,
        width >= 640 ? padding.bottom : 72,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: WebLayoutMetrics.maxContentWidth(width, base: maxWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}

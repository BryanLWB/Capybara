import 'package:flutter/material.dart';

class WebPageFrame extends StatelessWidget {
  const WebPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 1440,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 88),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontal = width >= 1180 ? padding.left : 16.0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          horizontal, padding.top, horizontal, padding.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

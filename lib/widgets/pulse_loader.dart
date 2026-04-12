import 'package:flutter/material.dart';
import 'capybara_loader.dart';

/// 统一使用 CapybaraLoader，保持动画风格一致
class PulseLoader extends StatelessWidget {
  final double size;
  const PulseLoader({super.key, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return CapybaraLoader(size: size * 3);
  }
}

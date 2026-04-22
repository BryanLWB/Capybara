import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

import '../l10n/generated/app_localizations.dart';

class CapybaraLoader extends StatefulWidget {
  final double size;
  final Color? color;
  final String? label;
  final bool showTips;

  const CapybaraLoader({
    super.key,
    this.size = 40,
    this.color,
    this.label,
    this.showTips = false,
  });

  @override
  State<CapybaraLoader> createState() => _CapybaraLoaderState();
}

class _CapybaraLoaderState extends State<CapybaraLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _tipTimer;
  int _tipIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    if (widget.showTips) {
      _tipTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted) return;
        setState(() {
          _tipIndex++;
        });
      });
    }
  }

  List<String> _getLocalizedTips(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return [];
    return [
      l10n.loadingTipConnecting,
      l10n.loadingTipOptimizing,
      l10n.loadingTipEncrypting,
      l10n.loadingTipVerifying,
      l10n.loadingTipSyncing,
      l10n.loadingTipHandshake,
      l10n.loadingTipAnalyzing,
    ];
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String currentText = widget.label ?? '';
    if (widget.label == null && widget.showTips) {
      final tips = _getLocalizedTips(context);
      if (tips.isNotEmpty) {
        currentText = tips[_tipIndex % tips.length];
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _CapybaraPainter(
                  animation: _controller,
                  color: widget.color ?? AppColors.accent,
                ),
              );
            },
          ),
        ),
        if (currentText.isNotEmpty) ...[
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Text(
              currentText,
              key: ValueKey(currentText),
              style: TextStyle(
                fontSize: 12,
                color: (widget.color ?? AppColors.accent).withOpacity(0.8),
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _CapybaraPainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;

  _CapybaraPainter({required this.animation, required this.color})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.12;

    // Common paint
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // 1. Central Pulsing Core (Solid)
    final pulseScale = 0.8 + 0.2 * math.sin(animation.value * 4 * math.pi);
    paint.style = PaintingStyle.fill;
    paint.color =
        color.withValues(alpha: 0.3 + 0.2 * pulseScale); // Use withValues
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset.zero, radius * 0.25 * pulseScale, paint);
    paint.maskFilter = null; // Reset mask

    // 2. Inner Rotating Ring (Counter-clockwise)
    canvas.save();
    canvas.rotate(-animation.value * 2 * math.pi);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = strokeWidth * 0.6;
    paint.color = color.withValues(alpha: 0.4); // Use withValues

    // Draw segmented inner ring
    for (int i = 0; i < 4; i++) {
      final double startAngle = i * (math.pi / 2);
      canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.55),
          startAngle,
          math.pi / 4, // 45 degrees arc
          false,
          paint);
    }
    canvas.restore();

    // 3. Outer Rotating Arcs (Clockwise) - Original improved
    canvas.rotate(animation.value * 2 * math.pi);
    paint.strokeWidth = strokeWidth;

    for (int i = 0; i < 3; i++) {
      final double phase = i * (2 * math.pi / 3);
      final double progress = (animation.value + i * 0.33) % 1.0;

      // Dynamic length wave
      final double length =
          (0.25 + 0.2 * math.sin(progress * 2 * math.pi)).abs() * 2 * math.pi;

      // Gradient-like opacity effect using arc stroke
      paint.color = color.withValues(
          alpha:
              0.8 + 0.2 * math.sin(progress * 2 * math.pi)); // Use withValues

      // Outer glow
      paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 4);

      final rect = Rect.fromCircle(
          center: Offset.zero, radius: radius - strokeWidth / 2);
      canvas.drawArc(rect, phase, length, false, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CapybaraPainter oldDelegate) => true;
}

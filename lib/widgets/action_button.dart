import 'package:flutter/material.dart';

import 'capybara_loader.dart';

/// 操作按钮组件
class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: onPressed != null
                  ? [
                      Colors.white.withValues(alpha: 0.15),
                      Colors.white.withValues(alpha: 0.08),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.02),
                    ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: onPressed != null
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CapybaraLoader(size: 16, color: Colors.white),
                )
              else
                Icon(
                  icon,
                  size: 18,
                  color: onPressed != null
                      ? Colors.white.withValues(alpha: 0.87)
                      : Colors.white38,
                ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: onPressed != null
                      ? Colors.white.withValues(alpha: 0.87)
                      : Colors.white38,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'capybara_loader.dart';

enum ConnectionButtonStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// 连接按钮组件
class ConnectionButton extends StatelessWidget {
  final ConnectionButtonStatus status;
  final VoidCallback? onTap;
  final bool isLoading;
  final Animation<double> pulseAnimation;

  const ConnectionButton({
    super.key,
    required this.status,
    required this.onTap,
    required this.pulseAnimation,
    this.isLoading = false,
  });

  Color get _buttonColor {
    switch (status) {
      case ConnectionButtonStatus.connected:
        return Colors.greenAccent;
      case ConnectionButtonStatus.connecting:
        return Colors.blueAccent;
      case ConnectionButtonStatus.error:
        return Colors.redAccent;
      case ConnectionButtonStatus.disconnected:
        return Colors.grey.shade400;
    }
  }

  String _getStatusText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case ConnectionButtonStatus.connected:
        return l10n?.connected ?? 'Connected';
      case ConnectionButtonStatus.connecting:
        return l10n?.connecting ?? 'Connecting...';
      case ConnectionButtonStatus.error:
        return l10n?.error ?? 'Error';
      case ConnectionButtonStatus.disconnected:
        return l10n?.disconnected ?? 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              final scale = status == ConnectionButtonStatus.connected
                  ? 1.0 + (pulseAnimation.value * 0.05)
                  : 1.0;

              return Transform.scale(
                scale: scale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 外圈光晕
                    if (status == ConnectionButtonStatus.connected)
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _buttonColor.withValues(alpha: 0.3),
                              _buttonColor.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    
                    // 主按钮
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _buttonColor.withValues(alpha: 0.25),
                            _buttonColor.withValues(alpha: 0.1),
                          ],
                        ),
                        border: Border.all(
                          color: _buttonColor,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _buttonColor.withValues(alpha: 0.5),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                          BoxShadow(
                            color: _buttonColor.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: isLoading
                            ? CapybaraLoader(
                                size: 56 * 0.6,
                                color: Colors.white70,
                              )
                            : Icon(
                                status == ConnectionButtonStatus.connected
                                    ? Icons.power
                                    : Icons.power_settings_new,
                                size: 56,
                                color: _buttonColor,
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 20),
        
        // 状态文本
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: _buttonColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _buttonColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Builder(
            builder: (context) => Text(
              _getStatusText(context),
              style: TextStyle(
                fontSize: 15,
                letterSpacing: 1.5,
                color: _buttonColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}


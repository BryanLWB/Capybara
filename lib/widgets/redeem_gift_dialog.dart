import 'dart:ui';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../services/panel_api.dart';

class RedeemGiftDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const RedeemGiftDialog({super.key, required this.onSuccess});

  @override
  State<RedeemGiftDialog> createState() => _RedeemGiftDialogState();
}

class _RedeemGiftDialogState extends State<RedeemGiftDialog> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _breatheAnim;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _breatheAnim = Tween<double>(begin: 0.2, end: 0.6).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      final api = PanelApi();
      final success = await api.redeemGiftCard(code);

      if (success) {
        // Refresh user info
        await api.getUserInfo();
        
        if (mounted) {
          widget.onSuccess();
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)?.redeemSuccess ?? 'Redeem success'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        setState(() => _errorText = AppLocalizations.of(context)?.invalidCode ?? 'Invalid code');
      }
    } catch (e) {
       setState(() => _errorText = '${AppLocalizations.of(context)?.redeemFailed ?? "Redeem failed"}: ${e.toString().replaceAll("Exception:", "")}');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _breatheAnim,
          builder: (context, child) {
            return Container(
              width: 340,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222B).withValues(alpha: 0.95), // Darker surface
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                  // Breathing Glow
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: _breatheAnim.value * 0.3),
                    blurRadius: 20 + (_breatheAnim.value * 10),
                    spreadRadius: -5 + (_breatheAnim.value * 5),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon Header with gentle pulse
                    AnimatedBuilder(
                      animation: _breatheAnim,
                      builder: (context, _) => Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1 + (_breatheAnim.value * 0.05)),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: _breatheAnim.value * 0.2),
                              blurRadius: 16,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: const Icon(
                          Icons.card_giftcard_rounded,
                          color: AppColors.accent,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Title
                    Text(
                      AppLocalizations.of(context)?.redeemGiftCard ?? 'Redeem Gift Card',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)?.enterCode ?? 'Enter your code',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Input Field
                    TextField(
                      controller: _controller,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration(
                        hintText: 'ABCD-1234-EFGH-5678',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 15,
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: AppColors.accent.withValues(alpha: 0.5),
                          ),
                        ),
                        errorText: _errorText,
                        errorStyle: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              foregroundColor: Colors.white.withValues(alpha: 0.6),
                            ),
                            child: Text(AppLocalizations.of(context)?.cancel ?? 'Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              // SILVER GRADIENT Black & Silver Theme
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFE5E6EB), // Bright Silver / White-ish
                                  Color(0xFF9CA3AF), // Metallic Grey
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black, // Dark loader on silver
                                      ),
                                    )
                                  : Text(
                                      AppLocalizations.of(context)?.redeemNow ?? 'Redeem Now',
                                      style: TextStyle(
                                        color: Colors.black, // BLACK TEXT for Silver button
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

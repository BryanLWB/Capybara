import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/plan.dart';
import '../services/panel_api.dart';
import '../services/user_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/animated_card.dart';
import '../widgets/fade_in_widget.dart';
import '../widgets/staggered_list.dart';
import '../widgets/section_header.dart';
import '../widgets/capybara_loader.dart';
import '../widgets/redeem_gift_dialog.dart';
import 'orders_screen.dart';

class PlansScreen extends StatefulWidget {
  final void Function(Plan plan)? onChoose;
  const PlansScreen({super.key, this.onChoose});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _userDataService = UserDataService();
  late Future<List<Plan>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _plansFuture = _loadPlans();
  }

  Future<List<Plan>> _loadPlans({bool forceRefresh = false}) async {
    // 使用缓存服务，避免重复请求
    final data = await _userDataService.getPlans(forceRefresh: forceRefresh);
    return data.map((item) => Plan.fromJson(item)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Plan>>(
      future: _plansFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final err = snapshot.error;
          final message = err is PanelApiException
              ? err.message
              : (AppLocalizations.of(context)?.networkError ?? 'Network error');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: const TextStyle(color: AppColors.accentWarm),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {
                    _plansFuture = _loadPlans(forceRefresh: true);
                  }),
                  child: Text(AppLocalizations.of(context)?.retry ?? 'Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CapybaraLoader(showTips: true));
        }
        final plans = snapshot.data!;
        return StaggeredList(
          padding: const EdgeInsets.only(
            top: 64,
            left: 20,
            right: 20,
            bottom: 100,
          ),
          children: [
            FadeInWidget(
              delay: Duration.zero,
              child: SectionHeader(
                title:
                    AppLocalizations.of(context)?.choosePlan ?? 'Choose Plan',
                actionLabel: AppLocalizations.of(context)?.refresh ?? 'Refresh',
                onAction: () {
                  setState(() {
                    _plansFuture = _loadPlans(forceRefresh: true);
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildRedeemButton(),
            const SizedBox(height: 16),
            ...plans.asMap().entries.map((entry) {
              final plan = entry.value;
              final price = (plan.monthPrice ?? 0) > 0
                  ? plan.monthPrice!
                  : (plan.yearPrice ?? 0) > 0
                  ? plan.yearPrice!
                  : (plan.onetimePrice ?? 0);
              final l10n = AppLocalizations.of(context);
              final priceLabel = (plan.monthPrice ?? 0) > 0
                  ? '/${l10n?.monthPrice ?? "月"}'
                  : (plan.yearPrice ?? 0) > 0
                  ? '/${l10n?.yearPrice ?? "年"}'
                  : '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AnimatedCard(
                  onTap: widget.onChoose == null
                      ? null
                      : () async {
                          final result = await Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      OrdersScreen(selectedPlan: plan),
                              transitionsBuilder:
                                  (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                    child,
                                  ) {
                                    const begin = Offset(1.0, 0.0);
                                    const end = Offset.zero;
                                    const curve = Curves.easeOutCubic;
                                    var tween = Tween(
                                      begin: begin,
                                      end: end,
                                    ).chain(CurveTween(curve: curve));
                                    return SlideTransition(
                                      position: animation.drive(tween),
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    );
                                  },
                              transitionDuration: const Duration(
                                milliseconds: 400,
                              ),
                            ),
                          );
                          if (result == true && widget.onChoose != null) {
                            widget.onChoose!(plan);
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部：方案名 + 流量
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plan.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      fontSize: 17,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    plan.content ??
                                        (AppLocalizations.of(
                                              context,
                                            )?.globalNodes ??
                                            'Global premium nodes'),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.45),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // 流量标签
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.accent.withOpacity(0.15),
                                    AppColors.accent.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.accent.withOpacity(0.25),
                                ),
                              ),
                              child: Text(
                                Formatters.formatBytes(plan.transferEnable),
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // 底部：价格 + 按钮
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 价格
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '¥',
                                    style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text: Formatters.formatCurrency(price),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  if (priceLabel.isNotEmpty)
                                    TextSpan(
                                      text: priceLabel,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.4),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // 按钮
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    AppLocalizations.of(context)?.subscribe ??
                                        'Subscribe',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.black,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            // Bottom padding for nav bar
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }

  Widget _buildRedeemButton() {
    return GestureDetector(
      onTap: _showRedeemDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.card_giftcard, size: 20, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)?.redeemGiftCard ??
                  'Redeem Gift Card',
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRedeemDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: animation,
            child: RedeemGiftDialog(
              onSuccess: () {
                // PlansScreen state refresh
                setState(() {
                  _plansFuture = _loadPlans(forceRefresh: true);
                });
              },
            ),
          ),
        );
      },
    );
  }
}

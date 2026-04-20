import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/web_purchase_view_data.dart';
import '../models/web_shell_section.dart';
import '../models/web_user_subpage.dart';
import '../services/api_config.dart';
import '../services/web_app_facade.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_card.dart';
import '../widgets/animated_background.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_crisp_widget.dart';
import '../widgets/web_layout_metrics.dart';
import 'web_account_page.dart';
import 'web_help_page.dart';
import 'web_home_page.dart';
import 'web_invite_page.dart';
import 'web_purchase_page.dart';

typedef WebShellLogoutAction = Future<void> Function();

class WebShell extends StatefulWidget {
  const WebShell({
    super.key,
    required this.onLogout,
    this.initialSection = WebShellSection.home,
    this.purchasePageBuilder,
    this.logoutAction,
  });

  final VoidCallback onLogout;
  final WebShellSection initialSection;
  final WidgetBuilder? purchasePageBuilder;
  final WebShellLogoutAction? logoutAction;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  final WebAppFacade _facade = WebAppFacade();
  late WebShellSection _currentSection;
  WebUserSubpage _currentUserSubpage = WebUserSubpage.profile;
  String? _purchaseInitialOrderRef;
  WebPlanViewData? _purchaseInitialFallbackPlan;
  int _purchaseViewSeed = 0;

  @override
  void initState() {
    super.initState();
    _currentSection = widget.initialSection;
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  Future<void> _confirmAndLogout() async {
    final isChinese = _isChinese(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => _ShellConfirmDialog(
            title: isChinese ? '提示' : 'Notice',
            message: isChinese ? '确认退出？' : 'Are you sure you want to log out?',
            cancelLabel: isChinese ? '取消' : 'Cancel',
            confirmLabel: isChinese ? '确定' : 'Confirm',
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _logout();
  }

  Future<void> _logout() async {
    try {
      final logoutAction = widget.logoutAction ?? _facade.logoutCurrentSession;
      await logoutAction();
    } catch (_) {
      // Local logout must proceed even if the server session is already gone.
    } finally {
      await ApiConfig().clearAuth();
      if (mounted) {
        widget.onLogout();
      }
    }
  }

  void _openSection(
    WebShellSection section, {
    WebUserSubpage? userSubpage,
  }) {
    setState(() {
      _currentSection = section;
      if (section == WebShellSection.account) {
        _currentUserSubpage = userSubpage ?? WebUserSubpage.profile;
      }
      if (section == WebShellSection.purchase) {
        _purchaseInitialOrderRef = null;
        _purchaseInitialFallbackPlan = null;
        _purchaseViewSeed++;
      }
    });
  }

  Future<void> _openPurchaseOrder(
    String orderRef,
    WebPlanViewData? fallbackPlan,
  ) async {
    setState(() {
      _currentSection = WebShellSection.purchase;
      _purchaseInitialOrderRef = orderRef;
      _purchaseInitialFallbackPlan = fallbackPlan;
      _purchaseViewSeed++;
    });
  }

  void _openUserOrders() {
    setState(() {
      _currentSection = WebShellSection.account;
      _currentUserSubpage = WebUserSubpage.orders;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final width = MediaQuery.of(context).size.width;
    final isWide = WebLayoutMetrics.useWideNav(width);
    final gutter = WebLayoutMetrics.horizontalPadding(width);
    final navPadding = width >= 1280
        ? 20.0
        : width >= 980
            ? 16.0
            : 14.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: AnimatedMeshBackground(child: SizedBox.expand()),
          ),
          SafeArea(
            child: Column(
              children: [
                Container(
                  margin: EdgeInsets.fromLTRB(
                    gutter,
                    width >= 980 ? 12 : 16,
                    gutter,
                    width >= 980 ? 10 : 12,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: navPadding,
                    vertical: width >= 1280
                        ? 16
                        : width >= 980
                            ? 12
                            : 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 36,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: isWide
                      ? Row(
                          children: [
                            _buildBrand(context, isChinese),
                            const Spacer(),
                            _buildNavBar(
                              context,
                              isChinese,
                              sections: WebShellSection.values,
                            ),
                            const Spacer(),
                            _buildLogoutButton(isChinese),
                          ],
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            const baseSections = <WebShellSection>[
                              WebShellSection.home,
                              WebShellSection.purchase,
                              WebShellSection.help,
                              WebShellSection.invite,
                            ];
                            const expandedSections = <WebShellSection>[
                              WebShellSection.home,
                              WebShellSection.purchase,
                              WebShellSection.help,
                              WebShellSection.invite,
                              WebShellSection.account,
                            ];
                            final brandWidth = _estimateBrandWidth(
                              context,
                              isChinese,
                            );
                            final logoutWidth = _estimateLogoutWidth(
                              context,
                              isChinese,
                              compact: true,
                            );
                            final allNavWidth = _estimateNavRowWidth(
                              context,
                              isChinese,
                              sections: expandedSections,
                              compact: true,
                            );
                            const compactFitSafetyGap = 24.0;
                            final singleRowFits = brandWidth +
                                    16 +
                                    allNavWidth +
                                    16 +
                                    logoutWidth <=
                                constraints.maxWidth;

                            if (singleRowFits) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildBrand(context, isChinese),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: _buildNavBar(
                                        context,
                                        isChinese,
                                        sections: expandedSections,
                                        compact: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  _buildLogoutButton(
                                    isChinese,
                                    compact: true,
                                  ),
                                ],
                              );
                            }
                            final userOnSecondRow =
                                allNavWidth + compactFitSafetyGap <=
                                    constraints.maxWidth;
                            final secondRowSections = userOnSecondRow
                                ? expandedSections
                                : baseSections;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                userOnSecondRow
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _buildBrand(
                                              context,
                                              isChinese,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          _buildLogoutButton(
                                            isChinese,
                                            compact: true,
                                          ),
                                        ],
                                      )
                                    : _buildCompactHeaderWithFloatingUser(
                                        context,
                                        isChinese,
                                      ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: constraints.maxWidth,
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.topCenter,
                                      child: _buildNavBar(
                                        context,
                                        isChinese,
                                        sections: secondRowSections,
                                        compact: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_currentSection),
                      child: _buildPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: WebCrispWidget())),
        ],
      ),
    );
  }

  Widget _buildBrand(BuildContext context, bool isChinese) {
    final width = MediaQuery.of(context).size.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Capybara',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: width >= 1280
                    ? 28
                    : width >= 980
                        ? 24
                        : 24,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          isChinese ? '会员中心' : 'Member Center',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: width >= 980 ? 12 : 13,
              ),
        ),
      ],
    );
  }

  Widget _buildNavBar(
    BuildContext context,
    bool isChinese, {
    required List<WebShellSection> sections,
    bool compact = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          _buildNavItem(
            context,
            sections[i],
            isChinese,
            compact: compact,
          ),
          if (i != sections.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildCompactHeaderWithFloatingUser(
    BuildContext context,
    bool isChinese,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBrand(context, isChinese),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: _buildNavItem(
                context,
                WebShellSection.account,
                isChinese,
                compact: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _buildLogoutButton(isChinese, compact: true),
      ],
    );
  }

  double _estimateBrandWidth(BuildContext context, bool isChinese) {
    final width = MediaQuery.of(context).size.width;
    final titleStyle = Theme.of(context).textTheme.displayMedium?.copyWith(
          fontSize: width >= 1280
              ? 28
              : width >= 980
                  ? 24
                  : 24,
          letterSpacing: 0.4,
        );
    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: width >= 980 ? 12 : 13,
        );
    final titleWidth = _measureTextWidth(context, 'Capybara', titleStyle);
    final subtitleWidth = _measureTextWidth(
      context,
      isChinese ? '会员中心' : 'Member Center',
      subtitleStyle,
    );
    return math.max(titleWidth, subtitleWidth);
  }

  double _estimateNavRowWidth(
    BuildContext context,
    bool isChinese, {
    required List<WebShellSection> sections,
    required bool compact,
  }) {
    var total = 0.0;
    for (var i = 0; i < sections.length; i++) {
      total += _estimateNavItemWidth(
        context,
        sections[i],
        isChinese,
        compact: compact,
      );
      if (i != sections.length - 1) {
        total += 6;
      }
    }
    return total;
  }

  double _estimateNavItemWidth(
    BuildContext context,
    WebShellSection section,
    bool isChinese, {
    required bool compact,
  }) {
    final width = MediaQuery.of(context).size.width;
    final horizontal = compact ? 14.0 : (width >= 980 ? 14.0 : 16.0);
    final iconSize = compact ? 18.0 : (width >= 980 ? 17.0 : 18.0);
    final textStyle = TextStyle(
      fontWeight:
          _currentSection == section ? FontWeight.w700 : FontWeight.w500,
      fontSize: compact ? 14 : (width >= 980 ? 14 : null),
    );
    return horizontal * 2 +
        iconSize +
        8 +
        _measureTextWidth(context, section.label(isChinese), textStyle);
  }

  double _estimateLogoutWidth(
    BuildContext context,
    bool isChinese, {
    required bool compact,
  }) {
    final label = isChinese ? '退出登录' : 'Logout';
    final textStyle = TextStyle(fontSize: compact ? 14 : 15);
    final horizontal = compact ? 12.0 : 16.0;
    return horizontal * 2 +
        18 +
        8 +
        _measureTextWidth(context, label, textStyle);
  }

  double _measureTextWidth(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  Widget _buildNavItem(
    BuildContext context,
    WebShellSection section,
    bool isChinese, {
    bool compact = false,
  }) {
    final width = MediaQuery.of(context).size.width;
    final isSelected = _currentSection == section;
    final horizontal = compact ? 14.0 : (width >= 980 ? 14.0 : 16.0);
    final vertical = compact ? 10.0 : (width >= 980 ? 10.0 : 12.0);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openSection(section),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              section.icon,
              size: compact ? 18 : (width >= 980 ? 17 : 18),
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              section.label(isChinese),
              style: TextStyle(
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: compact ? 14 : (width >= 980 ? 14 : null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(bool isChinese, {bool compact = false}) {
    return TextButton.icon(
      onPressed: _confirmAndLogout,
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: Text(isChinese ? '退出登录' : 'Logout'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 12,
        ),
        textStyle: TextStyle(fontSize: compact ? 14 : 15),
      ),
    );
  }

  Widget _buildPage() {
    switch (_currentSection) {
      case WebShellSection.home:
        return WebHomePage(
          onNavigate: (section) {
            _openSection(section);
          },
          onUnauthorized: widget.onLogout,
        );
      case WebShellSection.purchase:
        if (widget.purchasePageBuilder != null &&
            _purchaseInitialOrderRef == null) {
          return widget.purchasePageBuilder!.call(context);
        }
        return WebPurchasePage(
          key: ValueKey(
            'web-purchase-$_purchaseViewSeed-${_purchaseInitialOrderRef ?? 'catalog'}',
          ),
          initialOrderRef: _purchaseInitialOrderRef,
          initialFallbackPlan: _purchaseInitialFallbackPlan,
          onOpenUserOrders: _openUserOrders,
          onPaymentCompletedNavigateHome: () =>
              _openSection(WebShellSection.home),
        );
      case WebShellSection.help:
        return WebHelpPage(onUnauthorized: widget.onLogout);
      case WebShellSection.invite:
        return WebInvitePage(onUnauthorized: widget.onLogout);
      case WebShellSection.account:
        return WebAccountPage(
          initialSubpage: _currentUserSubpage,
          onOpenOrderCheckout: _openPurchaseOrder,
          onUnauthorized: widget.onLogout,
        );
    }
  }
}

class _ShellConfirmDialog extends StatelessWidget {
  const _ShellConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-shell-confirm-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GradientCard(
          borderRadius: 34,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 32,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _ShellDialogButton(
                      label: cancelLabel,
                      emphasized: false,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ShellDialogButton(
                      label: confirmLabel,
                      emphasized: true,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellDialogButton extends StatelessWidget {
  const _ShellDialogButton({
    required this.label,
    required this.emphasized,
    required this.onTap,
  });

  final String label;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: AnimatedCard(
        onTap: onTap,
        hoverScale: 1.015,
        padding: EdgeInsets.zero,
        borderRadius: 18,
        enableBreathing: false,
        gradientColors: [
          emphasized
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.surfaceAlt.withValues(alpha: 0.78),
          emphasized
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.surface.withValues(alpha: 0.9),
        ],
        baseBorderColor: emphasized
            ? AppColors.accent.withValues(alpha: 0.46)
            : AppColors.border,
        hoverBorderColor: emphasized
            ? AppColors.accent.withValues(alpha: 0.64)
            : AppColors.textSecondary,
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: emphasized
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
          ),
        ),
      ),
    );
  }
}

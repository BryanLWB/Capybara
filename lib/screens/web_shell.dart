import 'package:flutter/material.dart';

import '../models/web_shell_section.dart';
import '../services/api_config.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_background.dart';
import '../widgets/web_crisp_widget.dart';
import 'web_account_page.dart';
import 'web_help_page.dart';
import 'web_home_page.dart';
import 'web_invite_page.dart';
import 'web_purchase_page.dart';

class WebShell extends StatefulWidget {
  const WebShell({
    super.key,
    required this.onLogout,
    this.initialSection = WebShellSection.home,
  });

  final VoidCallback onLogout;
  final WebShellSection initialSection;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late WebShellSection _currentSection;

  @override
  void initState() {
    super.initState();
    _currentSection = widget.initialSection;
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  Future<void> _logout() async {
    await ApiConfig().clearAuth();
    if (mounted) {
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1040;

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
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: isWide
                      ? Row(
                          children: [
                            _buildBrand(context, isChinese),
                            const Spacer(),
                            _buildNavBar(context, isChinese),
                            const Spacer(),
                            _buildLogoutButton(isChinese),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildBrand(context, isChinese),
                                const Spacer(),
                                _buildLogoutButton(isChinese),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _buildNavBar(context, isChinese),
                            ),
                          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Capybara',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 28,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          isChinese ? '网页控制台' : 'Web Console',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildNavBar(BuildContext context, bool isChinese) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: WebShellSection.values.map((section) {
        final isSelected = _currentSection == section;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _currentSection = section),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    section.icon,
                    size: 18,
                    color:
                        isSelected ? AppColors.accent : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.label(isChinese),
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLogoutButton(bool isChinese) {
    return TextButton.icon(
      onPressed: _logout,
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: Text(isChinese ? '退出登录' : 'Logout'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildPage() {
    switch (_currentSection) {
      case WebShellSection.home:
        return WebHomePage(
          onNavigate: (section) {
            setState(() => _currentSection = section);
          },
          onUnauthorized: widget.onLogout,
        );
      case WebShellSection.purchase:
        return const WebPurchasePage();
      case WebShellSection.help:
        return const WebHelpPage();
      case WebShellSection.invite:
        return const WebInvitePage();
      case WebShellSection.account:
        return const WebAccountPage();
    }
  }
}

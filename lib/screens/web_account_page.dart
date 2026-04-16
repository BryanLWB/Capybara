import 'package:flutter/material.dart';

import '../models/web_account_view_data.dart';
import '../services/api_config.dart';
import '../services/app_api.dart';
import '../services/web_app_facade.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/animated_card.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_page_frame.dart';

typedef WebAccountProfileLoader = Future<Map<String, dynamic>> Function();
typedef WebAccountNotificationUpdater = Future<void> Function({
  required bool expiry,
  required bool traffic,
});
typedef WebAccountPasswordChanger = Future<void> Function({
  required String oldPassword,
  required String newPassword,
});
typedef WebAccountSubscriptionResetter = Future<void> Function();

class WebAccountPage extends StatefulWidget {
  const WebAccountPage({
    super.key,
    this.profileLoader,
    this.notificationUpdater,
    this.passwordChanger,
    this.subscriptionResetter,
    this.onUnauthorized,
  });

  final WebAccountProfileLoader? profileLoader;
  final WebAccountNotificationUpdater? notificationUpdater;
  final WebAccountPasswordChanger? passwordChanger;
  final WebAccountSubscriptionResetter? subscriptionResetter;
  final VoidCallback? onUnauthorized;

  @override
  State<WebAccountPage> createState() => _WebAccountPageState();
}

class _WebAccountPageState extends State<WebAccountPage> {
  final _facade = WebAppFacade();
  late Future<WebAccountProfileData> _profileFuture;
  bool? _expireReminder;
  bool? _trafficReminder;
  bool _isSavingNotifications = false;
  bool _isChangingPassword = false;
  bool _isResettingSubscription = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  Future<WebAccountProfileData> _loadProfile() async {
    final loader = widget.profileLoader;
    final profile = loader == null
        ? await _facade.loadAccountProfile()
        : WebAccountProfileData.fromResponse(await loader());
    _expireReminder ??= profile.expireReminder;
    _trafficReminder ??= profile.trafficReminder;
    return profile;
  }

  String _balanceLabel(
      AsyncSnapshot<WebAccountProfileData> snapshot, bool isChinese) {
    if (snapshot.connectionState != ConnectionState.done && !snapshot.hasData) {
      return '...';
    }
    if (snapshot.hasError) {
      final error = snapshot.error;
      if (error is AppApiException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        _handleUnauthorized();
      }
      return isChinese ? '加载失败' : 'Load failed';
    }
    return '¥${Formatters.formatCurrency(snapshot.data?.balanceAmount ?? 0)}';
  }

  Future<void> _updateNotifications({
    required bool expiry,
    required bool traffic,
    required bool isChinese,
  }) async {
    if (_isSavingNotifications) return;
    final previousExpiry = _expireReminder ?? false;
    final previousTraffic = _trafficReminder ?? false;
    setState(() {
      _expireReminder = expiry;
      _trafficReminder = traffic;
      _isSavingNotifications = true;
    });
    try {
      final updater = widget.notificationUpdater ??
          ({required bool expiry, required bool traffic}) async {
            await _facade.updateNotifications(
              expiry: expiry,
              traffic: traffic,
            );
          };
      await updater(expiry: expiry, traffic: traffic);
      if (!mounted) return;
      _showSnack(isChinese ? '邮件提醒设置已保存。' : 'Notification settings saved.');
    } catch (error) {
      if (mounted) {
        setState(() {
          _expireReminder = previousExpiry;
          _trafficReminder = previousTraffic;
        });
      }
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isSavingNotifications = false);
    }
  }

  Future<void> _changePassword(bool isChinese) async {
    final result = await showDialog<_PasswordChangeRequest>(
      context: context,
      builder: (context) => _ChangePasswordDialog(isChinese: isChinese),
    );
    if (result == null || !mounted || _isChangingPassword) return;
    setState(() => _isChangingPassword = true);
    try {
      final changer = widget.passwordChanger ??
          ({required String oldPassword, required String newPassword}) async {
            await _facade.changePassword(
              oldPassword: oldPassword,
              newPassword: newPassword,
            );
          };
      await changer(
        oldPassword: result.oldPassword,
        newPassword: result.newPassword,
      );
      if (!mounted) return;
      _showSnack(isChinese ? '密码已修改。' : 'Password changed.');
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _resetSubscription(bool isChinese) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AccountConfirmDialog(
        title: isChinese ? '重置订阅链接' : 'Reset Subscription Link',
        message: isChinese
            ? '确认重置订阅链接？旧链接会立即失效，需要重新复制或扫码导入。'
            : 'Reset the subscription link? The old link will stop working.',
        cancelLabel: isChinese ? '取消' : 'Cancel',
        confirmLabel: isChinese ? '确认重置' : 'Reset',
      ),
    );
    if (confirmed != true || !mounted || _isResettingSubscription) return;
    setState(() => _isResettingSubscription = true);
    try {
      final resetter = widget.subscriptionResetter ??
          () async {
            await _facade.resetSubscriptionSecurity();
          };
      await resetter();
      if (!mounted) return;
      _showSnack(isChinese
          ? '订阅链接已重置，请回到主页重新复制或生成二维码。'
          : 'Subscription link reset. Copy or generate a new QR from Home.');
    } catch (error) {
      _handleActionError(error, isChinese);
    } finally {
      if (mounted) setState(() => _isResettingSubscription = false);
    }
  }

  void _handleActionError(Object error, bool isChinese) {
    if (error is AppApiException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      _handleUnauthorized();
      return;
    }
    if (!mounted) return;
    _showSnack(error.toString());
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleUnauthorized() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ApiConfig().clearAuth();
      if (mounted) widget.onUnauthorized?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final wide = MediaQuery.of(context).size.width >= 1080;

    return FutureBuilder<WebAccountProfileData>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final balance = _balanceLabel(snapshot, isChinese);
        final profile = snapshot.data;
        final expireReminder =
            _expireReminder ?? profile?.expireReminder ?? false;
        final trafficReminder =
            _trafficReminder ?? profile?.trafficReminder ?? false;
        return WebPageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _BalanceCard(
                          title: isChinese ? '账户余额（仅消费）' : 'Account Balance',
                          value: balance,
                          fillHeight: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _PreferenceCard(
                          isChinese: isChinese,
                          expireReminder: expireReminder,
                          trafficReminder: trafficReminder,
                          isSaving: _isSavingNotifications,
                          onExpireChanged: (value) => _updateNotifications(
                            expiry: value,
                            traffic: trafficReminder,
                            isChinese: isChinese,
                          ),
                          onTrafficChanged: (value) => _updateNotifications(
                            expiry: expireReminder,
                            traffic: value,
                            isChinese: isChinese,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                _BalanceCard(
                  title: isChinese ? '账户余额（仅消费）' : 'Account Balance',
                  value: balance,
                ),
                const SizedBox(height: 16),
                _PreferenceCard(
                  isChinese: isChinese,
                  expireReminder: expireReminder,
                  trafficReminder: trafficReminder,
                  isSaving: _isSavingNotifications,
                  onExpireChanged: (value) => _updateNotifications(
                    expiry: value,
                    traffic: trafficReminder,
                    isChinese: isChinese,
                  ),
                  onTrafficChanged: (value) => _updateNotifications(
                    expiry: expireReminder,
                    traffic: value,
                    isChinese: isChinese,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _RiskActionCard(
                title: isChinese ? '修改你的密码' : 'Change Password',
                description: isChinese
                    ? '当你的账户发生泄漏时，可以在此修改密码，并重置订阅链接。避免带来不必要的损失。'
                    : 'Change your password here if you suspect account exposure.',
                buttonLabel: isChinese ? '立即修改' : 'Change Now',
                isLoading: _isChangingPassword,
                onPressed: () => _changePassword(isChinese),
              ),
              const SizedBox(height: 16),
              _RiskActionCard(
                title: isChinese ? '重置订阅链接' : 'Reset Subscription Link',
                description: isChinese
                    ? '当你的订阅链接发生泄漏被他人滥用时，可以在此重置订阅信息。避免带来不必要的损失。'
                    : 'Reset your subscription link if it has been leaked or abused.',
                buttonLabel: isChinese ? '立即重置' : 'Reset Now',
                isLoading: _isResettingSubscription,
                onPressed: () => _resetSubscription(isChinese),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.title,
    required this.value,
    this.fillHeight = false,
  });

  final String title;
  final String value;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('web-account-balance-card'),
      child: GradientCard(
        borderRadius: 30,
        padding: const EdgeInsets.all(28),
        child: fillHeight
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Center(
                      child: Text(
                        value,
                        style:
                            Theme.of(context).textTheme.displayMedium?.copyWith(
                                  fontSize: 84,
                                  height: 0.9,
                                ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                        ),
                  ),
                  const SizedBox(height: 54),
                  Center(
                    child: Text(
                      value,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 84,
                                height: 0.9,
                              ),
                    ),
                  ),
                  const SizedBox(height: 54),
                ],
              ),
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.isChinese,
    required this.expireReminder,
    required this.trafficReminder,
    required this.isSaving,
    required this.onExpireChanged,
    required this.onTrafficChanged,
  });

  final bool isChinese;
  final bool expireReminder;
  final bool trafficReminder;
  final bool isSaving;
  final ValueChanged<bool> onExpireChanged;
  final ValueChanged<bool> onTrafficChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('web-account-preference-card'),
      child: GradientCard(
        borderRadius: 30,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Text(
              isChinese ? '邮件通知' : 'Email Notifications',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 28,
                  ),
            ),
            const SizedBox(height: 20),
            _PreferenceTile(
              title: isChinese ? '到期邮件提醒' : 'Expiry Reminder',
              subtitle: isChinese
                  ? '我们会在套餐到期之前将邮件发送给您。'
                  : 'We will send an email reminder before the plan expires.',
              value: expireReminder,
              onChanged: isSaving ? null : onExpireChanged,
            ),
            const SizedBox(height: 14),
            _PreferenceTile(
              title: isChinese ? '流量邮件提醒' : 'Traffic Reminder',
              subtitle: isChinese
                  ? '我们会在流量用尽之前将邮件发送给您。'
                  : 'We will send an email reminder before traffic runs out.',
              value: trafficReminder,
              onChanged: isSaving ? null : onTrafficChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _RiskActionCard extends StatelessWidget {
  const _RiskActionCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.isLoading,
    required this.onPressed,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      borderRadius: 30,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                      ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: isLoading ? null : onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(buttonLabel),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordChangeRequest {
  const _PasswordChangeRequest({
    required this.oldPassword,
    required this.newPassword,
  });

  final String oldPassword;
  final String newPassword;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.isChinese});

  final bool isChinese;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final oldPassword = _oldController.text;
    final newPassword = _newController.text;
    final confirm = _confirmController.text;
    if (oldPassword.isEmpty || newPassword.length < 8) {
      setState(() {
        _error = widget.isChinese
            ? '旧密码不能为空，新密码至少 8 位。'
            : 'Old password is required and new password needs 8+ chars.';
      });
      return;
    }
    if (newPassword != confirm) {
      setState(() {
        _error = widget.isChinese ? '两次新密码不一致。' : 'Passwords do not match.';
      });
      return;
    }
    Navigator.of(context).pop(
      _PasswordChangeRequest(
        oldPassword: oldPassword,
        newPassword: newPassword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('web-account-change-password-dialog'),
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
                widget.isChinese ? '修改密码' : 'Change Password',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 32,
                    ),
              ),
              const SizedBox(height: 18),
              _DialogTextField(
                controller: _oldController,
                label: widget.isChinese ? '旧密码' : 'Old Password',
                obscureText: _obscure,
              ),
              const SizedBox(height: 12),
              _DialogTextField(
                controller: _newController,
                label: widget.isChinese ? '新密码' : 'New Password',
                obscureText: _obscure,
              ),
              const SizedBox(height: 12),
              _DialogTextField(
                controller: _confirmController,
                label: widget.isChinese ? '确认新密码' : 'Confirm Password',
                obscureText: _obscure,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.accentWarm,
                      ),
                ),
              ],
              const SizedBox(height: 22),
              _DialogButtonRow(
                cancelLabel: widget.isChinese ? '取消' : 'Cancel',
                confirmLabel: widget.isChinese ? '确认修改' : 'Change',
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountConfirmDialog extends StatelessWidget {
  const _AccountConfirmDialog({
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
      key: const Key('web-account-confirm-dialog'),
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
              _DialogButtonRow(
                cancelLabel: cancelLabel,
                confirmLabel: confirmLabel,
                onConfirm: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButtonRow extends StatelessWidget {
  const _DialogButtonRow({
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
  });

  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DialogCardButton(
            label: cancelLabel,
            emphasized: false,
            onTap: onCancel ?? () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DialogCardButton(
            label: confirmLabel,
            emphasized: true,
            onTap: onConfirm,
          ),
        ),
      ],
    );
  }
}

class _DialogCardButton extends StatelessWidget {
  const _DialogCardButton({
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
        enableBreathing: false,
        borderRadius: 18,
        hoverScale: 1.01,
        padding: EdgeInsets.zero,
        gradientColors: emphasized
            ? null
            : [
                AppColors.surface.withValues(alpha: 0.62),
                AppColors.surfaceAlt.withValues(alpha: 0.44),
              ],
        baseBorderColor:
            emphasized ? null : AppColors.border.withValues(alpha: 0.85),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color:
                  emphasized ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 15,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({
    required this.controller,
    required this.label,
    required this.obscureText,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: Theme.of(context).textTheme.titleMedium,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceAlt.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

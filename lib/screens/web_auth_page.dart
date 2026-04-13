import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_config.dart';
import '../services/panel_api.dart';
import '../theme/app_colors.dart';
import '../widgets/animated_background.dart';
import '../widgets/capybara_loader.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_crisp_widget.dart';

enum WebAuthMode { login, register, reset }

class WebAuthPage extends StatefulWidget {
  const WebAuthPage({super.key, required this.onAuthed});

  final VoidCallback onAuthed;

  @override
  State<WebAuthPage> createState() => _WebAuthPageState();
}

class _WebAuthPageState extends State<WebAuthPage> {
  final _api = PanelApi();
  final _config = ApiConfig();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteController = TextEditingController();
  final _emailCodeController = TextEditingController();
  final _newPasswordController = TextEditingController();

  WebAuthMode _mode = WebAuthMode.login;
  bool _loading = false;
  bool _isSendingVerify = false;
  bool _hidePassword = true;
  bool _hideNewPassword = true;
  int _countdown = 0;
  String? _message;
  Timer? _countdownTimer;

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
        'zh',
      );

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _inviteController.dispose();
    _emailCodeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      HapticFeedback.lightImpact();
      Map<String, dynamic> response;
      if (_mode == WebAuthMode.login) {
        response = await _api.login(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else if (_mode == WebAuthMode.register) {
        response = await _api.register(
          _emailController.text.trim(),
          _passwordController.text,
          inviteCode: _inviteController.text.trim(),
          emailCode: _emailCodeController.text.trim(),
        );
      } else {
        response = await _api.forgetPassword(
          _emailController.text.trim(),
          _emailCodeController.text.trim(),
          _newPasswordController.text,
        );
      }

      final sessionToken = (response['data'] ?? const {})['session_token'];
      if (sessionToken is String && sessionToken.isNotEmpty) {
        await _config.setSessionToken(sessionToken);
        await _config.dropLegacyAuth();
        await _config.refreshSessionCache();
      }

      if (_mode == WebAuthMode.reset) {
        if (mounted) {
          setState(() {
            _mode = WebAuthMode.login;
            _message = _isChinese(context)
                ? '密码已更新，请重新登录'
                : 'Password updated. Please log in again.';
          });
        }
        return;
      }

      widget.onAuthed();
    } catch (error) {
      final message = error is PanelApiException
          ? error.message
          : error.toString();
      if (mounted) {
        setState(() {
          _message = message;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendVerify() async {
    if (_countdown > 0 || _isSendingVerify) return;

    setState(() {
      _isSendingVerify = true;
      _message = null;
    });

    try {
      await _api.sendEmailVerify(_emailController.text.trim());
      if (mounted) {
        setState(() {
          _message = _isChinese(context)
              ? '验证码已发送，请留意邮箱'
              : 'Verification code sent. Please check your inbox.';
          _isSendingVerify = false;
        });
      }
      _startCountdown();
    } catch (error) {
      final message = error is PanelApiException
          ? error.message
          : error.toString();
      if (mounted) {
        setState(() {
          _message = message;
          _isSendingVerify = false;
        });
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1080;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.background,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            const Positioned.fill(
              child: AnimatedMeshBackground(child: SizedBox.expand()),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: _buildHeroPanel(context, isChinese)),
                              const SizedBox(width: 32),
                              SizedBox(
                                width: 460,
                                child: _buildAuthCard(context, isChinese),
                              ),
                            ],
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: _buildAuthCard(context, isChinese),
                          ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: IgnorePointer(child: WebCrispWidget())),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroPanel(BuildContext context, bool isChinese) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Capybara',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontSize: 56,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isChinese
                ? '一个更适合网页访问的轻量控制台入口。'
                : 'A focused web console experience built on the same Capybara design system.',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontSize: 28,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isChinese
                ? '登录后你可以查看公告、订阅概览、快捷入口，并通过右下角客服浮窗直接联系支持。'
                : 'Sign in to view announcements, subscription summaries, shortcuts, and reach support from the Crisp bubble.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 16,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(BuildContext context, bool isChinese) {
    return GradientCard(
      padding: const EdgeInsets.all(28),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Capybara',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontSize: 34,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _title(isChinese),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          _buildTextField(
            controller: _emailController,
            label: isChinese ? '邮箱地址' : 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          if (_mode == WebAuthMode.register) ...[
            _buildTextField(
              controller: _inviteController,
              label: isChinese ? '邀请码（可选）' : 'Invite Code (Optional)',
              icon: Icons.redeem_outlined,
            ),
            const SizedBox(height: 14),
          ],
          if (_mode != WebAuthMode.login) ...[
            _buildTextField(
              controller: _emailCodeController,
              label: isChinese ? '邮箱验证码' : 'Email Verification Code',
              icon: Icons.mark_email_read_outlined,
              suffix: _buildVerifyButton(isChinese),
            ),
            const SizedBox(height: 14),
          ],
          _buildTextField(
            controller: _mode == WebAuthMode.reset
                ? _newPasswordController
                : _passwordController,
            label: _mode == WebAuthMode.reset
                ? (isChinese ? '新密码' : 'New Password')
                : (isChinese ? '密码' : 'Password'),
            icon: Icons.lock_outline_rounded,
            obscureText: _mode == WebAuthMode.reset
                ? _hideNewPassword
                : _hidePassword,
            suffix: IconButton(
              onPressed: () {
                setState(() {
                  if (_mode == WebAuthMode.reset) {
                    _hideNewPassword = !_hideNewPassword;
                  } else {
                    _hidePassword = !_hidePassword;
                  }
                });
              },
              icon: Icon(
                (_mode == WebAuthMode.reset ? _hideNewPassword : _hidePassword)
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_mode == WebAuthMode.login)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _mode = WebAuthMode.reset),
                child: Text(
                  isChinese ? '忘记密码？' : 'Forgot Password?',
                ),
              ),
            ),
          if (_message != null) ...[
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.accentWarm,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _loading
                  ? const CapybaraLoader(size: 22, color: Colors.black)
                  : Text(
                      _submitLabel(isChinese),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          _buildModeFooter(isChinese),
        ],
      ),
    );
  }

  Widget _buildModeFooter(bool isChinese) {
    switch (_mode) {
      case WebAuthMode.login:
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              isChinese ? '还没有账号？' : "Don't have an account?",
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            TextButton(
              onPressed: () => setState(() => _mode = WebAuthMode.register),
              child: Text(isChinese ? '立即注册' : 'Create one'),
            ),
          ],
        );
      case WebAuthMode.register:
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              isChinese ? '已经有账号？' : 'Already have an account?',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            TextButton(
              onPressed: () => setState(() => _mode = WebAuthMode.login),
              child: Text(isChinese ? '返回登录' : 'Back to login'),
            ),
          ],
        );
      case WebAuthMode.reset:
        return Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: () => setState(() => _mode = WebAuthMode.login),
            child: Text(isChinese ? '返回登录' : 'Back to login'),
          ),
        );
    }
  }

  Widget _buildVerifyButton(bool isChinese) {
    if (_isSendingVerify) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: CapybaraLoader(size: 18),
      );
    }
    return TextButton(
      onPressed: _countdown > 0 ? null : _sendVerify,
      child: Text(
        _countdown > 0
            ? '${_countdown}s'
            : (isChinese ? '获取验证码' : 'Send Code'),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        suffixIcon: suffix,
      ),
    );
  }

  String _title(bool isChinese) {
    switch (_mode) {
      case WebAuthMode.login:
        return isChinese ? '登录你的网页控制台' : 'Sign in to your web console';
      case WebAuthMode.register:
        return isChinese ? '创建一个新的账号' : 'Create a new account';
      case WebAuthMode.reset:
        return isChinese ? '通过邮箱验证码重置密码' : 'Reset your password with email verification';
    }
  }

  String _submitLabel(bool isChinese) {
    switch (_mode) {
      case WebAuthMode.login:
        return isChinese ? '登录账号' : 'Sign In';
      case WebAuthMode.register:
        return isChinese ? '创建账号' : 'Create Account';
      case WebAuthMode.reset:
        return isChinese ? '更新密码' : 'Update Password';
    }
  }
}

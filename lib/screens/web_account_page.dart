import 'package:flutter/material.dart';

import '../models/web_mock_content.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_card.dart';
import '../widgets/web_page_frame.dart';

class WebAccountPage extends StatefulWidget {
  const WebAccountPage({super.key});

  @override
  State<WebAccountPage> createState() => _WebAccountPageState();
}

class _WebAccountPageState extends State<WebAccountPage> {
  late bool _expireReminder;
  late bool _trafficReminder;

  @override
  void initState() {
    super.initState();
    _expireReminder = webAccountMock.expireReminder;
    _trafficReminder = webAccountMock.trafficReminder;
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  void _showPendingAction(BuildContext context, bool isChinese, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isChinese
              ? '$action 先保留壳子交互，真实操作下一轮接入。'
              : '$action stays as a shell interaction for now. Real action comes next.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final wide = MediaQuery.of(context).size.width >= 1080;

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
                      value: webAccountMock.balance,
                      fillHeight: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _PreferenceCard(
                      isChinese: isChinese,
                      expireReminder: _expireReminder,
                      trafficReminder: _trafficReminder,
                      onExpireChanged: (value) =>
                          setState(() => _expireReminder = value),
                      onTrafficChanged: (value) =>
                          setState(() => _trafficReminder = value),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _BalanceCard(
              title: isChinese ? '账户余额（仅消费）' : 'Account Balance',
              value: webAccountMock.balance,
            ),
            const SizedBox(height: 16),
            _PreferenceCard(
              isChinese: isChinese,
              expireReminder: _expireReminder,
              trafficReminder: _trafficReminder,
              onExpireChanged: (value) =>
                  setState(() => _expireReminder = value),
              onTrafficChanged: (value) =>
                  setState(() => _trafficReminder = value),
            ),
          ],
          const SizedBox(height: 18),
          _RiskActionCard(
            title: isChinese ? '修改你的密码' : 'Change Password',
            description: isChinese
                ? '当你的账户发生泄漏时，可以在此修改密码，并重置订阅链接。避免带来不必要的损失。'
                : 'Change your password here if you suspect account exposure.',
            buttonLabel: isChinese ? '立即修改' : 'Change Now',
            onPressed: () => _showPendingAction(
              context,
              isChinese,
              isChinese ? '修改密码' : 'Change password',
            ),
          ),
          const SizedBox(height: 16),
          _RiskActionCard(
            title: isChinese ? '重置订阅链接' : 'Reset Subscription Link',
            description: isChinese
                ? '当你的订阅链接发生泄漏被他人滥用时，可以在此重置订阅信息。避免带来不必要的损失。'
                : 'Reset your subscription link if it has been leaked or abused.',
            buttonLabel: isChinese ? '立即重置' : 'Reset Now',
            onPressed: () => _showPendingAction(
              context,
              isChinese,
              isChinese ? '重置订阅链接' : 'Reset subscription link',
            ),
          ),
        ],
      ),
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
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(
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
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(
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
    required this.onExpireChanged,
    required this.onTrafficChanged,
  });

  final bool isChinese;
  final bool expireReminder;
  final bool trafficReminder;
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
              onChanged: onExpireChanged,
            ),
            const SizedBox(height: 14),
            _PreferenceTile(
              title: isChinese ? '流量邮件提醒' : 'Traffic Reminder',
              subtitle: isChinese
                  ? '我们会在流量用尽之前将邮件发送给您。'
                  : 'We will send an email reminder before traffic runs out.',
              value: trafficReminder,
              onChanged: onTrafficChanged,
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
  final ValueChanged<bool> onChanged;

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
    required this.onPressed,
  });

  final String title;
  final String description;
  final String buttonLabel;
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
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
                child: Text(buttonLabel),
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

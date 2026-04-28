import 'dart:async';

import 'package:flutter/material.dart';

import '../models/web_payment_return_data.dart';
import '../services/web_popup_window.dart';
import '../theme/app_colors.dart';

class WebPaymentReturnPage extends StatefulWidget {
  const WebPaymentReturnPage({
    super.key,
    required this.data,
  });

  final WebPaymentReturnData data;

  @override
  State<WebPaymentReturnPage> createState() => _WebPaymentReturnPageState();
}

class _WebPaymentReturnPageState extends State<WebPaymentReturnPage> {
  bool _attemptedClose = false;

  @override
  void initState() {
    super.initState();
    if (widget.data.isSuccess && WebPopupWindow.hasOpener) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_closePopupSoon());
      });
    }
  }

  bool _isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith(
            'zh',
          );

  Future<void> _closePopupSoon() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await WebPopupWindow.closeSelf();
    if (!mounted) return;
    setState(() => _attemptedClose = true);
  }

  @override
  Widget build(BuildContext context) {
    final isChinese = _isChinese(context);
    final isSuccess = widget.data.isSuccess;
    final title = isSuccess
        ? (isChinese ? '支付已完成' : 'Payment completed')
        : (isChinese ? '已返回支付结果' : 'Payment status received');
    final subtitle = isSuccess
        ? (WebPopupWindow.hasOpener
            ? (isChinese
                ? '支付窗口会自动关闭，原页面会继续同步订单状态。'
                : 'This payment window will close automatically while the original page refreshes the order state.')
            : (isChinese
                ? '请返回原页面查看订单状态。'
                : 'Return to the original page to check the order status.'))
        : (isChinese
            ? '请返回原页面确认订单状态。'
            : 'Return to the original page to confirm the order status.');
    final footer = _attemptedClose
        ? (isChinese
            ? '如果窗口没有自动关闭，可以直接手动关闭。'
            : 'If the window did not close automatically, close it manually.')
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            color: AppColors.surface.withValues(alpha: 0.96),
            elevation: 10,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    label: isChinese ? '订单号' : 'Order',
                    value: widget.data.orderRef,
                  ),
                  if (widget.data.paymentType.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: isChinese ? '支付方式' : 'Method',
                      value: widget.data.paymentType,
                    ),
                  ],
                  if (widget.data.tradeStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: isChinese ? '支付状态' : 'Status',
                      value: widget.data.tradeStatus,
                    ),
                  ],
                  if (footer != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      footer,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: WebPopupWindow.closeSelf,
                    child: Text(isChinese ? '关闭窗口' : 'Close window'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

import '../utils/formatters.dart';
import '../utils/rich_content_utils.dart';

enum WebPlanFilter { all, recurring, onetime }

extension WebPlanFilterX on WebPlanFilter {
  String label(bool isChinese) {
    switch (this) {
      case WebPlanFilter.all:
        return isChinese ? '全部套餐' : 'All Plans';
      case WebPlanFilter.recurring:
        return isChinese ? '周期性套餐' : 'Recurring';
      case WebPlanFilter.onetime:
        return isChinese ? '一次性套餐' : 'One-time';
    }
  }
}

class WebPlanViewData {
  WebPlanViewData({
    required this.id,
    required this.title,
    required this.summary,
    this.richContentHtml = '',
    required this.transferBytes,
    required this.periods,
    required this.features,
    this.deviceLimit,
    this.resetMethod,
  });

  final int id;
  final String title;
  final String summary;
  final String richContentHtml;
  final int transferBytes;
  final List<WebPlanPeriod> periods;
  final List<String> features;
  final int? deviceLimit;
  final int? resetMethod;

  WebPlanFilter get filter {
    if (periods.isNotEmpty &&
        periods.every((period) => period.key == 'onetime_price')) {
      return WebPlanFilter.onetime;
    }
    return WebPlanFilter.recurring;
  }

  bool get canBuy => id > 0 && periods.isNotEmpty;

  WebPlanPeriod? get primaryPeriod => periods.isEmpty ? null : periods.first;

  String get trafficLabel => Formatters.formatBytes(transferBytes);

  factory WebPlanViewData.fromJson(Map<String, dynamic> json) {
    final periods = <WebPlanPeriod>[];
    for (final definition in WebPlanPeriod.all) {
      final amount = _nullableInt(json[definition.amountField]);
      if (amount == null || amount <= 0) continue;
      periods.add(definition.withAmount(amount));
    }
    final richContent = buildRichContentData(json['summary']?.toString() ?? '');
    final summary = _cleanText(richContent.plainText);
    return WebPlanViewData(
      id: _toInt(json['plan_id']),
      title: json['title']?.toString() ?? 'Plan',
      summary: summary.isEmpty
          ? '包含流量 ${Formatters.formatBytes(_toInt(json['transfer_bytes']))}'
          : summary,
      richContentHtml: richContent.html,
      transferBytes: _toInt(json['transfer_bytes']),
      periods: periods,
      features: _featuresFromSummary(summary),
      deviceLimit: _nullableInt(json['device_limit']),
      resetMethod: _nullableInt(json['reset_method']),
    );
  }
}

class WebPlanPeriod {
  const WebPlanPeriod({
    required this.key,
    required this.amountField,
    required this.zhLabel,
    required this.enLabel,
    required this.amountCents,
  });

  final String key;
  final String amountField;
  final String zhLabel;
  final String enLabel;
  final int? amountCents;

  WebPlanPeriod withAmount(int amount) {
    return WebPlanPeriod(
      key: key,
      amountField: amountField,
      zhLabel: zhLabel,
      enLabel: enLabel,
      amountCents: amount,
    );
  }

  String label(bool isChinese) => isChinese ? zhLabel : enLabel;

  String get moneyLabel => amountCents == null
      ? '¥0'
      : '¥${Formatters.formatCurrency(amountCents!)}';

  static const all = <WebPlanPeriod>[
    WebPlanPeriod(
      key: 'month_price',
      amountField: 'monthly_amount',
      zhLabel: '月付',
      enLabel: 'Monthly',
      amountCents: null,
    ),
    WebPlanPeriod(
      key: 'quarter_price',
      amountField: 'quarterly_amount',
      zhLabel: '季付',
      enLabel: 'Quarterly',
      amountCents: null,
    ),
    WebPlanPeriod(
      key: 'half_year_price',
      amountField: 'half_year_amount',
      zhLabel: '半年付',
      enLabel: 'Half-year',
      amountCents: null,
    ),
    WebPlanPeriod(
      key: 'year_price',
      amountField: 'yearly_amount',
      zhLabel: '年付',
      enLabel: 'Yearly',
      amountCents: null,
    ),
    WebPlanPeriod(
      key: 'two_year_price',
      amountField: 'biennial_amount',
      zhLabel: '两年付',
      enLabel: 'Two years',
      amountCents: null,
    ),
    WebPlanPeriod(
      key: 'three_year_price',
      amountField: 'triennial_amount',
      zhLabel: '三年付',
      enLabel: 'Three years',
      amountCents: null,
    ),
    WebPlanPeriod(
      key: 'onetime_price',
      amountField: 'once_amount',
      zhLabel: '一次性',
      enLabel: 'One-time',
      amountCents: null,
    ),
    WebPlanPeriod(
      key: 'reset_price',
      amountField: 'reset_amount',
      zhLabel: '重置流量',
      enLabel: 'Traffic reset',
      amountCents: null,
    ),
  ];
}

class WebPaymentMethodData {
  WebPaymentMethodData({
    required this.id,
    required this.label,
    required this.provider,
    required this.feeFixedCents,
    required this.feeRate,
    this.iconUrl,
  });

  final int id;
  final String label;
  final String provider;
  final int feeFixedCents;
  final double feeRate;
  final String? iconUrl;

  int feeFor(int amountCents) {
    return feeFixedCents + ((amountCents * feeRate) / 100).round();
  }

  factory WebPaymentMethodData.fromJson(Map<String, dynamic> json) {
    return WebPaymentMethodData(
      id: _toInt(json['method_id']),
      label: json['label']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      feeFixedCents: _toInt(json['fee_fixed']),
      feeRate: _toDouble(json['fee_rate']),
      iconUrl: _trimmedOrNull(json['icon_url']),
    );
  }
}

class WebOrderDetailData {
  WebOrderDetailData({
    required this.orderRef,
    required this.stateCode,
    required this.periodKey,
    required this.amountTotal,
    required this.amountPayable,
    required this.amountDiscount,
    required this.amountBalance,
    required this.amountRefund,
    required this.amountSurplus,
    required this.amountHandling,
    required this.createdAt,
    this.plan,
    this.paymentMethod,
  });

  final String orderRef;
  final int stateCode;
  final String periodKey;
  final int amountTotal;
  final int amountPayable;
  final int amountDiscount;
  final int amountBalance;
  final int amountRefund;
  final int amountSurplus;
  final int amountHandling;
  final int createdAt;
  final WebPlanViewData? plan;
  final WebPaymentMethodData? paymentMethod;

  factory WebOrderDetailData.fromJson(
    Map<String, dynamic> json, {
    WebPlanViewData? fallbackPlan,
  }) {
    final planJson = json['plan'];
    final paymentJson = json['payment_method'];
    return WebOrderDetailData(
      orderRef: json['order_ref']?.toString() ?? '',
      stateCode: _toInt(json['state_code']),
      periodKey: json['period_key']?.toString() ?? '',
      amountTotal: _toInt(json['amount_total']),
      amountPayable: _toInt(json['amount_payable']),
      amountDiscount: _toInt(json['amount_discount']),
      amountBalance: _toInt(json['amount_balance']),
      amountRefund: _toInt(json['amount_refund']),
      amountSurplus: _toInt(json['amount_surplus']),
      amountHandling: _toInt(json['amount_handling']),
      createdAt: _toInt(json['created_at']),
      plan: planJson is Map
          ? WebPlanViewData.fromJson(Map<String, dynamic>.from(planJson))
          : fallbackPlan,
      paymentMethod: paymentJson is Map
          ? WebPaymentMethodData.fromJson(
              Map<String, dynamic>.from(paymentJson))
          : null,
    );
  }
}

class WebOrderListItemData {
  WebOrderListItemData({
    required this.orderRef,
    required this.stateCode,
    required this.periodKey,
    required this.amountTotal,
    required this.createdAt,
    required this.updatedAt,
    this.plan,
  });

  final String orderRef;
  final int stateCode;
  final String periodKey;
  final int amountTotal;
  final int createdAt;
  final int updatedAt;
  final WebPlanViewData? plan;

  bool get isPending => stateCode == 0;

  factory WebOrderListItemData.fromJson(Map<String, dynamic> json) {
    final planJson = json['plan'];
    return WebOrderListItemData(
      orderRef: json['order_ref']?.toString() ?? '',
      stateCode: _toInt(json['state_code']),
      periodKey: json['period_key']?.toString() ?? '',
      amountTotal: _toInt(json['amount_total']),
      createdAt: _toInt(json['created_at']),
      updatedAt: _toInt(json['updated_at']),
      plan: planJson is Map
          ? WebPlanViewData.fromJson(Map<String, dynamic>.from(planJson))
          : null,
    );
  }
}

class WebCheckoutActionData {
  WebCheckoutActionData({
    required this.kind,
    required this.code,
    this.payload,
  });

  final WebCheckoutActionKind kind;
  final int code;
  final Object? payload;

  factory WebCheckoutActionData.fromJson(Map<String, dynamic> json) {
    return WebCheckoutActionData(
      kind: WebCheckoutActionKindX.fromWire(json['kind']?.toString()),
      code: _toInt(json['code']),
      payload: json['payload'],
    );
  }
}

enum WebCheckoutActionKind {
  redirect,
  qrCode,
  completed,
  inlineFallback,
}

extension WebCheckoutActionKindX on WebCheckoutActionKind {
  static WebCheckoutActionKind fromWire(String? value) {
    switch (value) {
      case 'redirect':
        return WebCheckoutActionKind.redirect;
      case 'qr_code':
        return WebCheckoutActionKind.qrCode;
      case 'completed':
        return WebCheckoutActionKind.completed;
      default:
        return WebCheckoutActionKind.inlineFallback;
    }
  }
}

String _cleanText(String value) {
  return value
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('`', '')
      .replaceAll(RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'), r'$1')
      .replaceAll(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), r'$1')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

List<String> _featuresFromSummary(String summary) {
  final lines = summary
      .split(RegExp(r'[\n\r]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(4)
      .toList();
  if (lines.isNotEmpty) return lines;
  return const <String>[
    '按后台套餐配置展示',
    '购买后自动同步订阅状态',
    '支付方式由后台统一管理',
  ];
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value)?.toInt() ?? 0;
  return 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  return _toInt(value);
}

double _toDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String? _trimmedOrNull(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

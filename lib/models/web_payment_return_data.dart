class WebPaymentReturnData {
  const WebPaymentReturnData({
    required this.orderRef,
    required this.tradeNo,
    required this.outTradeNo,
    required this.paymentType,
    required this.tradeStatus,
    required this.queryParameters,
  });

  final String orderRef;
  final String tradeNo;
  final String outTradeNo;
  final String paymentType;
  final String tradeStatus;
  final Map<String, String> queryParameters;

  bool get isSuccess {
    final normalized = tradeStatus.trim().toUpperCase();
    return normalized == 'TRADE_SUCCESS' ||
        normalized == 'TRADE_FINISHED' ||
        normalized == 'SUCCESS';
  }

  static WebPaymentReturnData? tryParse(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) return null;

    final normalizedFragment =
        fragment.startsWith('/') ? fragment : '/$fragment';
    final queryIndex = normalizedFragment.indexOf('?');
    final pathPart = queryIndex >= 0
        ? normalizedFragment.substring(0, queryIndex)
        : normalizedFragment;
    final queryPart =
        queryIndex >= 0 ? normalizedFragment.substring(queryIndex + 1) : '';
    final pathSegments = Uri.parse(pathPart).pathSegments;
    if (pathSegments.length < 2 || pathSegments.first != 'order') {
      return null;
    }

    final queryParameters = queryPart.isEmpty
        ? const <String, String>{}
        : Uri.splitQueryString(queryPart);
    final hasPaymentSignal = queryParameters.containsKey('trade_status') ||
        queryParameters.containsKey('trade_no') ||
        queryParameters.containsKey('out_trade_no');
    if (!hasPaymentSignal) {
      return null;
    }

    return WebPaymentReturnData(
      orderRef: pathSegments[1],
      tradeNo: queryParameters['trade_no']?.trim() ?? '',
      outTradeNo: queryParameters['out_trade_no']?.trim() ?? '',
      paymentType: queryParameters['type']?.trim() ?? '',
      tradeStatus: queryParameters['trade_status']?.trim() ?? '',
      queryParameters: queryParameters,
    );
  }
}

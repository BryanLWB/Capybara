import 'package:capybara/models/web_payment_return_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses payment return fragment from hash route', () {
    final data = WebPaymentReturnData.tryParse(
      Uri.parse(
        'https://www.kapi-net.com/#/order/2026042320040329520142308?pid=2255&trade_no=2026042320430958897&out_trade_no=2026042320040329520142308&type=wxpay&trade_status=TRADE_SUCCESS',
      ),
    );

    expect(data, isNotNull);
    expect(data!.orderRef, '2026042320040329520142308');
    expect(data.tradeNo, '2026042320430958897');
    expect(data.outTradeNo, '2026042320040329520142308');
    expect(data.paymentType, 'wxpay');
    expect(data.tradeStatus, 'TRADE_SUCCESS');
    expect(data.isSuccess, isTrue);
  });

  test('ignores non-payment order fragments', () {
    final data = WebPaymentReturnData.tryParse(
      Uri.parse('https://www.kapi-net.com/#/order/2026042320040329520142308'),
    );

    expect(data, isNull);
  });
}

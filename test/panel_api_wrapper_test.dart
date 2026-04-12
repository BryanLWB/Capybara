import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/models/invite_data.dart';
import 'package:capybara/services/api_config.dart';
import 'package:capybara/services/app_api.dart';
import 'package:capybara/services/panel_api.dart';

void main() {
  test('legacy wrapper maps neutral account payload into legacy shape', () async {
    final api = PanelApi(
      config: ApiConfig(),
      appApi: _FakeAppApi(
        profile: <String, dynamic>{
          'data': <String, dynamic>{
            'account': <String, dynamic>{
              'email': 'u@example.com',
              'balance_amount': 200,
              'plan_id': 3,
              'transfer_bytes': 4096,
              'expiry_at': 1700000000,
              'avatar_url': 'https://example.com/avatar.png',
              'user_ref': 'user-1',
            },
          },
        },
      ),
    );

    final response = await api.getUserInfo();
    expect(
      response,
      <String, dynamic>{
        'data': <String, dynamic>{
          'email': 'u@example.com',
          'transfer_enable': 4096,
          'expired_at': 1700000000,
          'balance': 200,
          'plan_id': 3,
          'avatar_url': 'https://example.com/avatar.png',
          'uuid': 'user-1',
        },
      },
    );
  });

  test('legacy wrapper maps neutral referral records into InviteDetail objects', () async {
    final api = PanelApi(
      config: ApiConfig(),
      appApi: _FakeAppApi(
        inviteRecords: <String, dynamic>{
          'data': <String, dynamic>{
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'record_id': 1,
                'amount': 88,
                'trade_ref': 'T20260001',
                'order_amount': 188,
                'created_at': 1700000000,
                'status_text': 'Settled',
              },
            ],
          },
        },
      ),
    );

    final records = await api.fetchInviteDetails();
    expect(records, hasLength(1));
    expect(
      records.first,
      isA<InviteDetail>()
          .having((item) => item.amount, 'amount', 88)
          .having((item) => item.tradeNo, 'tradeNo', 'T20260001')
          .having((item) => item.orderAmount, 'orderAmount', 188)
          .having((item) => item.statusText, 'statusText', 'Settled'),
    );
  });
}

class _FakeAppApi extends AppApi {
  _FakeAppApi({
    Map<String, dynamic>? profile,
    Map<String, dynamic>? inviteRecords,
  })  : _profile = profile,
        _inviteRecords = inviteRecords,
        super(config: ApiConfig());

  final Map<String, dynamic>? _profile;
  final Map<String, dynamic>? _inviteRecords;

  @override
  Future<Map<String, dynamic>> getProfile() async =>
      _profile ?? jsonDecode('{"data":{"account":{}}}') as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> getInviteRecords() async =>
      _inviteRecords ??
      jsonDecode('{"data":{"items":[]}}') as Map<String, dynamic>;
}

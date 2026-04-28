import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/widgets/animated_card.dart';
import 'package:capybara/models/user_info.dart';
import 'package:capybara/models/web_client_import_option.dart';
import 'package:capybara/models/web_client_download.dart';
import 'package:capybara/models/web_home_view_data.dart';
import 'package:capybara/models/web_shell_section.dart';
import 'package:capybara/screens/web_home_page.dart';
import 'package:capybara/services/api_config.dart';
import 'package:capybara/services/app_api.dart';
import 'package:capybara/services/web_home_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

WebHomeViewData _homeData({
  bool hasSubscription = false,
  List<Map<String, dynamic>> notices = const <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'title': '最新可用地址',
      'content': '这里是公告内容，这里是公告内容。',
      'created_at': 1710000000,
    },
  ],
}) {
  return WebHomeViewData.fromSources(
    user: UserInfo(
      email: 'admin@local.test',
      transferEnable: hasSubscription ? 1024 : 0,
      expiredAt: hasSubscription ? 1710003600 : 0,
      balance: 0,
      planId: hasSubscription ? 1 : 0,
    ),
    subscription: <String, dynamic>{
      'u': 0,
      'd': 0,
      'transfer_enable': hasSubscription ? 1024 : 0,
      'expired_at': hasSubscription ? 1710003600 : 0,
      'reset_day': 0,
    },
    plans: const <Map<String, dynamic>>[],
    notices: notices,
  );
}

Widget _desktopHost(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
      'desktop zh web home renders without overflow and purchase card navigates',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    WebShellSection? navigatedSection;
    final data = _homeData();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: WebHomePage(
            onNavigate: (section) => navigatedSection = section,
            onUnauthorized: () {},
            dataLoader: (_) => SynchronousFuture(data),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('公告'), findsOneWidget);
    expect(find.text('订阅概览'), findsOneWidget);
    expect(find.text('购买套餐'), findsOneWidget);
    expect(find.text('最新可用地址'), findsOneWidget);
    expect(find.text('这里是公告内容，这里是公告内容。'), findsNothing);
    expect(
        find.byKey(const Key('web-subscription-empty-card')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('web-subscription-empty-card'))),
      isA<AnimatedCard>(),
    );
    expect(tester.takeException(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('购买套餐')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('购买套餐'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(navigatedSection, WebShellSection.purchase);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home notice opens detail dialog and rotates titles',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final data = _homeData(
      notices: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'title': '第一条公告',
          'content': '<p>第一条<strong>公告</strong>正文</p><ul><li>详情一</li></ul>',
          'created_at': 1710000000,
        },
        <String, dynamic>{
          'id': 2,
          'title': '第二条公告',
          'content': '## 第二条公告正文',
          'created_at': 1700000000,
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: WebHomePage(
            onNavigate: (_) {},
            onUnauthorized: () {},
            dataLoader: (_) => SynchronousFuture(data),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第一条公告'), findsOneWidget);
    expect(find.textContaining('第一条公告正文'), findsNothing);
    expect(find.byKey(const Key('web-home-notice-dot-0')), findsOneWidget);
    expect(find.byKey(const Key('web-home-notice-dot-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('web-home-notice-card-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('web-home-notice-dialog')), findsOneWidget);
    expect(find.text('第一条公告正文'), findsOneWidget);
    expect(find.text('详情一'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('web-home-notice-dot-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第二条公告'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第一条公告'), findsOneWidget);
    expect(find.textContaining('第二条公告正文'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home quick start actions use neutral subscription links',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    WebShellSection? navigatedSection;
    String? requestedFlag;
    var creatorCalls = 0;
    var downloadsCalls = 0;
    String? clipboardText;
    const link = 'http://127.0.0.1:8787/api/app/v1/client/subscription/cl_test';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map?)?['text']?.toString();
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(
      _desktopHost(
        WebHomePage(
          onNavigate: (section) => navigatedSection = section,
          onUnauthorized: () {},
          dataLoader: (_) =>
              SynchronousFuture(_homeData(hasSubscription: true)),
          subscriptionLinkCreator: (flag) async {
            creatorCalls += 1;
            requestedFlag = flag;
            return link;
          },
          downloadsLoader: () async {
            downloadsCalls += 1;
            return const <WebClientDownloadItem>[
              WebClientDownloadItem(
                platform: 'ios',
                label: 'iOS',
                available: false,
              ),
            ];
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('复制订阅链接'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(requestedFlag, 'shadowrocket');
    final clipboardData = await Clipboard.getData('text/plain');
    expect(clipboardData?.text, link);

    await tester.tap(find.text('二维码订阅'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const Key('web-home-subscription-qr-dialog')),
      findsOneWidget,
    );
    expect(find.text(link), findsOneWidget);
    expect(creatorCalls, 1);
    await tester.tap(find.text('关闭'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('下载客户端'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('下载客户端'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(navigatedSection, WebShellSection.help);
    expect(downloadsCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home blocks subscription actions when no subscription',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var creatorCalled = false;
    await tester.pumpWidget(
      _desktopHost(
        WebHomePage(
          onNavigate: (_) {},
          onUnauthorized: () {},
          dataLoader: (_) => SynchronousFuture(_homeData()),
          subscriptionLinkCreator: (_) async {
            creatorCalled = true;
            return 'https://example.com/sub';
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('复制订阅链接'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(creatorCalled, isFalse);
    expect(find.text('开通套餐后即可使用订阅链接。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home renders static loading frame before data resolves',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final completer = Completer<WebHomeViewData>();

    await tester.pumpWidget(
      _desktopHost(
        WebHomePage(
          onNavigate: (_) {},
          onUnauthorized: () {},
          dataLoader: (_) => completer.future,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('web-home-loading-state')), findsOneWidget);
    expect(find.text('公告'), findsOneWidget);
    expect(find.text('订阅概览'), findsOneWidget);
    expect(find.text('快速开始'), findsOneWidget);

    completer.complete(_homeData(hasSubscription: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('web-home-loading-state')), findsNothing);
    expect(find.text('流量使用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home renders cached snapshot while fresh data loads',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final freshCompleter = Completer<WebHomeViewData>();
    final store = _MemoryHomeSnapshotStore(
      cached: _homeData(
        hasSubscription: true,
        notices: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'title': '缓存公告',
            'content': '缓存内容',
            'created_at': 1710000000,
          },
        ],
      ),
    );

    await tester.pumpWidget(
      _desktopHost(
        WebHomePage(
          onNavigate: (_) {},
          onUnauthorized: () {},
          dataLoader: (_) => freshCompleter.future,
          homeSnapshotStore: store,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('缓存公告'), findsOneWidget);
    expect(find.byKey(const Key('web-home-loading-state')), findsNothing);

    freshCompleter.complete(
      _homeData(
        hasSubscription: true,
        notices: const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 2,
            'title': '实时公告',
            'content': '实时内容',
            'created_at': 1710000300,
          },
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('实时公告'), findsOneWidget);
    expect(store.writes, hasLength(1));
    expect(store.writes.single.latestNotice?.title, '实时公告');
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home clears snapshot on unauthorized refresh',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues(const <String, Object>{
      'app_session_token': 'as_test',
    });
    await ApiConfig().refreshSessionCache();
    final store = _MemoryHomeSnapshotStore(
      cached: _homeData(hasSubscription: true),
    );
    var unauthorized = false;

    await tester.pumpWidget(
      _desktopHost(
        WebHomePage(
          onNavigate: (_) {},
          onUnauthorized: () => unauthorized = true,
          dataLoader: (_) => Future<WebHomeViewData>.error(
            AppApiException(statusCode: 401, message: 'unauthorized'),
          ),
          homeSnapshotStore: store,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(store.cleared, isTrue);
    expect(unauthorized, isTrue);
    expect(await ApiConfig().getSessionToken(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web home keeps all import options visible when subscribed',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final importCalls = <String, int>{};
    await tester.pumpWidget(
      _desktopHost(
        WebHomePage(
          onNavigate: (_) {},
          onUnauthorized: () {},
          dataLoader: (_) =>
              SynchronousFuture(_homeData(hasSubscription: true)),
          importOptionsLoader: (platform) async {
            importCalls.update(
              platform,
              (value) => value + 1,
              ifAbsent: () => 1,
            );
            return const <WebClientImportOptionData>[
              WebClientImportOptionData(
                clientKey: 'shadowrocket',
                displayName: 'Shadowrocket',
                supported: true,
                actionType: 'deep_link',
                actionValue: 'shadowrocket://import',
                protocolHint: 'shadowrocket',
              ),
              WebClientImportOptionData(
                clientKey: 'quantumultx',
                displayName: 'Quantumult X',
                supported: true,
                actionType: 'copy_link',
                actionValue: 'quantumult-x://import',
                protocolHint: 'quantumultx',
              ),
              WebClientImportOptionData(
                clientKey: 'surge',
                displayName: 'Surge',
                supported: true,
                actionType: 'copy_link',
                actionValue: 'surge://import',
                protocolHint: 'surge',
              ),
            ];
          },
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Shadowrocket'), findsOneWidget);
    expect(find.text('Quantumult X'), findsOneWidget);
    expect(find.text('Surge'), findsOneWidget);
    expect(importCalls['ios'], 1);

    await tester.tap(find.text('Android'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(importCalls['android'], 1);

    await tester.tap(find.text('iOS'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(importCalls['ios'], 1);

    await tester.ensureVisible(find.text('Surge'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Surge'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemoryHomeSnapshotStore extends WebHomeSnapshotStore {
  _MemoryHomeSnapshotStore({this.cached}) : super(config: ApiConfig());

  WebHomeViewData? cached;
  final List<WebHomeViewData> writes = <WebHomeViewData>[];
  bool cleared = false;

  @override
  Future<WebHomeViewData?> read() async => cached;

  @override
  Future<void> write(WebHomeViewData data) async {
    writes.add(data);
    cached = data;
  }

  @override
  Future<void> clear() async {
    cleared = true;
    cached = null;
  }
}

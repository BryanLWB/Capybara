import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/models/help_article.dart';
import 'package:capybara/screens/web_help_page.dart';

Widget _desktopHost(Widget child) {
  return MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('help page shows empty state when knowledge base is empty',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _desktopHost(
        WebHelpPage(
          categoriesLoader: (_) async => <HelpCategory>[],
          articleLoader: (_, __) async => HelpArticleDetail(
            id: 1,
            category: '客户端下载',
            title: 'Windows 客户端',
            updatedAt: 1700000000,
            bodyHtml: '<p>正文</p>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.byKey(const Key('web-help-empty-state')), findsOneWidget);
    expect(find.text('暂时还没有帮助文章'), findsOneWidget);
    expect(find.text('官方推荐客户端'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('help page opens article dialog from knowledge list',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _desktopHost(
        WebHelpPage(
          categoriesLoader: (_) async => <HelpCategory>[
            HelpCategory(
              name: '客户端下载',
              articles: <HelpArticleSummary>[
                HelpArticleSummary(
                  id: 9,
                  category: '客户端下载',
                  title: 'Windows 客户端',
                  updatedAt: 1700000000,
                ),
              ],
            ),
          ],
          articleLoader: (_, __) async => HelpArticleDetail(
            id: 9,
            category: '客户端下载',
            title: 'Windows 客户端',
            updatedAt: 1700000000,
            bodyHtml: '<p>下载地址写在这里。</p>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(find.text('Windows 客户端'));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(find.byKey(const Key('web-help-article-dialog')), findsOneWidget);
    expect(find.text('下载地址写在这里。'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('web-help-article-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

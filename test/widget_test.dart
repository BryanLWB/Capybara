import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capybara/widgets/app_header.dart';

void main() {
  testWidgets('app header renders Capybara branding', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppHeader(),
        ),
      ),
    );

    expect(find.text('Capybara'), findsOneWidget);
    expect(find.text('Secure Network Connection'), findsOneWidget);
  });
}

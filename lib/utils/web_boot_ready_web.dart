import 'package:web/web.dart' as web;

void markWebFlutterReady() {
  web.document.body?.classList.add('capybara-flutter-ready');
}

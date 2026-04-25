import 'package:web/web.dart' as web;

class WebPopupWindow {
  static bool get hasOpener => web.window.opener != null;

  static Future<void> closeSelf() async {
    try {
      web.window.close();
    } catch (_) {
      // Ignore browser close restrictions; the page shows fallback text.
    }
  }
}

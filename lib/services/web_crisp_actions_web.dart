import 'dart:html' as html;
import 'dart:js_util' as js_util;

class WebCrispActions {
  static bool get isAvailable => js_util.hasProperty(html.window, r'$crisp');

  static Future<bool> openChat() async {
    if (!isAvailable) return false;

    try {
      final crisp = js_util.getProperty<Object>(html.window, r'$crisp');
      js_util.callMethod(crisp, 'push', <Object>[
        <String>['do', 'chat:open'],
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }
}

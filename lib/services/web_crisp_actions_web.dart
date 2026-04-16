import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class WebCrispActions {
  static bool get isAvailable => globalContext.has(r'$crisp');

  static Future<bool> openChat() async {
    if (!isAvailable) return false;

    try {
      final crisp = globalContext.getProperty<JSObject>(r'$crisp'.toJS);
      final command = <Object?>[
        <Object?>['do', 'chat:open'],
      ].jsify();
      if (command == null) return false;
      crisp.callMethod<JSAny?>('push'.toJS, command);
      return true;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'crisp_service.dart';

class WebCrispActions {
  static const String _bootstrapId = 'capybara-crisp-bootstrap';
  static const String _scriptId = 'capybara-crisp-script';
  static Future<void>? _mountFuture;

  static bool get isAvailable => globalContext.has(r'$crisp');

  static Future<bool> openChat() async {
    if (!isAvailable) {
      await (_mountFuture ??= _mount());
    }
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

  static Future<void> _mount() async {
    final websiteId = (await CrispService.getWebsiteId()).trim();
    if (websiteId.isEmpty) return;

    _appendBootstrap(websiteId);
    await _waitUntilAvailable();
  }

  static void _appendBootstrap(String websiteId) {
    web.document.getElementById(_bootstrapId)?.remove();

    final escapedWebsiteId = websiteId
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll("'", r"\'");
    final script = web.HTMLScriptElement()
      ..id = _bootstrapId
      ..type = 'text/javascript'
      ..text = '''
window.\$crisp = window.\$crisp || [];
window.CRISP_WEBSITE_ID = "$escapedWebsiteId";
(function () {
  if (document.getElementById("$_scriptId")) return;
  var d = document;
  var s = d.createElement("script");
  s.id = "$_scriptId";
  s.src = "https://client.crisp.chat/l.js";
  s.async = 1;
  d.head.appendChild(s);
})();
''';

    final root = web.document.body ?? web.document.head;
    root?.appendChild(script);
  }

  static Future<void> _waitUntilAvailable() async {
    for (var attempt = 0; attempt < 20; attempt += 1) {
      if (isAvailable) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}

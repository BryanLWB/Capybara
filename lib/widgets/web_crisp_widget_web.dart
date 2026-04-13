import 'dart:html' as html;

import 'package:flutter/widgets.dart';

import '../services/crisp_service.dart';

class WebCrispWidget extends StatefulWidget {
  const WebCrispWidget({super.key});

  @override
  State<WebCrispWidget> createState() => _WebCrispWidgetState();
}

class _WebCrispWidgetState extends State<WebCrispWidget> {
  @override
  void initState() {
    super.initState();
    _mountWidget();
  }

  Future<void> _mountWidget() async {
    final websiteId = (await CrispService.getWebsiteId()).trim();
    if (!mounted || websiteId.isEmpty) return;
    _WebCrispRuntime.instance.ensureMounted(websiteId);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _WebCrispRuntime {
  _WebCrispRuntime._();

  static final _WebCrispRuntime instance = _WebCrispRuntime._();

  String? _mountedWebsiteId;

  void ensureMounted(String websiteId) {
    if (_mountedWebsiteId == websiteId &&
        html.document.getElementById(_scriptId) != null) {
      return;
    }

    _mountedWebsiteId = websiteId;
    _appendBootstrap(websiteId);
  }

  static const String _bootstrapId = 'capybara-crisp-bootstrap';
  static const String _scriptId = 'capybara-crisp-script';

  void _appendBootstrap(String websiteId) {
    html.document.getElementById(_bootstrapId)?.remove();

    final escapedWebsiteId = websiteId
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll("'", r"\'");

    final script = html.ScriptElement()
      ..id = _bootstrapId
      ..type = 'text/javascript'
      ..text = '''
window.\$crisp = window.\$crisp || [];
window.CRISP_WEBSITE_ID = "$escapedWebsiteId";
(function () {
  if (document.getElementById("${_scriptId}")) return;
  var d = document;
  var s = d.createElement("script");
  s.id = "${_scriptId}";
  s.src = "https://client.crisp.chat/l.js";
  s.async = 1;
  d.head.appendChild(s);
})();
''';

    final root = html.document.body ?? html.document.head;
    root?.append(script);
  }
}

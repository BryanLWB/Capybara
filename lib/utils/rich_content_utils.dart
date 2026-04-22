import 'package:markdown/markdown.dart' as md;

class RichContentData {
  const RichContentData({
    required this.html,
    required this.plainText,
  });

  final String html;
  final String plainText;

  bool get isEmpty => html.isEmpty && plainText.isEmpty;
}

RichContentData buildRichContentData(String raw) {
  final source = raw.trim();
  if (source.isEmpty) {
    return const RichContentData(html: '', plainText: '');
  }

  final html = _sanitizeHtml(
    _looksLikeHtml(source)
        ? source
        : md.markdownToHtml(
            source,
            extensionSet: md.ExtensionSet.gitHubWeb,
          ),
  );

  return RichContentData(
    html: html,
    plainText: _plainTextFromHtml(html),
  );
}

bool _looksLikeHtml(String value) {
  return RegExp(r'<[a-zA-Z][^>]*>').hasMatch(value);
}

String _sanitizeHtml(String value) {
  return value
      .replaceAll(
        RegExp(
          r'<script[^>]*>.*?</script>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          "\\son\\w+=(\".*?\"|'.*?'|[^\\s>]+)",
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          "(href|src)=(\"|')\\s*javascript:[^\"']*(\"|')",
          caseSensitive: false,
        ),
        '',
      );
}

String _plainTextFromHtml(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

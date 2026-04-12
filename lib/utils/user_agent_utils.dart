import 'dart:io';

class UserAgentUtils {
  static String get userAgent {
    final os = Platform.operatingSystem.toLowerCase();
    switch (os) {
      case 'android':
        return 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Safari/537.36';
      case 'ios':
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148';
      case 'macos':
        return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36';
      case 'windows':
        return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Safari/537.36';
      default:
        return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Safari/537.36';
    }
  }
}

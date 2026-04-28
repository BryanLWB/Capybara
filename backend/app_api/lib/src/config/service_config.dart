import 'dart:io';

class ServiceConfig {
  ServiceConfig({
    required this.upstreamBaseUri,
    required this.port,
    required this.sessionTtl,
    required this.redisUrl,
    required this.upstreamTimeout,
    required this.requestJitterBase,
    required this.requestJitterSpread,
    required this.checkoutAllowedOrigins,
  });

  final Uri upstreamBaseUri;
  final int port;
  final Duration sessionTtl;
  final String? redisUrl;
  final Duration upstreamTimeout;
  final Duration requestJitterBase;
  final Duration requestJitterSpread;
  final List<Uri> checkoutAllowedOrigins;

  Uri? get checkoutDefaultOrigin =>
      checkoutAllowedOrigins.isEmpty ? null : checkoutAllowedOrigins.first;

  factory ServiceConfig.fromEnvironment() {
    final base = Platform.environment['UPSTREAM_BASE_URL'] ??
        Platform.environment['XBOARD_BASE_URL'] ??
        'http://127.0.0.1';
    return ServiceConfig(
      upstreamBaseUri: Uri.parse(base),
      port: int.tryParse(Platform.environment['PORT'] ?? '') ?? 8787,
      sessionTtl: Duration(
        seconds: int.tryParse(
              Platform.environment['APP_SESSION_TTL_SECONDS'] ?? '',
            ) ??
            604800,
      ),
      redisUrl: Platform.environment['REDIS_URL'],
      upstreamTimeout: Duration(
        seconds: int.tryParse(
              Platform.environment['UPSTREAM_TIMEOUT_SECONDS'] ?? '',
            ) ??
            20,
      ),
      requestJitterBase: Duration(
        milliseconds: int.tryParse(
              Platform.environment['UPSTREAM_RETRY_BASE_MS'] ?? '',
            ) ??
            350,
      ),
      requestJitterSpread: Duration(
        milliseconds: int.tryParse(
              Platform.environment['UPSTREAM_RETRY_SPREAD_MS'] ?? '',
            ) ??
            250,
      ),
      checkoutAllowedOrigins: parseCheckoutAllowedOrigins(
        Platform.environment['CHECKOUT_ALLOWED_ORIGINS'],
      ),
    );
  }

  static List<Uri> parseCheckoutAllowedOrigins(String? raw) {
    final values = (raw == null || raw.trim().isEmpty)
        ? const <String>[
            'https://www.kapi-net.com',
            'https://kapi-net.com',
            'http://localhost',
            'http://127.0.0.1',
          ]
        : raw.split(',');
    return values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map(Uri.tryParse)
        .whereType<Uri>()
        .where((uri) =>
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty)
        .toList(growable: false);
  }
}

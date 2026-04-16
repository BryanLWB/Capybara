import 'dart:convert';
import 'dart:io';

void main() {
  final root = Directory.current.path;
  final manifestFile = File('$root/config/upstream_route_manifest.json');
  final routesDir = Directory('$root/upstreams/xboard/app/Http/Routes/V1');

  if (!manifestFile.existsSync()) {
    stderr.writeln('Missing manifest: ${manifestFile.path}');
    exitCode = 1;
    return;
  }

  if (!routesDir.existsSync()) {
    stderr.writeln('Missing upstream routes directory: ${routesDir.path}');
    exitCode = 1;
    return;
  }

  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final requiredRoutes =
      (manifest['required_routes'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList();

  final declaredRoutes = <String>{};
  for (final entity in routesDir.listSync().whereType<File>()) {
    final content = entity.readAsStringSync();
    final prefixes = RegExp(r'''['"]prefix['"]\s*=>\s*['"]([^'"]+)['"]''')
        .allMatches(content)
        .map((match) => match.group(1))
        .whereType<String>()
        .toList();
    final matches = RegExp(r'''['"](/[^'"]+)['"]''').allMatches(content);
    for (final match in matches) {
      final route = match.group(1);
      if (route != null && route.startsWith('/')) {
        declaredRoutes.add(route);
        for (final prefix in prefixes) {
          declaredRoutes.add(_joinRoute(prefix, route));
        }
      }
    }
  }

  final missing =
      requiredRoutes.where((route) => !declaredRoutes.contains(route)).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing required upstream routes:');
    for (final route in missing) {
      stderr.writeln('  $route');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
      'Upstream route manifest check passed (${requiredRoutes.length} routes).');
}

String _joinRoute(String prefix, String route) {
  final normalizedPrefix =
      prefix.startsWith('/') ? prefix.substring(1) : prefix;
  return '/$normalizedPrefix$route'.replaceAll(RegExp(r'/+'), '/');
}

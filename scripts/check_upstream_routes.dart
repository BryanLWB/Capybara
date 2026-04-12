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

  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final requiredRoutes = (manifest['required_routes'] as List<dynamic>? ?? const [])
      .map((item) => item.toString())
      .toList();

  final declaredRoutes = <String>{};
  for (final entity in routesDir.listSync().whereType<File>()) {
    final content = entity.readAsStringSync();
    final matches = RegExp(r"['\"](/[^'\"]+)['\"]").allMatches(content);
    for (final match in matches) {
      final route = match.group(1);
      if (route != null && route.startsWith('/')) {
        declaredRoutes.add(route);
      }
    }
  }

  final missing = requiredRoutes.where((route) => !declaredRoutes.contains(route)).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing required upstream routes:');
    for (final route in missing) {
      stderr.writeln('  $route');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Upstream route manifest check passed (${requiredRoutes.length} routes).');
}

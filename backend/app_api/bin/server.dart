import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:app_api/app_api.dart';

Future<void> main() async {
  _configureLogging();

  final config = ServiceConfig.fromEnvironment();
  final sessionStore = await createSessionStore(config);
  final upstreamApi = UpstreamPanelApi(
    baseUri: config.upstreamBaseUri,
    timeout: config.upstreamTimeout,
    client: null,
    logger: Logger('UpstreamApi'),
  );
  final handler = createAppApiHandler(
    config: config,
    sessionStore: sessionStore,
    upstreamApi: upstreamApi,
    logger: Logger('EdgeApi'),
  );

  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  server.autoCompress = true;

  Logger('EdgeApi').info(
    'app_api listening on ${server.address.address}:${server.port}',
  );
}

void _configureLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stdout.writeln(
      '[${record.level.name}] ${record.time.toIso8601String()} '
      '${record.loggerName}: ${record.message}',
    );
  });
}

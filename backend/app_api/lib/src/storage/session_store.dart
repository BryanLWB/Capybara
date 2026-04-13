import 'dart:convert';
import 'dart:math';

import 'package:redis_dart_client/redis_dart_client.dart';

import '../config/service_config.dart';

class SessionRecord {
  SessionRecord({
    required this.id,
    required this.upstreamToken,
    required this.upstreamAuth,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String upstreamToken;
  final String upstreamAuth;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  SessionRecord copyWith({
    String? id,
    String? upstreamToken,
    String? upstreamAuth,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return SessionRecord(
      id: id ?? this.id,
      upstreamToken: upstreamToken ?? this.upstreamToken,
      upstreamAuth: upstreamAuth ?? this.upstreamAuth,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'upstream_token': upstreamToken,
        'upstream_auth': upstreamAuth,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    return SessionRecord(
      id: json['id'] as String? ?? '',
      upstreamToken: json['upstream_token'] as String? ?? '',
      upstreamAuth: json['upstream_auth'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract class SessionStore {
  Future<SessionRecord> create({
    required String upstreamToken,
    required String upstreamAuth,
    required Duration ttl,
  });

  Future<SessionRecord?> read(String sessionId);

  Future<void> write(SessionRecord record);

  Future<void> delete(String sessionId);
}

class MemorySessionStore implements SessionStore {
  final Map<String, SessionRecord> _records = <String, SessionRecord>{};

  @override
  Future<SessionRecord> create({
    required String upstreamToken,
    required String upstreamAuth,
    required Duration ttl,
  }) async {
    final now = DateTime.now().toUtc();
    final record = SessionRecord(
      id: _newSessionId(),
      upstreamToken: upstreamToken,
      upstreamAuth: upstreamAuth,
      createdAt: now,
      expiresAt: now.add(ttl),
    );
    _records[record.id] = record;
    return record;
  }

  @override
  Future<void> delete(String sessionId) async {
    _records.remove(sessionId);
  }

  @override
  Future<SessionRecord?> read(String sessionId) async {
    final record = _records[sessionId];
    if (record == null) return null;
    if (record.isExpired) {
      _records.remove(sessionId);
      return null;
    }
    return record;
  }

  @override
  Future<void> write(SessionRecord record) async {
    _records[record.id] = record;
  }
}

class RedisSessionStore implements SessionStore {
  RedisSessionStore(this._client);

  static const String _prefix = 'app_api:session:';
  final RedisClient _client;

  @override
  Future<SessionRecord> create({
    required String upstreamToken,
    required String upstreamAuth,
    required Duration ttl,
  }) async {
    final now = DateTime.now().toUtc();
    final record = SessionRecord(
      id: _newSessionId(),
      upstreamToken: upstreamToken,
      upstreamAuth: upstreamAuth,
      createdAt: now,
      expiresAt: now.add(ttl),
    );
    await _client.setex(
      '$_prefix${record.id}',
      jsonEncode(record.toJson()),
      ttl.inSeconds,
    );
    return record;
  }

  @override
  Future<void> delete(String sessionId) async {
    await _client.delete(['$_prefix$sessionId']);
  }

  @override
  Future<SessionRecord?> read(String sessionId) async {
    final value = await _client.get('$_prefix$sessionId');
    if (value == null || value.toString().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(value.toString());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final record = SessionRecord.fromJson(decoded);
    if (record.isExpired) {
      await delete(sessionId);
      return null;
    }
    return record;
  }

  @override
  Future<void> write(SessionRecord record) async {
    final ttl = record.expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    if (ttl <= 0) {
      await delete(record.id);
      return;
    }
    await _client.setex(
      '$_prefix${record.id}',
      jsonEncode(record.toJson()),
      ttl,
    );
  }
}

Future<SessionStore> createSessionStore(ServiceConfig config) async {
  if (config.redisUrl == null || config.redisUrl!.isEmpty) {
    return MemorySessionStore();
  }

  final uri = Uri.parse(config.redisUrl!);
  final client = RedisClient(
    host: uri.host,
    port: uri.hasPort ? uri.port : 6379,
    password: uri.userInfo.contains(':')
        ? uri.userInfo.split(':').last
        : (uri.userInfo.isEmpty ? null : uri.userInfo),
  );
  await client.connect();
  return RedisSessionStore(client);
}

String _newSessionId() {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  final buffer = StringBuffer('as_');
  for (var i = 0; i < 40; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

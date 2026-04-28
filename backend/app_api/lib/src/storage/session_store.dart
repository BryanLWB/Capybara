import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:redis_dart_client/redis_dart_client.dart';

import '../config/service_config.dart';

class SessionRecord {
  SessionRecord({
    required this.id,
    required this.upstreamToken,
    required this.upstreamAuth,
    this.ownerKey,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String upstreamToken;
  final String upstreamAuth;
  final String? ownerKey;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  SessionRecord copyWith({
    String? id,
    String? upstreamToken,
    String? upstreamAuth,
    String? ownerKey,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return SessionRecord(
      id: id ?? this.id,
      upstreamToken: upstreamToken ?? this.upstreamToken,
      upstreamAuth: upstreamAuth ?? this.upstreamAuth,
      ownerKey: ownerKey ?? this.ownerKey,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'upstream_token': upstreamToken,
        'upstream_auth': upstreamAuth,
        'owner_key': ownerKey,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    return SessionRecord(
      id: json['id'] as String? ?? '',
      upstreamToken: json['upstream_token'] as String? ?? '',
      upstreamAuth: json['upstream_auth'] as String? ?? '',
      ownerKey: json['owner_key'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class SubscriptionAccessRecord {
  SubscriptionAccessRecord({
    required this.id,
    required this.upstreamToken,
    required this.upstreamAuth,
    required this.ownerKey,
    required this.generation,
    required this.createdAt,
    required this.expiresAt,
    this.flag,
  });

  final String id;
  final String upstreamToken;
  final String upstreamAuth;
  final String ownerKey;
  final int generation;
  final String? flag;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'upstream_token': upstreamToken,
        'upstream_auth': upstreamAuth,
        'owner_key': ownerKey,
        'generation': generation,
        'flag': flag,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  factory SubscriptionAccessRecord.fromJson(Map<String, dynamic> json) {
    return SubscriptionAccessRecord(
      id: json['id'] as String? ?? '',
      upstreamToken: json['upstream_token'] as String? ?? '',
      upstreamAuth: json['upstream_auth'] as String? ?? '',
      ownerKey: json['owner_key'] as String? ?? '',
      generation: json['generation'] as int? ?? 0,
      flag: json['flag'] as String?,
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
    String? ownerKey,
    required Duration ttl,
  });

  Future<SessionRecord?> read(String sessionId);

  Future<void> write(SessionRecord record);

  Future<void> delete(String sessionId);

  Future<SubscriptionAccessRecord> createSubscriptionAccess({
    required String upstreamToken,
    required String upstreamAuth,
    required String ownerKey,
    required int generation,
    required Duration ttl,
    String? flag,
  });

  Future<SubscriptionAccessRecord?> readSubscriptionAccess(String accessId);

  Future<int> readSubscriptionGeneration(String ownerKey);

  Future<int> bumpSubscriptionGeneration(String ownerKey);

  Future<void> revokeSubscriptionAccesses(String ownerKey);
}

class MemorySessionStore implements SessionStore {
  final Map<String, SessionRecord> _records = <String, SessionRecord>{};
  final Map<String, SubscriptionAccessRecord> _subscriptionAccess =
      <String, SubscriptionAccessRecord>{};
  final Map<String, int> _subscriptionGenerations = <String, int>{};
  final Map<String, Set<String>> _subscriptionOwners = <String, Set<String>>{};

  @override
  Future<SessionRecord> create({
    required String upstreamToken,
    required String upstreamAuth,
    String? ownerKey,
    required Duration ttl,
  }) async {
    final now = DateTime.now().toUtc();
    final record = SessionRecord(
      id: _newSessionId(),
      upstreamToken: upstreamToken,
      upstreamAuth: upstreamAuth,
      ownerKey: ownerKey,
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

  @override
  Future<SubscriptionAccessRecord> createSubscriptionAccess({
    required String upstreamToken,
    required String upstreamAuth,
    required String ownerKey,
    required int generation,
    required Duration ttl,
    String? flag,
  }) async {
    final now = DateTime.now().toUtc();
    final record = SubscriptionAccessRecord(
      id: _newAccessId(),
      upstreamToken: upstreamToken,
      upstreamAuth: upstreamAuth,
      ownerKey: ownerKey,
      generation: generation,
      flag: flag,
      createdAt: now,
      expiresAt: now.add(ttl),
    );
    _subscriptionAccess[record.id] = record;
    _subscriptionOwners.putIfAbsent(ownerKey, () => <String>{}).add(record.id);
    return record;
  }

  @override
  Future<SubscriptionAccessRecord?> readSubscriptionAccess(
      String accessId) async {
    final record = _subscriptionAccess[accessId];
    if (record == null) return null;
    if (record.isExpired) {
      _removeSubscriptionAccess(record);
      return null;
    }
    return record;
  }

  @override
  Future<int> readSubscriptionGeneration(String ownerKey) async {
    return _subscriptionGenerations[ownerKey] ?? 0;
  }

  @override
  Future<int> bumpSubscriptionGeneration(String ownerKey) async {
    final next = (_subscriptionGenerations[ownerKey] ?? 0) + 1;
    _subscriptionGenerations[ownerKey] = next;
    return next;
  }

  @override
  Future<void> revokeSubscriptionAccesses(String ownerKey) async {
    final accessIds = _subscriptionOwners.remove(ownerKey);
    if (accessIds == null || accessIds.isEmpty) {
      return;
    }
    for (final accessId in accessIds) {
      _subscriptionAccess.remove(accessId);
    }
  }

  void _removeSubscriptionAccess(SubscriptionAccessRecord record) {
    _subscriptionAccess.remove(record.id);
    final ownerAccess = _subscriptionOwners[record.ownerKey];
    ownerAccess?.remove(record.id);
    if (ownerAccess != null && ownerAccess.isEmpty) {
      _subscriptionOwners.remove(record.ownerKey);
    }
  }
}

class RedisSessionStore implements SessionStore {
  RedisSessionStore(this._client);

  static const String _prefix = 'app_api:session:';
  static const String _subscriptionPrefix = 'app_api:subscription_access:';
  static const String _subscriptionGenerationPrefix =
      'app_api:subscription_generation:';
  static const String _subscriptionOwnerPrefix = 'app_api:subscription_owner:';
  final RedisClient _client;
  Future<void> _operationQueue = Future<void>.value();

  @override
  Future<SessionRecord> create({
    required String upstreamToken,
    required String upstreamAuth,
    String? ownerKey,
    required Duration ttl,
  }) async {
    final now = DateTime.now().toUtc();
    final record = SessionRecord(
      id: _newSessionId(),
      upstreamToken: upstreamToken,
      upstreamAuth: upstreamAuth,
      ownerKey: ownerKey,
      createdAt: now,
      expiresAt: now.add(ttl),
    );
    await _runExclusive(
      () => _client.setex(
        '$_prefix${record.id}',
        jsonEncode(record.toJson()),
        ttl.inSeconds,
      ),
    );
    return record;
  }

  @override
  Future<void> delete(String sessionId) async {
    await _runExclusive(() => _client.delete(['$_prefix$sessionId']));
  }

  @override
  Future<SessionRecord?> read(String sessionId) async {
    return _runExclusive(() async {
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
        await _client.delete(['$_prefix$sessionId']);
        return null;
      }
      return record;
    });
  }

  @override
  Future<void> write(SessionRecord record) async {
    final ttl = record.expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    await _runExclusive(() async {
      if (ttl <= 0) {
        await _client.delete(['$_prefix${record.id}']);
        return;
      }
      await _client.setex(
        '$_prefix${record.id}',
        jsonEncode(record.toJson()),
        ttl,
      );
    });
  }

  @override
  Future<SubscriptionAccessRecord> createSubscriptionAccess({
    required String upstreamToken,
    required String upstreamAuth,
    required String ownerKey,
    required int generation,
    required Duration ttl,
    String? flag,
  }) async {
    final now = DateTime.now().toUtc();
    final record = SubscriptionAccessRecord(
      id: _newAccessId(),
      upstreamToken: upstreamToken,
      upstreamAuth: upstreamAuth,
      ownerKey: ownerKey,
      generation: generation,
      flag: flag,
      createdAt: now,
      expiresAt: now.add(ttl),
    );
    await _runExclusive(() async {
      await _client.setex(
        '$_subscriptionPrefix${record.id}',
        jsonEncode(record.toJson()),
        ttl.inSeconds,
      );
      final accessIds = await _readOwnerAccessIds(ownerKey)
        ..add(record.id);
      await _writeOwnerAccessIds(ownerKey, accessIds);
    });
    return record;
  }

  @override
  Future<SubscriptionAccessRecord?> readSubscriptionAccess(
      String accessId) async {
    return _runExclusive(() async {
      final key = '$_subscriptionPrefix$accessId';
      final value = await _client.get(key);
      if (value == null || value.toString().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(value.toString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final record = SubscriptionAccessRecord.fromJson(decoded);
      if (record.isExpired) {
        await _client.delete([key]);
        final accessIds = await _readOwnerAccessIds(record.ownerKey)
          ..remove(record.id);
        await _writeOwnerAccessIds(record.ownerKey, accessIds);
        return null;
      }
      return record;
    });
  }

  @override
  Future<int> readSubscriptionGeneration(String ownerKey) async {
    return _runExclusive(() async {
      final value =
          await _client.get('$_subscriptionGenerationPrefix$ownerKey');
      if (value == null || value.toString().isEmpty) {
        return 0;
      }
      return int.tryParse(value.toString()) ?? 0;
    });
  }

  @override
  Future<int> bumpSubscriptionGeneration(String ownerKey) async {
    return _runExclusive(
      () => _client.incr('$_subscriptionGenerationPrefix$ownerKey'),
    );
  }

  @override
  Future<void> revokeSubscriptionAccesses(String ownerKey) async {
    await _runExclusive(() async {
      final accessIds = await _readOwnerAccessIds(ownerKey);
      if (accessIds.isNotEmpty) {
        await _client.delete(
          accessIds.map((id) => '$_subscriptionPrefix$id').toList(),
        );
      }
      await _client.delete(['$_subscriptionOwnerPrefix$ownerKey']);
    });
  }

  Future<List<String>> _readOwnerAccessIds(String ownerKey) async {
    final value = await _client.get('$_subscriptionOwnerPrefix$ownerKey');
    if (value == null || value.toString().isEmpty) {
      return <String>[];
    }
    final decoded = jsonDecode(value.toString());
    if (decoded is! List) {
      return <String>[];
    }
    return decoded
        .map((item) => item?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _writeOwnerAccessIds(String ownerKey, List<String> accessIds) {
    final key = '$_subscriptionOwnerPrefix$ownerKey';
    if (accessIds.isEmpty) {
      return _client.delete([key]);
    }
    return _client.set(key, jsonEncode(accessIds));
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final previous = _operationQueue;
    final gate = Completer<void>();
    _operationQueue = gate.future;
    return previous.catchError((_) {}).then((_) async {
      try {
        return await operation();
      } finally {
        gate.complete();
      }
    });
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
  return _randomId('as_');
}

String _newAccessId() {
  return _randomId('cl_');
}

String _randomId(String prefix) {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  final buffer = StringBuffer(prefix);
  for (var i = 0; i < 40; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

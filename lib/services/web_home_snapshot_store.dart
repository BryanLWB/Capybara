import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_home_view_data.dart';
import 'api_config.dart';

class WebHomeSnapshotStore {
  WebHomeSnapshotStore({
    ApiConfig? config,
    Duration maxAge = const Duration(hours: 6),
  })  : _config = config ?? ApiConfig(),
        _maxAge = maxAge;

  static const _storageKey = 'web_home_snapshot_v1';
  static const _version = 1;

  final ApiConfig _config;
  final Duration _maxAge;

  Future<WebHomeViewData?> read() async {
    try {
      final tokenFingerprint = await _currentSessionFingerprint();
      if (tokenFingerprint == null) {
        await clear();
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return null;

      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['version'] != _version ||
          envelope['session'] != tokenFingerprint) {
        await clear();
        return null;
      }

      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        _toInt(envelope['saved_at']),
      );
      if (DateTime.now().difference(savedAt) > _maxAge) {
        await clear();
        return null;
      }

      final data = Map<String, dynamic>.from(
        envelope['data'] as Map? ?? const {},
      );
      return WebHomeViewData.fromJson(data);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> write(WebHomeViewData data) async {
    try {
      final tokenFingerprint = await _currentSessionFingerprint();
      if (tokenFingerprint == null) {
        await clear();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(<String, dynamic>{
          'version': _version,
          'session': tokenFingerprint,
          'saved_at': DateTime.now().millisecondsSinceEpoch,
          'data': data.toJson(),
        }),
      );
    } catch (_) {
      // Snapshot caching is a best-effort speed optimization.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {
      // Ignore storage failures.
    }
  }

  Future<String?> _currentSessionFingerprint() async {
    final token = await _config.getSessionToken();
    if (token == null || token.isEmpty) return null;
    return _fnv1a32(token);
  }

  String _fnv1a32(String value) {
    const mask = 0xffffffff;
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & mask;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

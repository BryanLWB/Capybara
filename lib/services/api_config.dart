import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'remote_config_service.dart';
import 'user_data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const _sessionTokenKey = 'app_session_token';
  static const _legacyTokenKey = 'api_token';
  static const _legacyAuthDataKey = 'api_auth_data';
  static const _webApiDefaultDomain = String.fromEnvironment(
    'APP_API_DEFAULT_DOMAIN',
    defaultValue: '',
  );

  static String? _sessionTokenCache;

  Future<String> getBaseUrl() async {
    if (kIsWeb) {
      final webBase = webBaseUrlFor(Uri.base);
      if (webBase != null) return webBase;
    }

    final domain = await RemoteConfigService().getActiveDomain();
    return composeApiBaseUrl(domain);
  }

  @visibleForTesting
  static String composeApiBaseUrl(String domain) {
    final cleanDomain =
        domain.endsWith('/') ? domain.substring(0, domain.length - 1) : domain;
    return '$cleanDomain/api/app/v1';
  }

  @visibleForTesting
  static String? webBaseUrlFor(
    Uri currentUri, {
    String explicitApiDomain = _webApiDefaultDomain,
  }) {
    if (!_isPlaceholderApiDomain(explicitApiDomain)) {
      return composeApiBaseUrl(explicitApiDomain);
    }

    if (currentUri.hasScheme && currentUri.host.isNotEmpty) {
      return '${currentUri.scheme}://${currentUri.authority}/api/app/v1';
    }

    return null;
  }

  static bool _isPlaceholderApiDomain(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    return trimmed.contains('your-api-domain.com');
  }

  Future<String?> getSessionToken() async {
    final cached = _sessionTokenCache;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_sessionTokenKey);
      _sessionTokenCache = value;
      return value;
    } catch (error) {
      debugPrint('[ApiConfig] Failed to read session token: $error');
      return null;
    }
  }

  Future<void> setSessionToken(String? token) async {
    _sessionTokenCache = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null || token.isEmpty) {
        await prefs.remove(_sessionTokenKey);
        return;
      }
      await prefs.setString(_sessionTokenKey, token);
    } catch (error) {
      debugPrint('[ApiConfig] Failed to persist session token: $error');
    }
  }

  Future<void> clearAuth() async {
    _sessionTokenCache = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionTokenKey);
      await prefs.remove(_legacyTokenKey);
      await prefs.remove(_legacyAuthDataKey);
    } catch (error) {
      debugPrint('[ApiConfig] Failed to clear auth storage: $error');
    }
    // 清除用户数据缓存
    UserDataService().clearCache();
  }

  Future<void> refreshSessionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sessionTokenCache = prefs.getString(_sessionTokenKey);
    } catch (error) {
      debugPrint('[ApiConfig] Failed to refresh session cache: $error');
    }
  }

  Future<void> dropLegacyAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyTokenKey);
      await prefs.remove(_legacyAuthDataKey);
    } catch (error) {
      debugPrint('[ApiConfig] Failed to drop legacy auth: $error');
    }
  }

  Future<bool> hasLegacyAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_legacyTokenKey) ||
          prefs.containsKey(_legacyAuthDataKey);
    } catch (error) {
      debugPrint('[ApiConfig] Failed to inspect legacy auth: $error');
      return false;
    }
  }
}

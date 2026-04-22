import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'crisp_bridge.dart';
import 'platform_service.dart';
import 'remote_config_service.dart';

/// Crisp Chat Service for customer support
/// - Mobile (iOS/Android): Uses native Crisp SDK
/// - Desktop (Windows/macOS/Linux): Opens Crisp web chat in browser
class CrispService {
  // Default Website ID (fallback if remote config is unavailable)
  // TODO: Replace with your own Crisp Website ID if you don't use remote config
  static const String _defaultWebsiteId = '';
  static const String webChatBaseUrl = 'https://go.crisp.chat/chat/embed/';

  /// Get Website ID from remote config, fallback to default
  static Future<String> getWebsiteId() async {
    try {
      final remoteId = await RemoteConfigService().getCrispWebsiteId();
      if (remoteId != null && remoteId.isNotEmpty) {
        return remoteId;
      }
    } catch (e) {
      debugPrint('Error fetching Crisp Website ID from remote config: $e');
    }
    return _defaultWebsiteId;
  }

  /// Check if native Crisp SDK is supported on current platform
  static bool get isNativeSupported {
    return !kIsWeb && PlatformService.instance.isMobile;
  }

  /// Open Crisp chat with full user profile
  /// On mobile: Opens native Crisp SDK
  /// On desktop: Opens web browser with Crisp chat
  static Future<void> openChat({
    String? userEmail,
    String? userName,
    String? plan,
    String? expires,
    String? traffic,
    String? balance,
  }) async {
    // Fetch Website ID from remote config
    final websiteId = await getWebsiteId();
    
    if (isNativeSupported) {
      await _openNativeChat(
        websiteId: websiteId,
        userEmail: userEmail,
        userName: userName,
        plan: plan,
        expires: expires,
        traffic: traffic,
        balance: balance,
      );
    } else {
      await _openWebChat(
        websiteId: websiteId,
        userEmail: userEmail,
        userName: userName,
        plan: plan,
        expires: expires,
        traffic: traffic,
        balance: balance,
      );
    }
  }

  /// Open native Crisp chat (iOS/Android only)
  static Future<void> _openNativeChat({
    required String websiteId,
    String? userEmail,
    String? userName,
    String? plan,
    String? expires,
    String? traffic,
    String? balance,
  }) async {
    // 1. Try to set session data (might fail if session not loaded yet)
    try {
      await CrispBridge.setSessionData(
        userEmail: userEmail,
        userName: userName,
        plan: plan,
        expires: expires,
        traffic: traffic,
        balance: balance,
      );
    } catch (e) {
      // Ignore session errors - session might not be loaded yet on first run
      debugPrint('Crisp session data setting skipped (not critical): $e');
    }

    // 2. Open Chat (Crucial step)
    try {
      await CrispBridge.openChat(
        websiteId: websiteId,
        userEmail: userEmail,
        userName: userName,
      );
    } catch (e) {
      debugPrint('Error opening native Crisp chat: $e');
      // Fallback to web chat if native fails entirely
      await _openWebChat(
        websiteId: websiteId,
        userEmail: userEmail,
        userName: userName,
        plan: plan,
        expires: expires,
        traffic: traffic,
        balance: balance,
      );
    }
  }

  /// Open Crisp web chat in browser (for desktop platforms)
  /// Passes user data through URL parameters
  static Future<void> _openWebChat({
    required String websiteId,
    String? userEmail,
    String? userName,
    String? plan,
    String? expires,
    String? traffic,
    String? balance,
  }) async {
    // Build query parameters with user data
    final queryParams = <String, String>{
      'website_id': websiteId,
    };
    
    // Add user email
    if (userEmail != null && userEmail.isNotEmpty) {
      queryParams['user_email'] = userEmail;
    }
    
    // Add user nickname
    if (userName != null && userName.isNotEmpty) {
      queryParams['user_nickname'] = userName;
    }
    
    // Add custom data fields
    if (plan != null && plan.isNotEmpty) {
      queryParams['data[plan]'] = plan;
    }
    if (expires != null && expires.isNotEmpty) {
      queryParams['data[expires]'] = expires;
    }
    if (traffic != null && traffic.isNotEmpty) {
      queryParams['data[traffic]'] = traffic;
    }
    if (balance != null && balance.isNotEmpty) {
      queryParams['data[balance]'] = balance;
    }
    
    // Add segment
    queryParams['data[segment]'] = 'app_user';
    
    // Build the URL with parameters
    final uri = Uri.parse(webChatBaseUrl).replace(queryParameters: queryParams);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Reset Crisp chat session (useful when user logs out)
  static Future<void> resetSession() async {
    if (isNativeSupported) {
      try {
        await CrispBridge.resetSession();
      } catch (e) {
        debugPrint('Error resetting Crisp session: $e');
      }
    }
  }
}

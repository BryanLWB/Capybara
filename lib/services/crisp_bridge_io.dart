import 'package:crisp_chat/crisp_chat.dart';

class CrispBridge {
  static Future<void> setSessionData({
    String? userEmail,
    String? userName,
    String? plan,
    String? expires,
    String? traffic,
    String? balance,
  }) async {
    if (userEmail != null && userEmail.isNotEmpty) {
      FlutterCrispChat.setSessionString(key: 'email', value: userEmail);
    }
    if (userName != null && userName.isNotEmpty) {
      FlutterCrispChat.setSessionString(key: 'nickname', value: userName);
    }
    if (plan != null && plan.isNotEmpty) {
      FlutterCrispChat.setSessionString(key: 'plan', value: plan);
    }
    if (expires != null && expires.isNotEmpty) {
      FlutterCrispChat.setSessionString(key: 'expires', value: expires);
    }
    if (traffic != null && traffic.isNotEmpty) {
      FlutterCrispChat.setSessionString(key: 'traffic', value: traffic);
    }
    if (balance != null && balance.isNotEmpty) {
      FlutterCrispChat.setSessionString(key: 'balance', value: balance);
    }
    FlutterCrispChat.setSessionSegments(
      segments: const ['app_user'],
      overwrite: false,
    );
  }

  static Future<void> openChat({
    required String websiteId,
    String? userEmail,
    String? userName,
  }) {
    User? crispUser;
    if (userEmail != null || userName != null) {
      crispUser = User(
        email: userEmail,
        nickName: userName,
      );
    }

    final config = CrispConfig(
      websiteID: websiteId,
      user: crispUser,
      enableNotifications: true,
    );
    return FlutterCrispChat.openCrispChat(config: config);
  }

  static Future<void> resetSession() {
    return FlutterCrispChat.resetCrispChatSession();
  }
}

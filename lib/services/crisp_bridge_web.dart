class CrispBridge {
  static Future<void> setSessionData({
    String? userEmail,
    String? userName,
    String? plan,
    String? expires,
    String? traffic,
    String? balance,
  }) async {}

  static Future<void> openChat({
    required String websiteId,
    String? userEmail,
    String? userName,
  }) async {}

  static Future<void> resetSession() async {}
}

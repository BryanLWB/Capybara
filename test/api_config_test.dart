import 'package:capybara/services/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiConfig.webBaseUrlFor', () {
    test('prefers explicit web api domain over same-origin', () {
      final actual = ApiConfig.webBaseUrlFor(
        Uri.parse('https://www.kapi-net.com/account'),
        explicitApiDomain: 'https://api.kapi-net.com',
      );

      expect(actual, 'https://api.kapi-net.com/api/app/v1');
    });

    test('falls back to same-origin when explicit domain is unset', () {
      final actual = ApiConfig.webBaseUrlFor(
        Uri.parse('https://www.kapi-net.com/account'),
        explicitApiDomain: '',
      );

      expect(actual, 'https://www.kapi-net.com/api/app/v1');
    });

    test('treats placeholder domain as unset', () {
      final actual = ApiConfig.webBaseUrlFor(
        Uri.parse('https://www.kapi-net.com/account'),
        explicitApiDomain: 'https://your-api-domain.com',
      );

      expect(actual, 'https://www.kapi-net.com/api/app/v1');
    });
  });
}

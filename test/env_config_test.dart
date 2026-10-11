import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/env_config.dart';

void main() {
  test('development API, socket and checkout share the reachable Mac host', () {
    expect(
      Uri.parse(AppConfig.apiUrl).host,
      AppConfig.developmentHost.toLowerCase(),
    );
    expect(Uri.parse(AppConfig.apiUrl).path, '/api/v1');
    expect(AppConfig.socketUrl, Uri.parse(AppConfig.apiUrl).origin);
    expect(
      Uri.parse(AppConfig.websiteUrl).host,
      AppConfig.developmentHost.toLowerCase(),
    );
    expect(Uri.parse(AppConfig.websiteUrl).port, 3000);
    expect(
      Uri.parse(AppConfig.paymentUrl(currency: 'gbp')).host,
      AppConfig.developmentHost.toLowerCase(),
    );
    expect(AppConfig.validate, returnsNormally);
  });
}

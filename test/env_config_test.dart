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

  // Pre-launch: release builds never send tokens over cleartext sockets.
  test('release builds require an HTTPS socket origin', () {
    expect(() => AppConfig.validateSocketUrl('http://api.twon.example', release: true), throwsStateError);
    expect(() => AppConfig.validateSocketUrl('ws://api.twon.example', release: true), throwsStateError);
    expect(() => AppConfig.validateSocketUrl('not a url', release: true), throwsStateError);
    expect(() => AppConfig.validateSocketUrl('https://api.twon.example', release: true), returnsNormally);
    expect(() => AppConfig.validateSocketUrl('http://10.0.2.2:5001', release: false), returnsNormally);
  });
}

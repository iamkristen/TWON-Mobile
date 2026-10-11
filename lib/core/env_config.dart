import 'package:flutter/foundation.dart';

class AppConfig {
  // Physical phones must reach the development computer, not their own localhost.
  // Override DEV_HOST when developing on another computer/network.
  static const developmentHost = String.fromEnvironment(
    'DEV_HOST',
    defaultValue: '192.168.0.184',
  );
  static const _definedApi = String.fromEnvironment('API_BASE_URL');
  static String get apiUrl => _definedApi.isNotEmpty
      ? _definedApi.replaceAll(RegExp(r'/+$'), '')
      : 'http://$developmentHost:5001/api/v1';
  static String get socketUrl =>
      const String.fromEnvironment('SOCKET_URL').isNotEmpty
      ? const String.fromEnvironment('SOCKET_URL')
      : Uri.parse(apiUrl).origin;
  static const _definedWebsite = String.fromEnvironment('WEBSITE_URL');
  static String get websiteUrl =>
      (_definedWebsite.isNotEmpty
              ? _definedWebsite
              : 'http://$developmentHost:3000')
          .replaceAll(RegExp(r'/+$'), '');
  static String paymentUrl({required String currency, String? orderId}) =>
      Uri.parse('$websiteUrl/merch/pay')
          .replace(queryParameters: {'currency': currency, 'order': ?orderId})
          .toString();
  static void validate() {
    final site = Uri.parse(websiteUrl);
    if (!site.hasAuthority ||
        !['http', 'https'].contains(site.scheme) ||
        (kReleaseMode && site.scheme != 'https')) {
      throw StateError(
        'WEBSITE_URL must be HTTP(S), and HTTPS in release builds.',
      );
    }
    final uri = Uri.parse(apiUrl);
    if (!uri.hasAuthority || !['http', 'https'].contains(uri.scheme)) {
      throw StateError('API_BASE_URL must be an HTTP(S) URL.');
    }
    if (kReleaseMode && (uri.scheme != 'https' || _definedApi.isEmpty)) {
      throw StateError(
        'Release builds require an explicit HTTPS API_BASE_URL.',
      );
    }
  }
}

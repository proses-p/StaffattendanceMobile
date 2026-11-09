import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://app.taarifa.wadudu.co.tz/api/v1',
  );

  static String get baseUrl => resolveBaseUrl(
    defaultTargetPlatform,
    configuredBaseUrl: _configuredBaseUrl,
  );

  static String resolveBaseUrl(
    TargetPlatform platform, {
    String configuredBaseUrl = '',
  }) {
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    return _configuredBaseUrl;
  }
}

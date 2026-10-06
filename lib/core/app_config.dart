import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// 서버 주소 설정. 실행 환경에 따라 Spring 주소가 달라진다.
class AppConfig {
  AppConfig._();

  static const int _springPort = 8088;
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _validate(_configuredBaseUrl, requireHttps: !kDebugMode);
    }
    // A distributable APK must never silently point at the installing
    // device. Production builds require an explicit HTTPS dart-define.
    if (!kDebugMode) {
      throw StateError(
        'Release builds require --dart-define=API_BASE_URL=https://api.example.com',
      );
    }
    // Android 에뮬레이터에서 호스트 PC 의 localhost 는 10.0.2.2
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:$_springPort';
    }
    return 'http://localhost:$_springPort';
  }

  static String _validate(String value, {required bool requireHttps}) {
    final normalized = value.replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('API_BASE_URL must be a complete http(s) URL.');
    }
    if (requireHttps && uri.scheme != 'https') {
      throw StateError('Release API_BASE_URL must use HTTPS.');
    }
    if (requireHttps &&
        const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host)) {
      throw StateError('Release API_BASE_URL must be an external API domain.');
    }
    return normalized;
  }
}

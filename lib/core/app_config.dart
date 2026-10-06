import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 서버 주소 설정. 실행 환경에 따라 Spring 주소가 달라진다.
class AppConfig {
  AppConfig._();

  static const int _springPort = 8088;
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.replaceFirst(RegExp(r'/$'), '');
    }
    // Android 에뮬레이터에서 호스트 PC 의 localhost 는 10.0.2.2
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:$_springPort';
    }
    return 'http://localhost:$_springPort';
  }
}

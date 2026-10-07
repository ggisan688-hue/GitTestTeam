import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show VoidCallback, debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../model/api_response.dart';
import 'app_config.dart';

/// 서버 응답이 success=false 이거나 통신 자체가 실패했을 때 던지는 예외
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.errorCode, this.requestId});

  final String message;
  final int? statusCode;
  final String? errorCode;

  /// Safe-to-share support identifier returned by the API. Never a token.
  final String? requestId;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// http 패키지를 감싼 얇은 클라이언트. Repository 들이 공통으로 사용한다.
/// [tokenProvider] 가 토큰을 돌려주면 Authorization 헤더를 붙인다.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, this.tokenProvider})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const _requestTimeout = Duration(seconds: 5);
  static final Random _requestIdRandom = Random.secure();

  /// The app installs this once to clear authenticated UI state when a token
  /// has expired. Repositories remain transport-only and do not need to know
  /// about widget/navigation state.
  static VoidCallback? onUnauthorized;

  String get baseUrl => _baseUrl;

  /// 서버가 준 상대 경로(/uploads/..)를 절대 URL 로
  String absolute(String path) =>
      path.startsWith('http') ? path : '$_baseUrl$path';
  String? Function()? tokenProvider;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (tokenProvider?.call() case final t?) 'Authorization': 'Bearer $t',
  };

  String _newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_requestIdRandom.nextInt(1 << 32).toRadixString(36)}';

  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? query,
    T Function(Object? json)? parse,
  }) => _send('GET', path, query: query, parse: parse);

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? body,
    T Function(Object? json)? parse,
  }) => _send('POST', path, body: body, parse: parse);

  Future<ApiResponse<T>> put<T>(
    String path, {
    Object? body,
    T Function(Object? json)? parse,
  }) => _send('PUT', path, body: body, parse: parse);

  Future<ApiResponse<T>> patch<T>(
    String path, {
    Object? body,
    T Function(Object? json)? parse,
  }) => _send('PATCH', path, body: body, parse: parse);

  Future<ApiResponse<T>> delete<T>(
    String path, {
    Map<String, String>? query,
    T Function(Object? json)? parse,
  }) => _send<T>('DELETE', path, query: query, parse: parse);

  /// multipart 파일 업로드 (필드명 file)
  Future<ApiResponse<T>> uploadFile<T>(
    String path, {
    String method = 'POST',
    Uint8List? bytes,
    String? filename,
    String? fieldName,
    String? contentType,
    Map<String, String> fields = const {},
    T Function(Object? json)? parse,
  }) async {
    final requestId = _newRequestId();
    final req = http.MultipartRequest(method, Uri.parse('$_baseUrl$path'));
    req.headers['X-Request-ID'] = requestId;
    if (tokenProvider?.call() case final t?)
      req.headers['Authorization'] = 'Bearer $t';
    req.fields.addAll(fields);
    if (bytes != null) {
      req.files.add(
        http.MultipartFile.fromBytes(
          fieldName!,
          bytes,
          filename: filename!,
          contentType: MediaType.parse(contentType!),
        ),
      );
    }
    try {
      final res = await http.Response.fromStream(
        await _client.send(req).timeout(_requestTimeout),
      );
      return _handle(res, parse, requestId);
    } on TimeoutException {
      throw ApiException(
        '서버 응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.',
        requestId: requestId,
      );
    } on http.ClientException catch (_) {
      throw ApiException(
        '서버에 연결할 수 없습니다. 네트워크 또는 서버 상태를 확인해주세요.',
        requestId: requestId,
      );
    }
  }

  Future<ApiResponse<T>> _send<T>(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    T Function(Object? json)? parse,
  }) async {
    final requestId = _newRequestId();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers.addAll(_headers)
      ..headers['X-Request-ID'] = requestId;
    if (body != null) req.body = jsonEncode(body);
    try {
      final res = await http.Response.fromStream(
        await _client.send(req).timeout(_requestTimeout),
      );
      if (kDebugMode && path.startsWith('/api/reading-rooms')) {
        // Never write invite codes, request/response bodies, or JWTs to
        // logcat. The request ID links this event to the server log.
        debugPrint(
          '[ReadingRoom API] requestId=${res.headers['x-request-id'] ?? requestId} '
          '$method $path -> HTTP ${res.statusCode} bytes=${res.contentLength}',
        );
      }
      if (kDebugMode && path.startsWith('/api/books')) {
        debugPrint('[Book API] $method $uri -> HTTP ${res.statusCode}');
      }
      return _handle(res, parse, requestId);
    } on TimeoutException {
      throw ApiException(
        '서버 응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.',
        requestId: requestId,
      );
    } on http.ClientException catch (e) {
      if (kDebugMode && path.startsWith('/api/reading-rooms')) {
        debugPrint(
          '[ReadingRoom API] requestId=$requestId $method $path failed: ${e.runtimeType}',
        );
      }
      if (kDebugMode && path.startsWith('/api/books')) {
        debugPrint('[Book API] $method $uri failed: ${e.message}');
      }
      throw ApiException(
        '서버에 연결할 수 없습니다. 네트워크 또는 서버 상태를 확인해주세요.',
        requestId: requestId,
      );
    }
  }

  // Diagnostic output intentionally excludes request headers (and therefore
  // JWTs).  Keep response logging bounded so an accidental large payload does
  // not flood an Android logcat session.
  // ignore: unused_element
  String _safeDebugBody(String body) =>
      body.length <= 1000 ? body : '${body.substring(0, 1000)}…';

  ApiResponse<T> _handle<T>(
    http.Response res,
    T Function(Object? json)? parse,
    String requestId,
  ) {
    final responseRequestId = res.headers['x-request-id'] ?? requestId;
    if (res.statusCode == 401) {
      onUnauthorized?.call();
    }
    // DELETE endpoints intentionally return 204.  Treating an empty response
    // as JSON made a successful note deletion look like a client-side error.
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) {
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse<T>(success: true, data: null);
      }
      throw ApiException(
        'Request failed.',
        statusCode: res.statusCode,
        requestId: responseRequestId,
      );
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw ApiException(
        '서버 응답을 해석할 수 없습니다',
        statusCode: res.statusCode,
        requestId: responseRequestId,
      );
    }
    if (json is! Map<String, dynamic> || !json.containsKey('success')) {
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          '요청에 실패했습니다.',
          statusCode: res.statusCode,
          requestId: responseRequestId,
        );
      }
      return ApiResponse<T>(
        success: true,
        data: parse == null ? json as T? : parse(json),
      );
    }
    final response = ApiResponse<T>.fromJson(json, parse);
    if (!response.success) {
      throw ApiException(
        response.message ?? '요청에 실패했습니다',
        statusCode: res.statusCode,
        errorCode: json['code'] as String?,
        requestId: (json['requestId'] as String?) ?? responseRequestId,
      );
    }
    return response;
  }
}

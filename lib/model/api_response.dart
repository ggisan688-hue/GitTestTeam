/// Spring 의 공통 응답 {success, message, data} 를 그대로 옮긴 모델
class ApiResponse<T> {
  const ApiResponse({required this.success, this.message, this.data});

  final bool success;
  final String? message;
  final T? data;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json)? parse,
  ) {
    final raw = json['data'];
    return ApiResponse<T>(
      success: json['success'] == true,
      message: json['message'] as String?,
      data: raw == null || parse == null ? raw as T? : parse(raw),
    );
  }
}

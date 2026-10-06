import 'dart:typed_data';

import '../core/api_client.dart';
import '../model/user_profile.dart';

class UserProfileRepository {
  UserProfileRepository(this._api);
  final ApiClient _api;
  Future<UserProfile> get() async => (await _api.get<UserProfile>(
    '/api/users/me',
    parse: (json) => UserProfile.fromJson(json as Map<String, dynamic>),
  )).data!;
  Future<UserProfile> update({
    required String nickname,
    String? bio,
    String? avatar,
  }) async => (await _api.patch<UserProfile>(
    '/api/users/me',
    body: {
      'nickname': nickname.trim(),
      'bio': bio?.trim(),
      if (avatar != null) 'avatar': avatar.trim(),
    },
    parse: (json) => UserProfile.fromJson(json as Map<String, dynamic>),
  )).data!;
  Future<UserProfile> updateWithImage({
    required String nickname,
    required String bio,
    Uint8List? imageBytes,
    String? filename,
    String? contentType,
    bool removeProfileImage = false,
  }) async {
    if (imageBytes == null) {
      return (await _api.patch<UserProfile>(
        '/api/users/me',
        body: {'nickname': nickname.trim(), 'bio': bio.trim()},
        parse: (json) => UserProfile.fromJson(json as Map<String, dynamic>),
      )).data!;
    }
    return (await _api.uploadFile<UserProfile>(
      '/api/users/me',
      method: 'PATCH',
      fieldName: 'profileImage',
      bytes: imageBytes,
      filename: filename ?? 'profile.jpg',
      contentType: contentType ?? 'image/jpeg',
      fields: {
        'nickname': nickname.trim(),
        'bio': bio.trim(),
        if (removeProfileImage) 'removeProfileImage': 'true',
      },
      parse: (json) => UserProfile.fromJson(json as Map<String, dynamic>),
    )).data!;
  }

  Future<UserProfile> removeImage({
    required String nickname,
    required String bio,
  }) async => (await _api.uploadFile<UserProfile>(
    '/api/users/me',
    method: 'PATCH',
    fields: {
      'nickname': nickname.trim(),
      'bio': bio.trim(),
      'removeProfileImage': 'true',
    },
    parse: (json) => UserProfile.fromJson(json as Map<String, dynamic>),
  )).data!;
  Future<void> delete(String confirmation) => _api.delete(
    '/api/users/me?confirmation=${Uri.encodeQueryComponent(confirmation)}',
  );
}

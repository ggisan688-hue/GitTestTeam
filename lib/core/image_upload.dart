import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';

/// 갤러리에서 사진을 고른다. 크기 조절 옵션 때문에 실패하는 기기가 있어,
/// 실패하면 옵션 없이 한 번 더 시도한다(줄이는 건 아래 [prepareImageForUpload]가 한다).
Future<XFile?> pickGalleryImage(
  ImagePicker picker, {
  ImageSource source = ImageSource.gallery,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
}) async {
  try {
    return await picker.pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
  } catch (_) {
    try {
      return await picker.pickImage(source: source);
    } catch (e) {
      throw ImageLoadFailure('선택', e);
    }
  }
}

/// 올릴 수 있는 사진으로 정리한 결과.
class PreparedImage {
  const PreparedImage(this.bytes, this.name, this.contentType);
  final Uint8List bytes;
  final String name;
  final String contentType;
}

/// 사진 형식을 확인하고, 4MB가 넘으면 5MB 안쪽으로 자동으로 줄인다.
/// 형식이 안 맞으면 [UnsupportedImageType], 줄이지 못하면 [ImageTooLarge] 를 던진다.
Future<PreparedImage> prepareImageForUpload(XFile file) async {
  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (e) {
    throw ImageLoadFailure('읽기', e);
  }
  var name = file.name;
  var ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) {
    // 이름에 확장자가 없어도 사진 종류(mime)로 알 수 있으면 받아 준다.
    final mime = (file.mimeType ?? '').toLowerCase();
    if (mime == 'image/png') {
      ext = 'png';
    } else if (mime == 'image/jpeg' || mime == 'image/jpg') {
      ext = 'jpg';
    } else if (mime == 'image/webp') {
      ext = 'webp';
    } else {
      throw const UnsupportedImageType();
    }
  }
  if (bytes.length > 4 * 1024 * 1024) {
    final small = await _shrink(bytes);
    if (small == null) throw const ImageTooLarge();
    bytes = small;
    ext = 'png';
    name = '${name.split('.').first}.png';
  }
  final type = ext == 'png'
      ? 'image/png'
      : ext == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
  return PreparedImage(bytes, name, type);
}

class ImageLoadFailure implements Exception {
  ImageLoadFailure(this.stage, this.cause);
  final String stage;
  final Object cause;
}

class UnsupportedImageType implements Exception {
  const UnsupportedImageType();
}

class ImageTooLarge implements Exception {
  const ImageTooLarge();
}

String imageErrorMessage(Object error) => error is UnsupportedImageType
    ? 'JPG, PNG, WEBP 형식의 사진을 선택해주세요.'
    : error is ImageTooLarge
        ? '사진이 너무 커서 줄이지 못했어요. 다른 사진을 선택해주세요.'
        : error is ImageLoadFailure
            ? '사진을 불러오지 못했습니다. [${error.stage}] ${_short(error.cause.toString())}'
            : '사진을 불러오지 못했습니다. [기타] ${_short(error.toString())}';

String _short(String text) =>
    text.length > 110 ? text.substring(0, 110) : text;

Future<Uint8List?> _shrink(Uint8List data) async {
  var width = 1280;
  for (var i = 0; i < 5; i++) {
    try {
      final codec = await ui.instantiateImageCodec(data, targetWidth: width);
      final frame = await codec.getNextFrame();
      final bd = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return null;
      final out = bd.buffer.asUint8List();
      if (out.length <= 4 * 1024 * 1024) return out;
    } catch (_) {
      return null;
    }
    width = (width * 0.7).round();
  }
  return null;
}

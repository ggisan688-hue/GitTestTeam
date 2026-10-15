import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePhotoSelection {
  const ProfilePhotoSelection({this.bytes, this.filename, this.contentType, this.remove = false});
  final Uint8List? bytes;
  final String? filename, contentType;
  final bool remove;
}

Future<void> showProfilePhotoDialog(BuildContext context, {
  required String name,
  String? imageUrl,
  ProfilePhotoSelection? initialSelection,
  String confirmLabel = '저장',
  required Future<void> Function(ProfilePhotoSelection selection) onSave,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ProfilePhotoDialog(name: name, imageUrl: imageUrl,
      initialSelection: initialSelection, confirmLabel: confirmLabel, onSave: onSave),
);

class _ProfilePhotoDialog extends StatefulWidget {
  const _ProfilePhotoDialog({required this.name, this.imageUrl, this.initialSelection,
    required this.confirmLabel, required this.onSave});
  final String name, confirmLabel;
  final String? imageUrl;
  final ProfilePhotoSelection? initialSelection;
  final Future<void> Function(ProfilePhotoSelection) onSave;
  @override
  State<_ProfilePhotoDialog> createState() => _ProfilePhotoDialogState();
}

class _ProfilePhotoDialogState extends State<_ProfilePhotoDialog> {
  late ProfilePhotoSelection _selection;
  bool _saving = false, _picking = false, _changed = false;
  String? _error;
  bool get _busy => _saving || _picking;
  bool get _hasPhoto => _selection.bytes != null ||
      (!_selection.remove && widget.imageUrl?.isNotEmpty == true);
  @override
  void initState() { super.initState(); _selection = widget.initialSelection ?? const ProfilePhotoSelection(); }
  Future<void> _pick() async {
    setState(() { _picking = true; _error = null; });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery,
          maxWidth: 1280, maxHeight: 1280, imageQuality: 85);
      if (file == null) return;
      final data = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext) || data.length > 5 * 1024 * 1024)
        throw Exception('invalid photo');
      if (!mounted) return;
      setState(() {
        _selection = ProfilePhotoSelection(bytes: data, filename: file.name,
            contentType: ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
        _changed = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'JPG, PNG, WEBP 형식의 5MB 이하 사진을 선택해주세요.');
    } finally { if (mounted) setState(() => _picking = false); }
  }
  Future<void> _save() async {
    if (_busy) return;
    if (!_changed) { Navigator.pop(context); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(_selection);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = '사진을 저장하지 못했어요. 다시 시도해주세요.'; });
    }
  }
  @override
  Widget build(BuildContext context) {
    final fallback = Text(widget.name.isEmpty ? '?' : widget.name.characters.take(2).toString(),
        style: const TextStyle(fontSize: 24, color: Color(0xFF555555)));
    return PopScope(canPop: !_busy, child: AlertDialog(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      title: const Text('프로필 사진 변경'),
      content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        CircleAvatar(radius: 44, backgroundColor: const Color(0xFFF2F3F7),
            child: !_hasPhoto ? fallback : ClipOval(child: _selection.bytes != null
                ? Image.memory(_selection.bytes!, width: 88, height: 88, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback)
                : Image.network(widget.imageUrl!, width: 88, height: 88, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback))),
        const SizedBox(height: 12),
        TextButton(onPressed: _busy ? null : _pick, child: Text(_picking ? '사진 선택 중' : '갤러리에서 선택')),
        if (_hasPhoto) TextButton(
            onPressed: _busy ? null : () => setState(() {
              _selection = const ProfilePhotoSelection(remove: true); _changed = true; _error = null;
            }),
            child: const Text('사진 삭제', style: TextStyle(color: Colors.red))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
      ],
      ))),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _busy ? null : _save,
            child: Text(_saving ? '저장 중' : widget.confirmLabel)),
      ],
    ));
  }
}

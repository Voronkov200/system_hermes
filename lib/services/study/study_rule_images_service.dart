// Локальные фотографии правил и страниц учебника.
//
// Пользователь сам выбирает изображения из галереи. Hermes копирует их в
// собственную папку приложения и никогда не отправляет в ИИ или сеть.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/file_tools.dart';

class StudyRuleImage {
  final String path;
  final String name;
  final DateTime modifiedAt;

  const StudyRuleImage({
    required this.path,
    required this.name,
    required this.modifiedAt,
  });
}

class StudyRuleImagesService {
  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  String _safeId(String paragraphId) {
    final clean =
        paragraphId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (clean.isEmpty) throw ArgumentError('Пустой id параграфа');
    return clean.substring(0, clean.length > 100 ? 100 : clean.length);
  }

  Future<Directory> _directory(String paragraphId) async {
    final root = await FileTools.root();
    return Directory('${root.path}/study_rule_images/${_safeId(paragraphId)}');
  }

  Future<List<StudyRuleImage>> list(String paragraphId) async {
    final directory = await _directory(paragraphId);
    if (!await directory.exists()) return const [];
    final result = <StudyRuleImage>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final extension = entity.path.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains(extension)) continue;
      try {
        final stat = await entity.stat();
        result.add(
          StudyRuleImage(
            path: entity.path,
            name: entity.uri.pathSegments.last,
            modifiedAt: stat.modified,
          ),
        );
      } catch (_) {}
    }
    result.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
    return result;
  }

  /// Возвращает количество реально сохранённых фотографий.
  Future<int> addFromGallery(String paragraphId) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Фото правил или страниц',
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return 0;

    final directory = await _directory(paragraphId);
    await directory.create(recursive: true);
    var saved = 0;
    for (var index = 0; index < picked.files.length; index++) {
      final selected = picked.files[index];
      final extension = _extensionOf(selected);
      if (!_allowedExtensions.contains(extension)) continue;
      final target = File(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$index.$extension',
      );
      final sourcePath = selected.path;
      if (sourcePath != null && await File(sourcePath).exists()) {
        await File(sourcePath).copy(target.path);
        saved++;
        continue;
      }
      final Uint8List? bytes = selected.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      await target.writeAsBytes(bytes, flush: true);
      saved++;
    }
    return saved;
  }

  Future<void> remove(String paragraphId, StudyRuleImage image) async {
    final directory = await _directory(paragraphId);
    final expectedParent = directory.absolute.path;
    final file = File(image.path).absolute;
    if (file.parent.path != expectedParent) {
      throw ArgumentError('Фотография находится вне папки параграфа');
    }
    if (await file.exists()) await file.delete();
  }

  Future<void> removeAll(String paragraphId) async {
    final directory = await _directory(paragraphId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  String _extensionOf(PlatformFile file) {
    final direct = file.extension?.toLowerCase().trim();
    if (direct != null && _allowedExtensions.contains(direct)) return direct;
    final nameParts = file.name.toLowerCase().split('.');
    return nameParts.length > 1 ? nameParts.last : 'jpg';
  }
}

final studyRuleImagesServiceProvider = Provider<StudyRuleImagesService>(
  (ref) => StudyRuleImagesService(),
);

final studyRuleImagesProvider = FutureProvider.autoDispose
    .family<List<StudyRuleImage>, String>((ref, paragraphId) {
  return ref.read(studyRuleImagesServiceProvider).list(paragraphId);
});

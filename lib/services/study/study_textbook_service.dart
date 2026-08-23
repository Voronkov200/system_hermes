// Автоматическая загрузка и локальный кэш официальных PDF-учебников.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../agent/file_tools.dart';
import 'study_textbook_catalog.dart';

class StudyTextbookDownloadException implements Exception {
  final String message;

  const StudyTextbookDownloadException(this.message);

  @override
  String toString() => message;
}

class StudyTextbookService {
  final http.Client _client;
  final Map<String, Future<File>> _inFlight = {};

  StudyTextbookService([http.Client? client]) : _client = client ?? http.Client();

  Future<File> ensureLocal(String bookId) {
    final active = _inFlight[bookId];
    if (active != null) return active;
    final future = _ensureLocal(bookId);
    _inFlight[bookId] = future;
    return future.whenComplete(() => _inFlight.remove(bookId));
  }

  Future<File> _ensureLocal(String bookId) async {
    final source = StudyTextbookCatalog.sources[bookId];
    if (source == null) {
      throw const StudyTextbookDownloadException(
        'Для этого разбора пока не найден официальный PDF-источник.',
      );
    }

    final root = await FileTools.root();
    final directory = Directory('${root.path}/study_textbooks');
    await directory.create(recursive: true);
    final target = File('${directory.path}/$bookId.pdf');
    if (await _isValidPdf(target)) return target;

    final partial = File('${target.path}.part');
    try {
      if (await partial.exists()) await partial.delete();
      final request = http.Request('GET', source.pdfUri)
        ..headers['User-Agent'] = 'SystemHermes/1.0 (Android; textbook cache)'
        ..headers['Accept'] = 'application/pdf,*/*;q=0.8';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 35));
      if (response.statusCode != HttpStatus.ok) {
        throw StudyTextbookDownloadException(
          'Учебник не загрузился: сервер вернул ${response.statusCode}.',
        );
      }
      const maxBytes = 250 * 1024 * 1024;
      final declared = response.contentLength;
      if (declared != null && declared > maxBytes) {
        throw const StudyTextbookDownloadException(
          'PDF слишком большой для безопасной загрузки.',
        );
      }

      var received = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 45))) {
          received += chunk.length;
          if (received > maxBytes) {
            throw const StudyTextbookDownloadException(
              'PDF превысил допустимый размер.',
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (!await _isValidPdf(partial)) {
        throw const StudyTextbookDownloadException(
          'Сервер вернул не PDF. Попробуй ещё раз позже.',
        );
      }
      if (await target.exists()) await target.delete();
      return await partial.rename(target.path);
    } on StudyTextbookDownloadException {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } on SocketException {
      if (await partial.exists()) await partial.delete();
      throw const StudyTextbookDownloadException(
        'Нет соединения. Один раз открой параграф с интернетом — затем весь учебник останется на телефоне.',
      );
    } on TimeoutException {
      if (await partial.exists()) await partial.delete();
      throw const StudyTextbookDownloadException(
        'Загрузка учебника прервалась по тайм-ауту. Нажми «Повторить».',
      );
    } catch (error) {
      if (await partial.exists()) await partial.delete();
      throw StudyTextbookDownloadException('Не удалось сохранить учебник: $error');
    }
  }

  Future<bool> _isValidPdf(File file) async {
    try {
      if (!await file.exists() || await file.length() < 1024) return false;
      final handle = await file.open();
      try {
        final header = await handle.read(5);
        return header.length == 5 && String.fromCharCodes(header) == '%PDF-';
      } finally {
        await handle.close();
      }
    } catch (_) {
      return false;
    }
  }

  void dispose() => _client.close();
}

final studyTextbookServiceProvider = Provider<StudyTextbookService>((ref) {
  final service = StudyTextbookService();
  ref.onDispose(service.dispose);
  return service;
});

final studyTextbookFileProvider = FutureProvider.autoDispose
    .family<File, String>((ref, bookId) {
  return ref.read(studyTextbookServiceProvider).ensureLocal(bookId);
});

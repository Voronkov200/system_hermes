// Автоматическая загрузка и локальный кэш официальных PDF-учебников.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../agent/file_tools.dart';
import 'study_textbook_catalog.dart';

class StudyTextbookDownloadException implements Exception {
  final String message;
  final bool retryable;

  const StudyTextbookDownloadException(
    this.message, {
    this.retryable = false,
  });

  @override
  String toString() => message;
}

class StudyTextbookService {
  static const _maxAttempts = 3;
  static const _maxBytes = 250 * 1024 * 1024;

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
    Object? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        if (await partial.exists()) await partial.delete();
        return await _downloadOnce(source, target, partial);
      } on StudyTextbookDownloadException catch (error) {
        lastError = error;
        if (!error.retryable || attempt == _maxAttempts - 1) rethrow;
      } on SocketException catch (error) {
        lastError = error;
        if (attempt == _maxAttempts - 1) {
          throw const StudyTextbookDownloadException(
            'Нет соединения. Hermes автоматически повторит загрузку, когда сеть станет стабильнее.',
            retryable: true,
          );
        }
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == _maxAttempts - 1) {
          throw const StudyTextbookDownloadException(
            'Загрузка учебника несколько раз прервалась по тайм-ауту. Hermes попробует снова позже.',
            retryable: true,
          );
        }
      } catch (error) {
        lastError = error;
        throw StudyTextbookDownloadException(
          'Не удалось сохранить учебник: $error',
        );
      } finally {
        if (await partial.exists() && !await _isValidPdf(partial)) {
          try {
            await partial.delete();
          } catch (_) {
            // Следующая попытка всё равно попробует очистить временный файл.
          }
        }
      }

      await Future<void>.delayed(
        Duration(milliseconds: 600 * (attempt + 1)),
      );
    }

    throw StudyTextbookDownloadException(
      'Не удалось загрузить учебник: $lastError',
      retryable: true,
    );
  }

  Future<File> _downloadOnce(
    StudyTextbookSource source,
    File target,
    File partial,
  ) async {
    final request = http.Request('GET', source.pdfUri)
      ..headers['User-Agent'] = 'SystemHermes/1.0 (Android; textbook cache)'
      ..headers['Accept'] = 'application/pdf,*/*;q=0.8';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 35));

    if (response.statusCode != HttpStatus.ok) {
      final retryable = response.statusCode == HttpStatus.requestTimeout ||
          response.statusCode == 429 ||
          response.statusCode >= 500;
      await response.stream.drain<void>();
      throw StudyTextbookDownloadException(
        'Учебник не загрузился: сервер вернул ${response.statusCode}.',
        retryable: retryable,
      );
    }

    final declared = response.contentLength;
    if (declared != null && declared > _maxBytes) {
      await response.stream.drain<void>();
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
        if (received > _maxBytes) {
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
        'Сервер вернул не PDF. Hermes попробует загрузить учебник ещё раз.',
        retryable: true,
      );
    }
    if (await target.exists()) await target.delete();
    return partial.rename(target.path);
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

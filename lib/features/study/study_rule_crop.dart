// Снимок «таблички» (правило/теорема/формула) из официальной страницы учебника,
// приложенный прямо к разделу конспекта.
//
// Виджет никак не влияет на поведение конспекта: если локализовать фрагмент на
// странице не удалось, он тихо не рисует ничего. Работает поверх
// StudyTextbookTableCropService (детерминированная эвристика по текстовому слою
// PDF, без ИИ, целиком на телефоне).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/study/study_textbook_table_crop_service.dart';

/// Один снимок таблички. [text] — фрагмент правила/теоремы, который ищем в
/// текстовом слое страницы, [pdfPages] — страницы параграфа (PDF-нумерация),
/// [bookId] — идентификатор официального учебника.
class StudyRuleCrop extends ConsumerWidget {
  final String bookId;
  final List<int> pdfPages;
  final String text;

  const StudyRuleCrop({
    super.key,
    required this.bookId,
    required this.pdfPages,
    required this.text,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crop = ref.watch(studyTextbookCropProvider((
      bookId: bookId,
      pdfPages: pdfPages,
      text: text,
    )));

    return crop.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (file) {
        if (file == null) return const SizedBox.shrink();
        return _CropCard(file: file);
      },
    );
  }
}

class _CropCard extends StatelessWidget {
  final File file;

  const _CropCard({required this.file});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _CropViewer(file: file)),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(file, width: double.infinity, fit: BoxFit.contain),
      ),
    );
  }
}

/// Полноэкранный просмотр вырезанной таблички.
class _CropViewer extends StatelessWidget {
  final File file;

  const _CropViewer({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

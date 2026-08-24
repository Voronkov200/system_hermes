import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Просмотр очень длинных фото ГДЗ.
///
/// Старый вариант вписывал всё изображение целиком в экран, из-за чего
/// многостраничное решение превращалось в узкую нечитаемую полоску. Здесь
/// масштаб 1.0 означает «ширина изображения = ширина экрана», а длинная часть
/// остаётся за пределами viewport и доступна обычным вертикальным панорамированием.
class GdzPhotoView extends StatelessWidget {
  final File file;

  const GdzPhotoView({
    super.key,
    required this.file,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AppColors.surfaceAlt,
          child: const Row(
            children: [
              Icon(Icons.zoom_in, size: 17, color: AppColors.textDim),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'По ширине экрана · веди вверх/вниз · двумя пальцами увеличивай',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              return ColoredBox(
                color: Colors.black,
                child: ClipRect(
                  child: InteractiveViewer(
                    key: ValueKey(file.path),
                    constrained: false,
                    alignment: Alignment.topCenter,
                    minScale: 1,
                    maxScale: 6,
                    panAxis: PanAxis.free,
                    boundaryMargin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 80,
                    ),
                    child: SizedBox(
                      width: viewportWidth,
                      child: Image.file(
                        file,
                        width: viewportWidth,
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 320,
                          height: 240,
                          child: Center(
                            child: Text(
                              'Фото повреждено',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

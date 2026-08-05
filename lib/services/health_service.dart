// Health Connect: получение данных о шагах (верификация тренировок).
//
// Работает опционально: если Health Connect недоступен на устройстве,
// возвращает null (не ломает приложение).

import 'package:flutter_health_connect/flutter_health_connect.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HealthService {
  /// Количество шагов за сегодня (null если недоступно/нет прав).
  Future<int?> getStepsToday() async {
    try {
      if (!await HealthConnectFactory.isApiSupported()) return null;
      final hasPermission = await HealthConnectFactory.hasPermissions(
        [HealthConnectDataType.Steps],
        readOnly: true,
      );
      if (!hasPermission) return null;

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final results = await HealthConnectFactory.getRecord(
        type: HealthConnectDataType.Steps,
        startTime: start,
        endTime: now,
      );

      // results: Map<имя типа, List<Map<String, dynamic>>>
      int total = 0;
      final raw = results['Steps'];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            final count = item['count'];
            if (count is num) total += count.toInt();
          }
        }
      } else if (raw is Map) {
        final count = raw['count'];
        if (count is num) total += count.toInt();
      }
      return total;
    } catch (_) {
      return null;
    }
  }
}

final healthServiceProvider = Provider((ref) => HealthService());

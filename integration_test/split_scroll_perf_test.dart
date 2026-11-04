// Плавность прокрутки на настоящем окне: одна панель и две с синхронной прокруткой, вниз и вверх по тексту.
// Время кадров (построение и отрисовка), длинные кадры, сколько кадров ведомая панель показывает другой стих
// Запуск: flutter test integration_test/split_scroll_perf_test.dart -d windows
import 'dart:ui';

import 'package:aobible/core/panes.dart';
import 'package:aobible/main.dart' as app;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('прокрутка: вниз и вверх, одна и две панели', (tester) async {
    await app.main();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // приложение помнит панели с прошлого раза: для замера одной панели — закрыть вторую
    final close2 = find.byTooltip('Закрыть вторую панель');
    if (close2.evaluate().isNotEmpty) {
      await tester.tap(close2.first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final out = <String>[];

    Future<void> measure(String label, Offset at, double step, {bool split = false}) async {
      final timings = <FrameTiming>[];
      void cb(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(cb);
      var frames = 0, differ = 0;
      for (var k = 0; k < 4; k++) {
        final g = await tester.startGesture(at);
        for (var i = 0; i < 45; i++) {
          await g.moveBy(Offset(0, step));
          await tester.pump(const Duration(milliseconds: 16));
          if (split) {
            frames++;
            final a = livePositions[0]?.value, b = livePositions[1]?.value;
            if (a != null && b != null && (a.chapter != b.chapter || a.verse != b.verse)) differ++;
          }
        }
        await g.up();
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      await tester.pump(const Duration(milliseconds: 500));
      SchedulerBinding.instance.removeTimingsCallback(cb);
      double ms(Duration d) => d.inMicroseconds / 1000;
      final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
      final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
      double p(List<double> l, double q) => l.isEmpty ? 0 : l[((l.length - 1) * q).round()];
      final long = timings.where((t) => ms(t.buildDuration) + ms(t.rasterDuration) > 16.7).length;
      out.add('$label: кадров ${timings.length}, длинных (>16,7 мс) $long; построение сред ${p(build, 0.5).toStringAsFixed(1)} / 90% ${p(build, 0.9).toStringAsFixed(1)} / 99% ${p(build, 0.99).toStringAsFixed(1)} / макс ${p(build, 1).toStringAsFixed(1)}; '
          'отрисовка 90% ${p(raster, 0.9).toStringAsFixed(1)} / макс ${p(raster, 1).toStringAsFixed(1)}'
          '${split ? '; ведомая на другом стихе: $differ из $frames кадров' : ''}');
    }

    // одна панель: сначала вниз по тексту (палец вверх), потом вверх (палец вниз)
    final one = Offset(size.width / 2, size.height * 0.5);
    await measure('одна панель, ВНИЗ по тексту', one, -12);
    await measure('одна панель, ВВЕРХ по тексту', one, 12);

    final splitBtn = find.byTooltip('Читать параллельно');
    if (splitBtn.evaluate().isNotEmpty) {
      await tester.tap(splitBtn.first);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    final top = Offset(size.width / 2, size.height * 0.30), bottom = Offset(size.width / 2, size.height * 0.70);
    await measure('две, тяну ВЕРХНЮЮ вниз по тексту', top, -12, split: true);
    await measure('две, тяну ВЕРХНЮЮ вверх по тексту', top, 12, split: true);
    await measure('две, тяну НИЖНЮЮ вниз по тексту', bottom, -12, split: true);
    await measure('две, тяну НИЖНЮЮ вверх по тексту', bottom, 12, split: true);
    for (final l in out) {
      // ignore: avoid_print
      print('PERF $l');
    }
  });
}

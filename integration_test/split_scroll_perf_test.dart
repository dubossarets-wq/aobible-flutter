// Плавность синхронной прокрутки двух панелей на настоящем окне: тянем верхнюю, потом нижнюю и сравниваем время
// кадров (построение и отрисовка). Запуск: flutter test integration_test/split_scroll_perf_test.dart -d windows --profile
import 'dart:ui';

import 'package:aobible/main.dart' as app;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('две панели: кадры при прокрутке верхней и нижней', (tester) async {
    await app.main();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final split = find.byTooltip('Читать параллельно');
    if (split.evaluate().isNotEmpty) {
      await tester.tap(split.first);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    Future<String> measure(String label, Offset at) async {
      final timings = <FrameTiming>[];
      void cb(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(cb);
      for (var k = 0; k < 3; k++) {
        final g = await tester.startGesture(at);
        for (var i = 0; i < 40; i++) {
          await g.moveBy(const Offset(0, -12));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      await tester.pump(const Duration(milliseconds: 500));
      SchedulerBinding.instance.removeTimingsCallback(cb);
      double ms(Duration d) => d.inMicroseconds / 1000;
      final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
      final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
      double p(List<double> l, double q) => l.isEmpty ? 0 : l[((l.length - 1) * q).round()];
      return '$label: кадров ${timings.length}, построение сред ${p(build, 0.5).toStringAsFixed(1)} / 90% ${p(build, 0.9).toStringAsFixed(1)} / макс ${p(build, 1).toStringAsFixed(1)} мс; '
          'отрисовка сред ${p(raster, 0.5).toStringAsFixed(1)} / 90% ${p(raster, 0.9).toStringAsFixed(1)} / макс ${p(raster, 1).toStringAsFixed(1)} мс';
    }

    final top = await measure('тяну ВЕРХНЮЮ', Offset(size.width / 2, size.height * 0.30));
    final bottom = await measure('тяну НИЖНЮЮ', Offset(size.width / 2, size.height * 0.70));
    // ignore: avoid_print
    print('PERF $top');
    // ignore: avoid_print
    print('PERF $bottom');
  });
}

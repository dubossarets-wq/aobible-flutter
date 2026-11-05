// Снимки окна приложения со стилем iPhone (для проверки вида на компьютере): читалка, «Ещё», «Оформление».
// Снимается только окно приложения (слой Flutter), не экран. Настройка iosStyle потом возвращается как была.
// Запуск: flutter test integration_test/ios_style_shots_test.dart -d windows --dart-define=SHOTS=<папка>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aobible/core/settings.dart';
import 'package:aobible/main.dart' as app;
import 'package:aobible/ui/reader_pane.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const dir = String.fromEnvironment('SHOTS', defaultValue: 'build/shots');

  testWidgets('стиль iPhone: снимки', (tester) async {
    await app.main();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final c = ProviderScope.containerOf(tester.element(find.byType(ReaderPane).first));
    final was = c.read(settingsProvider).get<bool>('iosStyle');
    Future<void> wait([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> shot(String name) async {
      final rv = tester.binding.renderViews.first;
      final layer = rv.debugLayer! as OffsetLayer;
      final size = rv.size;
      final img = await layer.toImage(Offset.zero & size, pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    try {
      for (final dark in [false, true]) {
        c.read(settingsProvider.notifier).set({'iosStyle': true});
        systemDark.value = dark;
        await wait();
        final tag = dark ? 'dark' : 'light';
        await shot('1-reader-$tag');
        await tester.tap(find.text('Ещё').last);
        await wait(10);
        await shot('2-more-$tag');
        for (final (i, name) in [(3, 'Оформление'), (4, 'Настройки')]) {
          final row = find.text(name);
          if (row.evaluate().isEmpty) continue;
          await tester.ensureVisible(row.first);
          await wait(4);
          await tester.tap(row.first, warnIfMissed: false);
          await wait(10);
          await shot('$i-$name-$tag');
          await tester.tap(find.text('Ещё').last, warnIfMissed: false);
          await wait(10);
        }
        // закрыть окна
        await tester.tap(find.text('Библия').last);
        await wait(10);
      }
    } finally {
      c.read(settingsProvider.notifier).set({'iosStyle': was});
      systemDark.value = false;
      await wait(4);
    }
  });
}

// Снимки окна приложения со стилем iPhone (для проверки вида на компьютере): читалка и основные окна.
// Снимается только окно приложения (слой Flutter), не экран. Настройка iosStyle потом возвращается как была.
// Запуск: flutter test integration_test/ios_style_shots_test.dart -d windows --dart-define=SHOTS=<папка> [--dart-define=DARK=1]
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
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
  const dark = bool.fromEnvironment('DARK');

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
      final img = await layer.toImage(Offset.zero & rv.size, pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    Future<void> closeAll() async {
      FocusManager.instance.primaryFocus?.unfocus();
      Hub.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      await wait(8);
    }

    Future<void> step(String name, Future<void> Function() open) async {
      try {
        await open();
        await wait(10);
        await shot(name);
      } catch (e) {
        // ignore: avoid_print
        print('SHOT $name: $e');
      }
      await closeAll();
    }

    try {
      c.read(settingsProvider.notifier).set({'iosStyle': true});
      systemDark.value = dark;
      await wait();
      await shot('01-reader');
      await step('02-search', () => tester.tap(find.text('Поиск').last));
      await step('03-plans', () => tester.tap(find.text('Планы').last));
      await step('04-saved', () => tester.tap(find.text('Закладки').last));
      await step('05-more', () => tester.tap(find.text('Ещё').last));
      Future<void> fromMore(String row) async {
        await tester.tap(find.text('Ещё').last);
        await wait(10);
        final f = find.text(row);
        await tester.ensureVisible(f.first);
        await wait(4);
        await tester.tap(f.first, warnIfMissed: false);
      }

      await step('06-settings', () => fromMore('Настройки'));
      await step('07-appearance', () => fromMore('Оформление'));
      await step('08-library', () => fromMore('Библиотека модулей'));
      // капсула первой панели: слева — перевод, справа — место
      await step('09-goto', () => tester.tapAt(const Offset(130, 22)));
      await step('10-module', () => tester.tapAt(const Offset(42, 22)));
    } finally {
      c.read(settingsProvider.notifier).set({'iosStyle': was});
      systemDark.value = false;
      await wait(4);
    }
  });
}

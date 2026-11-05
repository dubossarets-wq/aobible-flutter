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
    // окно как у iPhone 16 Pro: 402×874 pt
    tester.view.physicalSize = const Size(402 * 2, 874 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await app.main();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final c = ProviderScope.containerOf(tester.element(find.byType(ReaderPane).first));
    final was = c.read(settingsProvider).get<bool>('iosStyle');
    final theme = c.read(settingsProvider).get<String>('theme');
    Future<void> wait([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> shot(String name) async {
      final rv = tester.binding.renderViews.first;
      final layer = rv.debugLayer! as OffsetLayer;
      // слой окна — в физических пикселях (402×874 pt × 2)
      final img = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
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
      c.read(settingsProvider.notifier).set({'iosStyle': true, if (dark) 'theme': 'dark'});
      systemDark.value = dark;
      await wait();
      await shot('01-reader');
      await step('02-search', () => tester.tap(find.text('Поиск').last));
      await step('02b-search-nokb', () async {
        await tester.tap(find.text('Поиск').last);
        await wait(10);
        FocusManager.instance.primaryFocus?.unfocus();
      });
      await step('03-plans', () => tester.tap(find.text('Планы').last));
      await step('04-saved', () => tester.tap(find.text('Закладки').last));
      await step('05-more', () => tester.tap(find.text('Ещё').last));
      // крупный заголовок: на полпути и уже в шапке; полоса края прокрутки
      for (final (n, dy) in [('05b-more-half', -50.0), ('05b-more-half2', -66.0), ('05c-more-up', -260.0)]) {
        await step(n, () async {
          await tester.tap(find.text('Ещё').last);
          await wait(10);
          await tester.drag(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last, Offset(0, dy));
        });
      }
      Future<void> fromMore(String row) async {
        await tester.tap(find.text('Ещё').last);
        await wait(10);
        final f = find.text(row);
        await tester.scrollUntilVisible(f.first, 200, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last);
        await wait(4);
        await tester.tap(f.first, warnIfMissed: false);
      }

      await step('06-settings', () => fromMore('Настройки'));
      await step('07-appearance', () => fromMore('Оформление'));
      await step('06b-settings-up', () async {
        await fromMore('Настройки');
        await wait(10);
        await tester.drag(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last, const Offset(0, -300));
      });
      await step('07b-appearance-low', () async {
        await fromMore('Оформление');
        await wait(10);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
      });
      Future<void> sub(String page, String row) async {
        await fromMore(page);
        await wait(10);
        final f = find.text(row);
        await tester.scrollUntilVisible(f.first, 200, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last);
        await wait(4);
        await tester.tap(f.first, warnIfMissed: false);
      }

      Future<void> low(Future<void> Function() open) async {
        await open();
        await wait(10);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
      }

      await step('06b-settings-low', () => low(() => fromMore('Настройки')));
      for (final (i, r) in ['Шрифт', 'Номера и заголовки', 'Фон', 'Цвета', 'Кнопки и панели', 'Комментарии'].indexed) {
        await step('07-${'cdefgh'[i]}-$r', () => sub('Оформление', r));
      }
      await step('05b-more-low', () => low(() => tester.tap(find.text('Ещё').last)));
      await step('11-about', () => fromMore('О приложении'));
      await step('19-help', () => fromMore('Инструкция'));
      await step('12-whatsnew', () => fromMore('Что нового'));
      await step('13-bookmarks', () => fromMore('Закладки и заметки'));
      await step('14-sermons', () => fromMore('Проповеди'));
      await step('14b-sermons-swipe', () async {
        await fromMore('Проповеди');
        await wait(10);
        await tester.drag(find.textContaining('изменена').first, const Offset(-140, 0));
      });
      await step('15-plans', () => fromMore('Планы чтения'));
      await step('16-maps', () => fromMore('Карты'));
      await step('17-report', () => fromMore('Сообщить о проблеме'));
      // выделение стиха: нажатие на текст первой панели
      await step('18-selection', () => tester.tapAt(const Offset(200, 260)));
      await step('20-dictionary', () async {
        await tester.tapAt(const Offset(200, 260));
        await wait(8);
        await tester.tap(find.textContaining('Стронг').first, warnIfMissed: false);
      });
      await step('21-commentary', () => tester.tap(find.text('Лопухин').first, warnIfMissed: false));
      await step('08-library', () => fromMore('Библиотека модулей'));
      // капсула первой панели: слева — перевод, справа — место
      await step('09-goto', () => tester.tapAt(const Offset(130, 22)));
      await step('10-module', () => tester.tapAt(const Offset(42, 22)));
    } finally {
      c.read(settingsProvider.notifier).set({'iosStyle': was, 'theme': theme});
      systemDark.value = false;
      await wait(4);
    }
  });
}

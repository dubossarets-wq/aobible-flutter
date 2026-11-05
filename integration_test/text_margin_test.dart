// Поля текста по бокам (Оформление → «Поля по бокам»): текст сдвигается от края панели
// Запуск: flutter test integration_test/text_margin_test.dart -d windows
import 'package:aobible/core/settings.dart';
import 'package:aobible/main.dart' as app;
import 'package:aobible/ui/reader_pane.dart';
import 'package:aobible/ui/verse_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('поля по бокам меняют отступ текста', (tester) async {
    await app.main();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final c = ProviderScope.containerOf(tester.element(find.byType(ReaderPane).first));
    final was = c.read(settingsProvider).j['textMargin'];
    double left() {
      final pane = tester.getTopLeft(find.byType(ReaderPane).first).dx;
      return tester.getTopLeft(find.byType(VerseView).first).dx - pane;
    }

    try {
      final before = left();
      for (final m in [40.0, 4.0]) {
        c.read(settingsProvider.notifier).set({'textMargin': m});
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        // ignore: avoid_print
        print('MARGIN было ${before.toStringAsFixed(1)} → при $m: ${left().toStringAsFixed(1)}');
      }
    } finally {
      c.read(settingsProvider.notifier).set({'textMargin': was ?? -1.0});
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }
  });
}

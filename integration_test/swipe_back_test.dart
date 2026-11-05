// Стиль iPhone: страница окна закрывается свайпом вправо с середины экрана (не только от края)
// Запуск: flutter test integration_test/swipe_back_test.dart -d windows
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/main.dart' as app;
import 'package:aobible/ui/kit.dart';
import 'package:aobible/ui/reader_pane.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('свайп назад с середины', (tester) async {
    await app.main();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final c = ProviderScope.containerOf(tester.element(find.byType(ReaderPane).first));
    final was = c.read(settingsProvider).get<bool>('iosStyle');
    Future<void> wait([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    try {
      c.read(settingsProvider.notifier).set({'iosStyle': true});
      await wait();
      await tester.tap(find.text('Ещё').last);
      await wait(10);
      final top = topRoute(Hub.navigatorKey.currentContext!);
      expect(top, isA<IosPageRoute>(), reason: 'окно «Ещё» — страница iOS');
      // короткий свайп (меньше половины, медленно) — страница возвращается
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final mid = Offset(size.width / 2, size.height / 2);
      var g = await tester.startGesture(mid);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await wait(10);
      expect(topRoute(Hub.navigatorKey.currentContext!), same(top), reason: 'короткий свайп — остаётся');
      // длинный свайп с середины — закрывается
      g = await tester.startGesture(mid);
      for (var i = 0; i < 20; i++) {
        await g.moveBy(Offset(size.width / 30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await wait(12);
      expect(topRoute(Hub.navigatorKey.currentContext!), isNot(isA<IosPageRoute>()), reason: 'длинный свайп — закрылась');
    } finally {
      Hub.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      c.read(settingsProvider.notifier).set({'iosStyle': was});
      await wait(4);
    }
  });
}

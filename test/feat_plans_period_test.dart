// «Свой план» → «Параллельно» → «Глав в день» / «За срок»: переключатели, скрытие шагов, выбор дней, запуск, запоминание.
// Экран 400×830; любое исключение Flutter (переполнение, setState после dispose) роняет тест. Сети нет: список планов — в подложенном кэше.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/plans/plan_logic.dart';
import 'package:aobible/features/plans/plan_store.dart';
import 'package:aobible/features/plans/plans_sheet.dart';
import 'package:aobible/features/plans/ui_kit.dart' show showPage;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

class V {
  const V(this.name, this.theme, this.scale);
  final String name, theme;
  final double scale;
}

const variants = [V('светлая', 'light', 1.0), V('тёмная', 'dark', 1.0), V('светлая ×1.3', 'light', 1.3)];

late Directory root;
late ProviderContainer c;
bool realFont = false;

/// Тестовый шрифт по умолчанию (Ahem) вдвое шире настоящего — на нём «переполнения» ложные. Берём Roboto из SDK.
Future<void> loadRoboto() async {
  var d = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++, d = d.parent) {
    final dir = Directory('${d.path}/artifacts/material_fonts');
    if (!dir.existsSync()) continue;
    final loader = FontLoader('Roboto');
    for (final f in ['regular', 'medium', 'bold']) {
      final file = File('${dir.path}/roboto-$f.ttf');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
    realFont = true;
    return;
  }
}

void makeBible(Directory dir) {
  final db = sqlite3.open('${dir.path}/rst-plus.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('''
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  const shape = {'Gen': (6, 5), 'Ps': (6, 4), 'Matt': (6, 5), 'John': (3, 20)};
  var id = 0;
  shape.forEach((b, s) {
    for (var ch = 1; ch <= s.$1; ch++) {
      for (var v = 1; v <= s.$2; v++) {
        final text = 'Слово $b $ch:$v и любовь';
        id++;
        db.execute('INSERT INTO verses VALUES (?, ?, ?, ?, ?)', [id, b, ch, v, text]);
        db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?, ?)', [id, text]);
      }
    }
  });
  db.execute('CREATE INDEX verses_ref ON verses(book, chapter, verse)');
  final books = [for (final b in shape.keys) {'id': b, 'name': b, 'short': b, 'chapters': shape[b]!.$1}];
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': 'rst-plus', 'type': 'bible', 'name': 'РСТ+', 'title': 'Тест', 'language': 'ru', 'bookList': books})]);
  db.close();
}

Future<void> real(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
}

Future<void> spin(WidgetTester tester, [int ms = 700]) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Длинные списки ленивые: если элемента ещё нет, прокручиваем окно вниз, пока он не построится
Future<void> reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isNotEmpty) return;
  final sc = find.byType(Scrollable);
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await tester.drag(sc.first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapText(WidgetTester tester, String text, {bool last = false, bool first = false}) async {
  var f = find.text(text);
  await reveal(tester, f);
  expect(f, findsWidgets, reason: 'нет «$text»');
  if (last) f = f.last;
  if (first) f = f.first;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await spin(tester, 300);
}

Future<void> tapTip(WidgetTester tester, String tip, {bool first = false, bool last = false}) async {
  var f = find.byTooltip(tip);
  await reveal(tester, f);
  expect(f, findsWidgets, reason: 'нет подсказки «$tip»');
  if (first) f = f.first;
  if (last) f = f.last;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await spin(tester, 300);
}

Future<void> boot(WidgetTester tester, V v) async {
  tester.view.physicalSize = const Size(400, 830);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(settingsProvider.notifier).set({'theme': v.theme});
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: ThemeData(brightness: v.theme == 'dark' ? Brightness.dark : Brightness.light, fontFamily: realFont ? 'Roboto' : null),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.scale)), child: child!),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(child: GestureDetector(onTap: () => showPage(ctx, (_) => const PlansSheet(pane: 0)), child: const Text('открыть'))),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('открыть'));
  await spin(tester, 300);
  await real(tester);
  await spin(tester, 600);
  expect(tester.takeException(), isNull);
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await spin(tester, 200);
  expect(tester.takeException(), isNull);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    root = Directory('${Directory.systemTemp.path}/aob_period_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final mods = Directory('${root.path}/modules')..createSync();
    makeBible(mods);
    final cache = Directory('${root.path}/site_cache')..createSync();
    File('${cache.path}/plans_index.json').writeAsStringSync(jsonEncode({'plans': []}));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => root.path);
    await loadRoboto();
    await Books.load();
    await ModuleStore.initAt(mods);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await setLang('ru');
  });

  Future<void> open(WidgetTester tester, V v) async {
    await tester.runAsync(() async => fetchPlanIndex());
    await boot(tester, v);
  }

  for (final v in variants) {
    testWidgets('«За срок» [${v.name}]: переключатели, шаги скрыты, дни как в «Последовательно», запуск', (tester) async {
      await open(tester, v);
      expect(find.text('Последовательно'), findsOneWidget);
      expect(find.text('Подряд'), findsNothing);
      await tapText(tester, 'Параллельно');
      expect(find.text('Глав в день'), findsOneWidget);
      expect(find.text('За срок'), findsOneWidget);
      expect(find.text('Разделы и глав в день'), findsOneWidget);
      expect(find.text('1 гл. в день'), findsWidgets);
      expect(find.text('За сколько дней'), findsNothing);
      // «За срок»: шаги разделов скрыты, галочки остались, появился выбор дней
      await tapText(tester, 'За срок');
      expect(find.text('1 гл. в день'), findsNothing);
      expect(find.text('Разделы'), findsOneWidget);
      expect(find.text('Ветхий Завет'), findsWidgets);
      await reveal(tester, find.text('За сколько дней'));
      expect(find.text('За сколько дней'), findsOneWidget);
      for (final n in [7, 14, 30, 90, 180, 365]) {
        expect(find.text('$n дн.'), findsOneWidget, reason: 'пресет $n');
      }
      expect(find.text('Начать на 90 дн.'), findsOneWidget);
      await tapText(tester, '14 дн.');
      expect(find.text('Начать на 14 дн.'), findsOneWidget);
      for (var i = 0; i < 9; i++) {
        await tapTip(tester, 'Уменьшить', last: true);
      }
      expect(find.text('Начать на 7 дн.'), findsOneWidget); // не меньше 7
      await tester.enterText(find.byType(TextField).last, '20');
      await spin(tester, 100);
      expect(find.text('Начать на 20 дн.'), findsOneWidget);
      // запомнилось
      expect(prefs.getString('customPlanParMode'), '"period"');
      // «Глав в день» возвращает шаги
      await tapText(tester, 'Глав в день');
      expect(find.text('1 гл. в день'), findsWidgets);
      expect(prefs.getString('customPlanParMode'), '"perday"');
      await tapText(tester, 'За срок');
      await reveal(tester, find.text('Начать на 20 дн.'));
      expect(find.text('Начать на 20 дн.'), findsOneWidget); // срок сохранился
      await tapText(tester, 'Начать на 20 дн.');
      await spin(tester, 400);
      final plans = c.read(plansProvider);
      expect(plans.length, 1);
      final days = readingsOf(plans.first);
      expect(days.length, lessThanOrEqualTo(20));
      expect(days.length, greaterThan(10));
      expect('${plans.first['name']}', 'ВЗ + НЗ + Псалтирь за ${days.length} дн.');
      final all = [for (final d in days) ...d];
      expect(all.toSet().length, all.length);
      expect(all, containsAll(['Gen.6', 'John.3', 'Ps.6'])); // все разделы дочитаны
      await finish(tester);
    });

    testWidgets('«За срок» [${v.name}]: выбор и срок восстанавливаются при следующем открытии', (tester) async {
      prefs.setString('customPlanMode', jsonEncode('par'));
      prefs.setString('customPlanParMode', jsonEncode('period'));
      prefs.setString('customPlanParDays', jsonEncode(30));
      await open(tester, v);
      await reveal(tester, find.text('Начать на 30 дн.'));
      expect(find.text('Начать на 30 дн.'), findsOneWidget);
      expect(find.text('1 гл. в день'), findsNothing);
      await finish(tester);
    });
  }
}

// «Мощная проверка» планов, проповедей и аудио: каждый экран открывается на поверхности 400×830 в светлой и тёмной теме
// и при textScale 1.3, основные действия проходятся нажатиями, как у человека. Любое исключение Flutter (переполнение,
// setState после dispose, ошибка построения) роняет тест. Сети нет: данные сайта лежат в подложенной папке кэша,
// воспроизведения нет: состояние движка задаётся напрямую.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/audio/audio_bar.dart';
import 'package:aobible/features/audio/audio_engine.dart';
import 'package:aobible/features/audio/audio_fab.dart';
import 'package:aobible/features/audio/audio_settings.dart';
import 'package:aobible/features/plans/plan_logic.dart';
import 'package:aobible/features/plans/plan_store.dart';
import 'package:aobible/features/plans/plans_sheet.dart';
import 'package:aobible/features/plans/ui_kit.dart' show LucideIcons, showPage;
import 'package:aobible/features/plans/verse_list.dart';
import 'package:aobible/features/sermons/sermon_add.dart';
import 'package:aobible/features/sermons/sermon_store.dart';
import 'package:aobible/features/sermons/sermons_sheet.dart';
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

late ProviderContainer c;

// --- Небольшой тестовый перевод «rst-plus» (так же устроен SQLite у ModuleStore) ------------------------------

void makeBible(Directory dir) {
  final db = sqlite3.open('${dir.path}/rst-plus.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('''
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  const shape = {'Gen': (3, 5), 'Ps': (6, 4), 'Prov': (4, 4), 'Isa': (4, 5), 'Matt': (3, 5), 'John': (3, 20), 'Acts': (3, 5)};
  final seen = <String>{};
  var id = 0;
  void add(String b, int c, int v) {
    if (!seen.add('$b.$c.$v')) return;
    final text = b == 'John' && c == 3 && v == 16 ? 'Ибо так возлюбил Бог мир' : 'Слово $b $c:$v и любовь';
    id++;
    db.execute('INSERT INTO verses VALUES (?, ?, ?, ?, ?)', [id, b, c, v, text]);
    db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?, ?)', [id, text]);
  }

  shape.forEach((b, s) {
    for (var c = 1; c <= s.$1; c++) {
      for (var v = 1; v <= s.$2; v++) {
        add(b, c, v);
      }
    }
  });
  // стих дня на сегодня обязан быть в модуле, иначе карточка не показывается
  final k = verseOfDayKey().split('.');
  add(k[0], int.parse(k[1]), int.parse(k[2]));
  db.execute('CREATE INDEX verses_ref ON verses(book, chapter, verse)');
  final books = [for (final b in shape.keys) {'id': b, 'name': b, 'short': b, 'chapters': shape[b]!.$1}];
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': 'rst-plus', 'type': 'bible', 'name': 'РСТ+', 'title': 'Тест', 'language': 'ru', 'bookList': books})]);
  db.close();
}

// --- Окружение ---------------------------------------------------------------------------------------------

/// Будущие значения, созданные вне «поддельных» часов (кэш сайта), доходят до окна только через настоящий цикл событий
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

Future<void> toTop(WidgetTester tester) async {
  // мгновенно к началу списка: рывок пальцем дальше верха закрыл бы окно (потянуть вниз — закрыть)
  final st = tester.state<ScrollableState>(find.byType(Scrollable).first);
  st.position.jumpTo(st.position.minScrollExtent);
  await spin(tester, 300);
}

/// Окно закрылось (анимация закрытия идёт ~0,2 с)
Future<void> gone(WidgetTester tester, String text) async {
  await spin(tester, 600);
  expect(find.text(text), findsNothing, reason: 'окно «$text» не закрылось');
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

/// Экран 400×830, тема и масштаб текста; кнопка «открыть» вызывает [open]
Future<void> boot(WidgetTester tester, V v, void Function(BuildContext, WidgetRef) open, {Widget? extra}) async {
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
      home: Consumer(
        builder: (ctx, ref, _) => Scaffold(
          body: Stack(children: [
            Center(child: GestureDetector(onTap: () => open(ctx, ref), child: const Text('открыть'))),
            ?extra,
          ]),
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

Map<String, dynamic> plan({String start = '2026-01-01', int days = 6, String name = 'Тестовый план', String uid = 'p1'}) => {
      'uid': uid,
      'planId': 'x',
      'name': name,
      'calendar': false,
      'start': start,
      'readings': [
        for (var i = 0; i < days; i++) i == 1 ? ['Gen.1', 'John.3'] : ['Gen.${i % 3 + 1}'],
      ],
      'done': <String, dynamic>{},
    };


/// Число дней в капсуле «− | 90 | +» (последнее видимое поле)
String daysValue(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField).last).controller!.text;

/// Кнопка «Начать» своего плана — последняя (у готового плана своя «Начать» выше)
Future<void> tapStart(WidgetTester tester) async {
  final f = find.text('Начать').last;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    root = Directory('${Directory.systemTemp.path}/aob_qa_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final mods = Directory('${root.path}/modules')..createSync();
    makeBible(mods);
    // path_provider: кэш сайта — наша папка; в нём лежат список планов и сам план (сети в тестах нет)
    final cache = Directory('${root.path}/site_cache')..createSync();
    File('${cache.path}/plans_index.json').writeAsStringSync(jsonEncode({
      'plans': [
        {'id': 'nt-90', 'name': 'Новый Завет за 90 дней', 'file': 'nt-90.json', 'days': 90, 'short': 'НЗ', 'description': 'Читаем Новый Завет.'},
        {'id': 'gospels-30', 'name': 'Евангелия за 30 дней', 'file': 'gospels-30.json', 'days': 30},
      ],
    }));
    File('${cache.path}/plans_nt-90.json').writeAsStringSync(jsonEncode({
      'id': 'nt-90',
      'name': 'Новый Завет за 90 дней',
      'readings': [for (var i = 0; i < 9; i++) ['Matt.${i % 3 + 1}']],
    }));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => root.path);
    // «Поделиться» без системного окна
    binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'), (call) async => 'dev.fluttercommunity.plus/share/unavailable');
    await loadRoboto();
    await Books.load();
    await ModuleStore.initAt(mods);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await setLang('ru');
    AudioEngine.I.state.value = const AudioState();
  });

  tearDown(() async {
    await AudioEngine.I.stop();
    AudioEngine.I.state.value = const AudioState();
  });

  Future<void> warmSite(WidgetTester tester) async {
    await tester.runAsync(() async {
      await fetchPlanIndex();
      await fetchPlan('nt-90.json');
    });
  }

  // ===== ПЛАНЫ ================================================================================================

  Future<void> openPlans(WidgetTester tester, V v) async {
    await warmSite(tester);
    await boot(tester, v, (ctx, ref) => showPage(ctx, (_) => const PlansSheet(pane: 0)));
  }

  for (final v in variants) {
    testWidgets('планы [${v.name}]: стих дня, готовые планы, «Читать» ведёт к стиху', (tester) async {
      await openPlans(tester, v);
      expect(find.text('Планы чтения'), findsOneWidget);
      expect(find.text('Стих дня'), findsOneWidget);
      expect(find.text('Картинка'), findsOneWidget);
      expect(find.text('Выберите план'), findsOneWidget);
      await reveal(tester, find.text('Новый Завет за 90 дней'));
      expect(find.text('Новый Завет за 90 дней'), findsOneWidget);
      expect(find.text('Евангелия за 30 дней'), findsOneWidget);
      // назад к стиху дня — прокруткой ровно до него: рывок дальше верха закрывает окно (потянуть вниз — закрыть)
      await tester.scrollUntilVisible(find.text('Стих дня'), -300, scrollable: find.byType(Scrollable).first);
      await spin(tester, 200);
      await tapText(tester, 'Читать'); // «Читать» стиха дня
      expect(c.read(panesProvider).first.ref, isNot(startRef)); // сменили место
      await gone(tester, 'Планы чтения'); // окно закрылось
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: картинка со стихом — форматы, размер, «как было»', (tester) async {
      await openPlans(tester, v);
      await tapText(tester, 'Картинка');
      expect(find.text('Картинка со стихом'), findsOneWidget);
      await tapText(tester, 'Квадрат');
      await tapText(tester, 'История');
      await tapText(tester, 'Пост');
      await tapTip(tester, 'Крупнее');
      await tapTip(tester, 'Крупнее');
      expect(find.text('как было'), findsOneWidget);
      await tapTip(tester, 'Мельче');
      await tapText(tester, 'как было');
      expect(find.text('как было'), findsNothing);
      // двигаем текст пальцем по превью
      final paint = find.byType(CustomPaint).evaluate().where((e) => e.size != null && e.size!.width > 200 && e.size!.height > 150).firstOrNull;
      if (paint != null) {
        await tester.drag(find.byElementPredicate((e) => e == paint), const Offset(30, 20));
        await spin(tester, 200);
      }
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: начать готовый план, день, отметки, удаление с подтверждением', (tester) async {
      await openPlans(tester, v);
      await tapText(tester, 'Новый Завет за 90 дней');
      expect(find.text('Читаем Новый Завет.'), findsOneWidget);
      await tapText(tester, 'Начать', first: true); // у готового плана; ниже — «Начать» своего плана
      await real(tester);
      await spin(tester, 400);
      expect(c.read(plansProvider).length, 1);
      expect(c.read(plansProvider).first['readings'], isNotEmpty);
      await toTop(tester);
      expect(find.textContaining('День 1'), findsOneWidget);
      expect(find.textContaining('0 из 9 дн.'), findsOneWidget);
      // отметить день, снять отметку
      await tapText(tester, 'Отметить');
      expect(find.textContaining('1 из 9 дн.'), findsOneWidget);
      expect(find.text('прочитано'), findsOneWidget);
      await tapText(tester, 'Прочитано');
      expect(find.textContaining('0 из 9 дн.'), findsOneWidget);
      // листаем дни
      await tapTip(tester, 'Следующий день');
      expect(find.textContaining('День 2'), findsOneWidget);
      await tapTip(tester, 'Предыдущий день');
      expect(find.textContaining('День 1'), findsOneWidget);
      // удаление: сначала «корзина», потом «Удалить»; без второго нажатия само отменяется
      await tapTip(tester, 'Удалить план');
      expect(find.text('Удалить'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Удалить'), findsNothing);
      expect(c.read(plansProvider).length, 1);
      await tapTip(tester, 'Удалить план');
      await tapText(tester, 'Удалить');
      expect(c.read(plansProvider), isEmpty);
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: отрывков больше пяти — «Ещё N»; кружок отмечает отрывок, все отмечены — день закрыт', (tester) async {
      final handle = tester.ensureSemantics();
      final gen = Books.instance.meta('Gen').name;
      prefs.setString('plans', jsonEncode([
        {...plan(start: localDate(DateTime.now())), 'readings': [for (var d = 0; d < 3; d++) [for (var k = 1; k <= 7; k++) 'Gen.$k']]},
      ]));
      await openPlans(tester, v);
      await reveal(tester, find.text('$gen 1'));
      expect(find.text('$gen 5'), findsOneWidget);
      expect(find.text('$gen 6'), findsNothing, reason: 'шестой — за «Ещё»');
      await tapText(tester, 'Ещё 2');
      expect(find.text('$gen 7'), findsOneWidget);
      // кружок: отметить и снять
      Future<void> mark(String label) async {
        final f = find.bySemanticsLabel(label);
        // по центру видимой области: у верха строка ушла бы под шапку окна
        await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
        await spin(tester, 100);
        await tester.tap(f);
        await spin(tester, 300);
      }

      await mark('Отметить прочитанным: $gen 2');
      expect(find.textContaining('1 из 7 отрывков'), findsOneWidget);
      await mark('Снять отметку: $gen 2');
      expect(find.textContaining('0 из 7 отрывков'), findsOneWidget);
      for (var k = 1; k <= 7; k++) {
        await mark('Отметить прочитанным: $gen $k');
      }
      expect(c.read(plansProvider).first['done'], contains('0'), reason: 'все отрывки отмечены — день закрыт');
      // снял один в закрытом дне — день открыт, остальные шесть остались
      await mark('Снять отметку: $gen 4');
      expect(c.read(plansProvider).first['done'], isNot(contains('0')));
      expect(find.textContaining('6 из 7 отрывков'), findsOneWidget);
      handle.dispose();
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: пропущенные дни и переход к первому пропущенному, чтение отрывка', (tester) async {
      final start = localDate(DateTime.now().subtract(const Duration(days: 3)));
      prefs.setString('plans', jsonEncode([plan(start: start)]));
      await openPlans(tester, v);
      expect(find.text('Пропущено дней: 3'), findsOneWidget);
      expect(find.textContaining('День 4'), findsOneWidget);
      expect(find.textContaining('сегодня'), findsWidgets);
      await tapText(tester, 'Догнать'); // к первому пропущенному
      expect(find.textContaining('День 1'), findsOneWidget);
      await tapText(tester, 'Отметить');
      expect(find.text('Пропущено дней: 2'), findsOneWidget);
      // отрывки второго дня: «Читать» → продолжить → «Перечитать»
      await tapTip(tester, 'Следующий день');
      expect(find.textContaining('0 из 2 отрывков'), findsOneWidget);
      await tapText(tester, 'Читать', last: true); // первая «Читать» — у стиха дня
      // перешли к первому отрывку дня и окно закрылось
      expect(c.read(panesProvider).first.ref.book, 'Gen');
      await gone(tester, 'Планы чтения');
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: «Свой план» подряд — раздел, дни, шаги «− +», пресеты, свои книги', (tester) async {
      await openPlans(tester, v);
      await reveal(tester, find.text('За сколько дней'));
      expect(daysValue(tester), '90');
      await tapText(tester, 'Неделя');
      expect(daysValue(tester), '7');
      await tapTip(tester, 'Увеличить');
      expect(daysValue(tester), '8');
      await tapTip(tester, 'Уменьшить');
      await tapTip(tester, 'Уменьшить'); // 6 → не меньше 7
      expect(daysValue(tester), '7');
      await tester.enterText(find.byType(TextField).last, '14');
      await spin(tester, 100);
      expect(daysValue(tester), '14');
      // свои книги: пока ничего не выбрано — кнопка выключена
      await tapText(tester, 'Свои книги');
      final isa = Books.instance.meta('Isa'), acts = Books.instance.meta('Acts');
      await tapTip(tester, isa.name);
      await tapTip(tester, acts.name);
      expect(find.text('Выбрано книг: 2'), findsOneWidget);
      await tapStart(tester);
      await spin(tester, 400);
      final plans = c.read(plansProvider);
      expect(plans.length, 1);
      expect('${plans.first['name']}', contains('${isa.name}, ${acts.name}'));
      expect(readingsOf(plans.first).length, lessThanOrEqualTo(14));
      // настройки запомнились
      expect(jsonDecode(prefs.getString('customPlanBooks')!), ['Isa', 'Acts']);
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: «Свой план» параллельно — разделы, «− +», запуск', (tester) async {
      await openPlans(tester, v);
      await tapText(tester, 'Параллельно');
      expect(find.text('Разделы и глав в день'), findsOneWidget);
      for (final s in ['Ветхий Завет', 'Новый Завет', 'Псалтирь', 'Притчи', 'Евангелия']) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      // ВЗ и НЗ включены; добавим Псалтирь и поднимем число глав
      await tapText(tester, 'Псалтирь', last: true);
      await tapTip(tester, 'Увеличить', first: true);
      expect(find.text('2 гл. в день'), findsOneWidget);
      await tapTip(tester, 'Уменьшить', first: true);
      expect(find.text('1 гл. в день'), findsWidgets);
      // «Свои книги» без книг — кнопка «Выберите книги»
      await tapText(tester, 'Свои книги', last: true);
      expect(find.text('Выбрано книг: 0'), findsNothing);
      await tapTip(tester, Books.instance.meta('Isa').name);
      await tapText(tester, 'Свои книги', last: true); // выключить раздел
      expect(find.text('Начать'), findsWidgets);
      await tapStart(tester);
      await spin(tester, 400);
      expect(c.read(plansProvider).length, 1);
      expect('${c.read(plansProvider).first['name']}', contains('параллельно'));
      expect(prefs.getString('customPlanMode'), '"par"');
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: повреждённый план без дней не роняет окно и удаляется', (tester) async {
      prefs.setString('plans', jsonEncode([plan(days: 0, name: 'Пустой план')]));
      await openPlans(tester, v);
      expect(find.text('Пустой план'), findsOneWidget);
      await tapTip(tester, 'Удалить план');
      await tapText(tester, 'Удалить');
      expect(c.read(plansProvider), isEmpty);
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: «Сколько прочитано» — недавние главы открывают место', (tester) async {
      logChapter('Gen', 1);
      logChapter('Gen', 2);
      logChapter('John', 3);
      logChapter('Acts', 1);
      await openPlans(tester, v);
      await tapText(tester, 'ещё…');
      expect(find.text('ещё…'), findsNothing);
      await tapText(tester, '${Books.instance.meta('Gen').short.replaceFirst(RegExp(r'\.$'), '')} 2', first: true);
      await gone(tester, 'Планы чтения');
      expect(c.read(panesProvider).first.ref.book, 'Gen');
      expect(c.read(panesProvider).first.ref.chapter, 2);
      await finish(tester);
    });
  }

  // ===== ПРОПОВЕДИ ============================================================================================

  Future<void> openSermons(WidgetTester tester, V v, {String? open}) =>
      boot(tester, v, (ctx, ref) => showPage(ctx, (_) => SermonsSheet(pane: 0, open: open), page: true));

  for (final v in variants) {
    testWidgets('проповеди [${v.name}]: пустой список, создание, текстовый блок, ввод', (tester) async {
      await openSermons(tester, v);
      expect(find.text('Проповедей пока нет'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Благодать');
      await tapText(tester, 'Создать');
      expect(c.read(sermonsProvider).single['title'], 'Благодать');
      expect(find.text('Проповедь'), findsOneWidget);
      expect(find.textContaining('Как добавить стих'), findsOneWidget);
      // пустая проповедь: кнопки внизу
      await tapText(tester, 'Текст', last: true);
      final id = '${c.read(sermonsProvider).single['id']}';
      expect(blocksOf(c.read(sermonsProvider).single).length, 1);
      await tester.enterText(find.widgetWithText(TextField, '').last, 'Бог любит нас');
      await spin(tester, 100);
      expect(blocksOf(c.read(sermonsProvider).single).first['text'], 'Бог любит нас');
      // название правится
      await tester.enterText(find.byType(TextField).first, 'Новое имя');
      await spin(tester, 100);
      expect(c.read(sermonsProvider.notifier).byId(id)!['title'], 'Новое имя');
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: переводы у стиха, пустой текст исчезает, таймер «Кафедры»', (tester) async {
      final id = c0Create();
      await openSermons(tester, v, open: id);
      final n = c.read(sermonsProvider.notifier);
      n.addVerses(id, [VerseItem('John', 3, 16, 'Ибо так возлюбил Бог мир')], 'rst-plus');
      await spin(tester, 300);
      // «Переводы» раскрывают выбор; «к новым стихам» — только когда подключён второй перевод
      await tapTip(tester, 'Переводы');
      expect(find.text('Подключать к новым стихам'), findsNothing);
      // переводы, выбранные заранее, подключаются к новым стихам сами
      n.setAltDefault(id, [{'m': 'kjv-test', 'n': 'KJV'}]);
      n.addVerses(id, [VerseItem('John', 3, 17, 'Ибо не послал Бог')], 'rst-plus');
      await spin(tester, 300);
      final blocks = blocksOf(c.read(sermonsProvider).single);
      expect(blocks.length, 2);
      expect(altsOf(blocks.last).single['m'], 'kjv-test');
      expect(sermonText(c.read(sermonsProvider).single), contains('3:16'));
      // пустой свой текст исчезает сам, когда из него ушли
      await tapText(tester, 'Текст', last: true);
      expect(blocksOf(c.read(sermonsProvider).single).length, 3);
      FocusManager.instance.primaryFocus?.unfocus();
      await spin(tester, 300);
      expect(blocksOf(c.read(sermonsProvider).single).length, 2);
      // «Кафедра»: таймер идёт, нажатие — пауза
      await tapText(tester, 'Кафедра');
      await spin(tester, 1200);
      expect(find.textContaining(RegExp(r'^\d+:\d\d$')), findsOneWidget); // секундомер идёт по настоящим часам
      await tapTip(tester, 'Пауза');
      expect(find.byTooltip('Продолжить'), findsOneWidget);
      await tapTip(tester, 'Закрыть кафедру');
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: добавить стих по ссылке и по слову, «Кафедра», размер', (tester) async {
      final id = c0Create();
      await openSermons(tester, v, open: id);
      await tapText(tester, 'Стих', last: true);
      expect(find.text('Добавить стих'), findsOneWidget);
      // ссылка добавляет все стихи сразу и возвращает к проповеди
      await tester.enterText(find.byType(TextField).first, 'Ин 3:16-18');
      await spin(tester, 100);
      await tapText(tester, find.textContaining('Добавить в проповедь:').evaluate().map((e) => (e.widget as Text).data!).first);
      expect(find.text('Проповедь'), findsOneWidget);
      var blocks = blocksOf(c.read(sermonsProvider).single);
      expect((blocks.single['verse'], blocks.single['to']), (16, 18));
      // между блоками — «+ Стих»: поиск по слову
      await tapText(tester, 'Стих', first: true);
      await tester.enterText(find.byType(TextField).first, 'возлюбил');
      await spin(tester, 500); // запрос уходит после паузы ввода, поиск идёт в отдельном потоке
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await spin(tester, 500);
      expect(find.textContaining('Ин'), findsWidgets);
      await tester.tap(find.textContaining('Ибо так').first);
      await spin(tester, 300);
      blocks = blocksOf(c.read(sermonsProvider).single);
      expect(blocks.length, 2); // 3:16 уже есть, но слово-поиск добавляет отдельным блоком
      await tapTip(tester, 'Назад');
      // Кафедра
      await tapText(tester, 'Кафедра');
      expect(find.text('Аминь'), findsOneWidget);
      await tapTip(tester, 'Крупнее');
      await tapTip(tester, 'Крупнее');
      expect(prefs.getString('pulpitSize'), '30');
      await tapTip(tester, 'Мельче');
      expect(prefs.getString('pulpitSize'), '28');
      // щипок двумя пальцами
      final g1 = await tester.startGesture(const Offset(150, 400), pointer: 1);
      final g2 = await tester.startGesture(const Offset(250, 400), pointer: 2);
      await g1.moveBy(const Offset(-40, 0));
      await g2.moveBy(const Offset(40, 0));
      await g1.up();
      await g2.up();
      await spin(tester, 200);
      await tapTip(tester, 'Закрыть кафедру');
      expect(find.text('Аминь'), findsNothing);
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: перестановка блоков, убрать стих с «Отменить», удалить блок и проповедь', (tester) async {
      final id = c0Create();
      await openSermons(tester, v, open: id);
      final n = c.read(sermonsProvider.notifier);
      n.addVerses(id, [for (final x in [16, 17, 18]) VerseItem('John', 3, x, 'текст $x')], 'rst-plus');
      final t1 = n.addTextBlock(id);
      n.updateBlock(id, t1, {'text': 'Мысль про любовь'});
      await spin(tester, 300);
      expect(find.text('Мысль про любовь'), findsOneWidget);
      // перетаскивание: зажать блок «Мысль…» и потянуть вверх
      final from = tester.getCenter(find.text('Мысль про любовь'));
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, -25));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await g.up();
      await spin(tester, 500);
      expect(blocksOf(c.read(sermonsProvider).single).first['type'], 'text');
      // убрать средний стих диапазона: «Убрано», «Отменить» возвращает
      await tapTip(tester, 'Убрать стих', first: true);
      await tapText(tester, 'Убрать');
      expect(blocksOf(c.read(sermonsProvider).single).last['verse'], 17); // осталось 17–18
      await spin(tester, 1000);
      await tapText(tester, 'Отменить');
      expect(blocksOf(c.read(sermonsProvider).single).last['verse'], 16); // вернули 16–18
      // удалить текстовый блок
      await tapTip(tester, 'Удалить текст', first: true);
      await tapText(tester, 'Удалить', first: true);
      expect(blocksOf(c.read(sermonsProvider).single).length, 1);
      // удалить проповедь целиком
      await tapText(tester, 'Удалить проповедь', last: true);
      await tapText(tester, 'Удалить проповедь?');
      expect(c.read(sermonsProvider), isEmpty);
      expect(find.text('Проповедей пока нет'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: список — смахивание и «Отменить»; поделиться', (tester) async {
      final a = c0Create(title: 'Первая');
      c0Create(title: 'Вторая');
      await openSermons(tester, v);
      expect(find.text('Первая'), findsOneWidget);
      expect(find.textContaining('0 мест'), findsWidgets);
      await tester.drag(find.text('Первая'), const Offset(-400, 0));
      await spin(tester, 1500);
      expect(c.read(sermonsProvider).length, 1);
      expect(find.textContaining('удалена'), findsOneWidget);
      await tapText(tester, 'Отменить');
      expect(c.read(sermonsProvider).length, 2);
      // открыть проповедь, «Поделиться» и вернуться «Назад»
      c.read(sermonsProvider.notifier).addTextBlock(a);
      await tapText(tester, 'Первая');
      expect(find.text('Проповедь'), findsOneWidget);
      await tapTip(tester, 'Поделиться'); // значком в шапке
      await tapTip(tester, 'Назад');
      expect(find.text('Проповеди'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: «Добавить в проповедь» — новая и существующая', (tester) async {
      await boot(tester, v, (ctx, ref) => showPage(ctx, (_) => const SermonAddSheet(pane: 0, refs: [VerseRef('John', 3, 16)], moduleId: 'rst-plus'), height: 0.7));
      expect(find.text('Добавить в проповедь'), findsOneWidget);
      expect(find.text('Назовите проповедь'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Любовь');
      await tapText(tester, 'Создать');
      expect(find.text('Добавлено'), findsOneWidget);
      var s = c.read(sermonsProvider).single;
      expect(blocksOf(s).single['text'], 'Ибо так возлюбил Бог мир');
      await tapText(tester, 'Открыть проповедь');
      expect(find.text('Проповедь'), findsOneWidget);
      expect(find.text('Любовь'), findsWidgets);
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: «Добавить в проповедь» — выбрать из списка, «Читать дальше»', (tester) async {
      c0Create(title: 'Старая');
      await boot(tester, v, (ctx, ref) => showPage(ctx, (_) => const SermonAddSheet(pane: 0, refs: [VerseRef('John', 3, 16), VerseRef('John', 3, 17)], moduleId: 'rst-plus'), height: 0.7));
      expect(find.text('Или выберите проповедь'), findsOneWidget);
      await tapText(tester, 'Старая');
      expect(find.text('Добавлено'), findsOneWidget);
      expect(blocksOf(c.read(sermonsProvider).single).single['to'], 17);
      await tapText(tester, 'Читать дальше');
      await gone(tester, 'Добавлено');
      await finish(tester);
    });
  }

  // ===== АУДИО ================================================================================================

  AudioState playing({VerseRef at = const VerseRef('Gen', 1, 2), bool on = true}) =>
      AudioState(active: true, playing: on, pane: 0, moduleId: 'rst-plus', ref: at, source: 'aud1', rate: 1, volume: 1);

  for (final v in variants) {
    testWidgets('аудио [${v.name}]: кнопка «Слушать» без записи — сообщение в мини-проигрывателе', (tester) async {
      await boot(tester, v, (ctx, ref) {}, extra: const Positioned(right: 14, bottom: 90, child: ListenFab(pane: 0)));
      expect(find.byTooltip('Слушать с Gen 1:1'), findsNothing); // подпись по книгам перевода
      final fab = find.byType(ListenFab);
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await spin(tester, 400);
      expect(AudioEngine.I.s.active, true);
      expect(AudioEngine.I.s.error, 'Для этой главы нет аудиозаписи.');
      expect(find.byType(ListenFab), findsOneWidget); // кнопка прячется сама (active)
      await finish(tester);
    });

    testWidgets('аудио [${v.name}]: мини-проигрыватель — пауза, скорость, таймер сна, закрыть', (tester) async {
      await boot(tester, v, (ctx, ref) {}, extra: const Positioned(left: 0, right: 0, bottom: 0, child: AudioBar()));
      expect(find.byType(AudioBar), findsOneWidget);
      AudioEngine.I.state.value = playing();
      await spin(tester, 200);
      expect(find.text(Books.instance.formatRef('Gen', 1, 2)), findsWidgets);
      expect(find.bySemanticsLabel('Пауза'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Пауза'));
      await spin(tester, 200);
      expect(AudioEngine.I.s.playing, false);
      // настройки: скорость и таймер сна
      await tester.tap(find.bySemanticsLabel('Настройки чтения вслух'));
      await spin(tester, 300);
      expect(find.text('Скорость'), findsOneWidget);
      await tapText(tester, '1.5×');
      expect(AudioEngine.I.s.rate, 1.5);
      expect(prefs.getString('audioRate'), '1.5');
      await tapText(tester, '15 мин');
      expect(AudioEngine.I.s.sleep?.minutes, 15);
      expect(find.textContaining('сон через'), findsOneWidget);
      await tapText(tester, 'Конец главы');
      expect(AudioEngine.I.s.sleep?.kind, 'chapter');
      expect(find.text('до конца главы'), findsOneWidget);
      await tapText(tester, 'Выкл');
      expect(AudioEngine.I.s.sleep, isNull);
      await tapText(tester, '30 мин'); // таймер остаётся — его гасит закрытие
      await tester.tap(find.bySemanticsLabel('Закрыть аудио'));
      await spin(tester, 300);
      expect(AudioEngine.I.s.active, false);
      expect(AudioEngine.I.s.sleep, isNull);
      await finish(tester);
    });
  }

  testWidgets('аудио: полный проигрыватель открывается из мини-проигрывателя и ведёт себя', (tester) async {
    for (final v in variants) {
      AudioEngine.I.state.value = playing();
      AudioEngine.I.time.value = const TimeSnap(10, 100);
      await boot(tester, v, (ctx, ref) {}, extra: const Positioned(left: 0, right: 0, bottom: 0, child: AudioBar()));
      await tester.tap(find.text(Books.instance.formatRef('Gen', 1, 2)).first);
      await spin(tester, 800);
      expect(find.text('${Books.instance.meta('Gen').name} 1'), findsOneWidget);
      expect(find.textContaining('Слово Gen 1:3'), findsOneWidget);
      // скорость по кругу
      await tester.tap(find.text('1×'));
      await spin(tester, 200);
      expect(AudioEngine.I.s.rate, 1.25);
      // громкость и перемотка
      await tester.drag(find.byType(Slider).last, const Offset(-60, 0));
      await spin(tester, 200);
      expect(AudioEngine.I.s.volume, lessThan(1));
      await tester.drag(find.byType(Slider).first, const Offset(40, 0));
      await spin(tester, 200);
      // звучащий стих сменился — текст идёт за ним
      AudioEngine.I.state.value = AudioEngine.I.s.copyWith(ref: const VerseRef('Gen', 1, 4));
      await spin(tester, 700);
      // ручная прокрутка и возврат через 3,5 с
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await spin(tester, 4000);
      // таймер сна: лента минут
      await tester.tap(find.byIcon(LucideIcons.moon));
      await spin(tester, 600);
      expect(find.text('Запустить таймер'), findsOneWidget);
      await tester.tap(find.text('Запустить таймер'));
      await spin(tester, 500);
      expect(AudioEngine.I.s.sleep?.minutes, 15);
      await tester.tap(find.byIcon(LucideIcons.moon));
      await spin(tester, 600);
      expect(find.text('Выключить таймер'), findsOneWidget);
      await tester.tap(find.text('До конца главы'));
      await spin(tester, 500);
      expect(AudioEngine.I.s.sleep?.kind, 'chapter');
      // свайп вниз за шапку закрывает
      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await spin(tester, 600);
      expect(find.text('${Books.instance.meta('Gen').name} 1'), findsNothing);
      // выключили запись — страница закрывается сама
      await finish(tester);
      AudioEngine.I.state.value = const AudioState();
    }
  });

  for (final v in variants) {
    testWidgets('аудио [${v.name}]: окно «Аудио» в настройках — скачанные книги и удаление', (tester) async {
      await boot(tester, v, (ctx, ref) => openAudioSettings(ctx));
      expect(find.text('Аудио'), findsOneWidget);
      expect(find.textContaining('Пока ничего нет'), findsOneWidget);
      await finish(tester);
      prefs.setString('offlineAudio', jsonEncode({'aud1|Gen': {'at': 1, 'files': 3, 'bytes': 52428800}, 'aud1|John': {'at': 2, 'files': 2, 'bytes': 1048576}}));
      await boot(tester, v, (ctx, ref) => openAudioSettings(ctx));
      expect(find.text('Скачано 2 кн. · 51 МБ'), findsOneWidget);
      await tapTip(tester, 'Удалить скачанную книгу ${Books.instance.meta('Gen').name}');
      expect(find.text('Отмена'), findsOneWidget);
      await tapText(tester, 'Отмена');
      expect(find.text('Отмена'), findsNothing);
      await tapTip(tester, 'Удалить скачанную книгу ${Books.instance.meta('Gen').name}');
      await tapText(tester, 'Удалить');
      await spin(tester, 300);
      expect(find.text('Скачано 1 кн. · 1 МБ'), findsOneWidget);
      await finish(tester);
    });
  }
}

/// Проповедь в prefs до открытия окна (отдельный контейнер — как будто создана раньше)
String c0Create({String title = 'Моя тема'}) {
  final tmp = ProviderContainer();
  final id = tmp.read(sermonsProvider.notifier).create(title);
  tmp.dispose();
  return id;
}

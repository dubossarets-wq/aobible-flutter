// Сценарии «как у человека» для: страница дня плана (PlanView), значок «стих в проповеди» и «Часть стиха → В проповедь»,
// выбор стихов для проповеди поиском, пункты меню «Ещё» по флагам.
// Светлая и тёмная тема, экран 400×830; любое исключение Flutter (переполнение, setState после dispose) роняет тест.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/bible.dart';
import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/audio/audio_bar.dart';
import 'package:aobible/features/audio/audio_engine.dart';
import 'package:aobible/features/features.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/plans/plan_logic.dart';
import 'package:aobible/features/plans/plan_mode.dart';
import 'package:aobible/features/plans/plan_return.dart';
import 'package:aobible/features/plans/plan_store.dart';
import 'package:aobible/features/plans/plan_view.dart';
import 'package:aobible/features/plans/plans_sheet.dart';
import 'package:aobible/features/plans/ui_kit.dart' show showPage;
import 'package:aobible/features/sermons/sermon_store.dart';
import 'package:aobible/features/sermons/sermons_sheet.dart';
import 'package:aobible/ui/verse_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

class V {
  const V(this.name, this.theme);
  final String name, theme;
}

const variants = [V('светлая', 'light'), V('тёмная', 'dark')];

late Directory root;
late ProviderContainer c;

void makeBible(Directory dir) {
  final db = sqlite3.open('${dir.path}/rst-plus.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('''
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  const shape = {'Gen': (3, 5), 'Ps': (3, 4), 'John': (3, 20), 'Acts': (2, 5)};
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

Future<void> spin(WidgetTester tester, [int ms = 500]) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> real(WidgetTester tester, [int ms = 30]) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

Future<void> tapText(WidgetTester tester, String text, {bool last = false, bool first = false}) async {
  var f = find.textContaining(text);
  expect(f, findsWidgets, reason: 'нет «$text»');
  if (last) f = f.last;
  if (first) f = f.first;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await spin(tester, 300);
}

Future<void> tapExact(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await spin(tester, 300);
}

Map<String, dynamic> plan({String uid = 'p1', int days = 4}) => {
      'uid': uid,
      'planId': 'x',
      'name': 'Тестовый план',
      'calendar': false,
      'start': localDate(),
      'readings': [
        for (var i = 0; i < days; i++) i == 1 ? ['Gen.1', 'John.3.16-18'] : ['Gen.${i % 3 + 1}'],
      ],
      'done': <String, dynamic>{},
    };

/// Окно приложения 400×830 с темой; внизу — кнопка «К плану»
Future<void> pumpApp(WidgetTester tester, V v, Widget Function(BuildContext) body, {Widget? bottom}) async {
  tester.view.physicalSize = const Size(400, 830);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(settingsProvider.notifier).set({'theme': v.theme});
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      scaffoldMessengerKey: Hub.messengerKey,
      theme: ThemeData(brightness: v.theme == 'dark' ? Brightness.dark : Brightness.light),
      home: Builder(builder: (ctx) => Scaffold(body: body(ctx), bottomNavigationBar: bottom)),
    ),
  ));
  await spin(tester, 300);
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await spin(tester, 2000);
  expect(tester.takeException(), isNull);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    root = Directory('${Directory.systemTemp.path}/aob_feat_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final mods = Directory('${root.path}/modules')..createSync();
    makeBible(mods);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => root.path);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'), (call) async => 'dev.fluttercommunity.plus/share/unavailable');
    await Books.load();
    await ModuleStore.initAt(mods);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await setLang('ru');
    AudioEngine.I.state.value = const AudioState();
    planMode.value = {};
    lastPlans.value = {};
    planStart.clear();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Hub.reset();
  });

  tearDown(() async {
    await AudioEngine.I.stop();
    AudioEngine.I.state.value = const AudioState();
    planMode.value = {};
  });

  Future<void> openDay(WidgetTester tester, V v, {int day = 1, String uid = 'p1'}) async {
    prefs.setString('plans', jsonEncode([plan()]));
    await pumpApp(tester, v, (ctx) => PlanHost(pane: 0), bottom: const PlanReturnPill());
    watchPlanLeaving(c);
    planStart[0] = (at: 0, ref: null);
    setPlanMode(0, (uid: uid, day: day));
    await spin(tester, 500);
  }

  // ===== СТРАНИЦА ДНЯ ПЛАНА ======================================================================================

  for (final v in variants) {
    testWidgets('страница дня [${v.name}]: лента отрывков, отметки, «Дальше», конец дня и следующий день', (tester) async {
      await openDay(tester, v);
      expect(find.text('День 2 · 0/2'), findsOneWidget);
      expect(find.text('Тестовый план'), findsOneWidget);
      expect(find.text('Читайте подряд — отрывок отметится сам.'), findsOneWidget);
      expect(find.textContaining('Слово Gen 1:1 и любовь'), findsOneWidget); // стихи отрывка — той же строкой, что в читалке
      expect(find.text('Gen 1'), findsWidgets); // чип отрывка в закреплённой строке
      expect(find.text('Отметить прочитанным'), findsWidgets);
      expect(find.textContaining('Дальше:'), findsWidgets);
      expect(find.text('Осталось:'), findsNothing);

      // «Отметить прочитанным» у первого отрывка
      await tapText(tester, 'Отметить прочитанным', first: true);
      expect(find.text('День 2 · 1/2'), findsOneWidget);
      expect(readingDone(c.read(plansProvider).first, 1, 'Gen.1'), isTrue);
      expect(find.text('Быт 1 — прочитано'), findsWidgets);

      // «Дальше» прокручивает к следующему отрывку
      await tapText(tester, 'Дальше:', first: true);
      await spin(tester, 500);
      expect(find.textContaining('Слово John 3:16'), findsWidgets);

      // отмечаем второй — день выполнен
      await tapText(tester, 'Отметить прочитанным', first: true);
      await spin(tester, 300);
      expect(dayDone(c.read(plansProvider).first, 1), isTrue);
      expect(find.textContaining('План на сегодня выполнен'), findsWidgets);
      expect(find.text('Читать день 3'), findsOneWidget);

      // «Читать день 3» открывает следующий день
      await tapText(tester, 'Читать день 3');
      expect(planMode.value[0]?.day, 2);
      expect(find.text('День 3 · 0/1'), findsOneWidget);

      // выход из плана — крестик в закреплённой строке
      final x = find.byTooltip('Выйти из плана');
      await tester.tap(x);
      await spin(tester, 300);
      expect(planMode.value, isEmpty);
      await finish(tester);
    });

    testWidgets('страница дня [${v.name}]: отрывок отмечается сам, когда дочитан и прошло время', (tester) async {
      await openDay(tester, v, day: 0);
      expect(dayDone(c.read(plansProvider).first, 0), isFalse);
      // minSeconds(5 стихов) — 13 секунд; отрывок на экране целиком
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(dayDone(c.read(plansProvider).first, 0), isTrue, reason: 'отрывок должен отметиться сам');
      expect(find.textContaining('План на сегодня выполнен'), findsWidgets);
      expect(readLogData()['days'], isNotEmpty); // глава пошла в учёт прочитанного
    });

    testWidgets('страница дня [${v.name}]: «Читать дальше — вне плана» и «К плану»', (tester) async {
      await openDay(tester, v, day: 0);
      await tapText(tester, 'Читать дальше: Gen 2');
      // ушли из плана: страница закрыта, внизу кнопка возврата
      expect(planMode.value, isEmpty);
      expect(c.read(panesProvider).first.ref.chapter, 2);
      expect(lastPlans.value[0]?.day, 0);
      expect(find.text('К плану · 0 из 1'), findsOneWidget);
      await tapText(tester, 'К плану · 0 из 1');
      expect(planMode.value[0]?.day, 0);
      expect(lastPlans.value, isEmpty);
      expect(find.text('День 1 · 0/1'), findsOneWidget);
      // любой другой переход в панели тоже выводит из плана, кнопку можно скрыть крестиком
      c.read(panesProvider.notifier).navigate(0, const VerseRef('Ps', 1, 1));
      await spin(tester, 300);
      expect(planMode.value, isEmpty);
      expect(find.text('К плану · 0 из 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Скрыть кнопку возврата к плану'));
      await spin(tester, 300);
      expect(find.textContaining('К плану'), findsNothing);
      await finish(tester);
    });

    testWidgets('планы [${v.name}]: «Читать» открывает страницу дня, подсказка кнопки дня', (tester) async {
      prefs.setString('plans', jsonEncode([plan()]));
      await pumpApp(tester, v, (ctx) => Center(child: GestureDetector(onTap: () => showPage(ctx, (_) => const PlansSheet(pane: 0)), child: const Text('открыть'))));
      watchPlanLeaving(c);
      await tester.tap(find.text('открыть'));
      await spin(tester, 600);
      await real(tester);
      await spin(tester, 600);
      expect(find.byTooltip('Отметить весь день прочитанным'), findsOneWidget);
      final read = find.text('Читать');
      await tester.ensureVisible(read.last);
      await tester.pump();
      await tester.tap(read.last);
      await spin(tester, 700);
      expect(planMode.value[0]?.uid, 'p1');
      expect(planMode.value[0]?.day, 0);
      expect(find.text('Планы чтения'), findsNothing); // окно закрылось
    });
  }

  // ===== ПРОПОВЕДИ ===============================================================================================

  for (final v in variants) {
    testWidgets('проповеди [${v.name}]: значок «стих в проповеди», часть стиха, выбор стихов поиском', (tester) async {
      Hub.reset();
      registerFeatures();
      // проповедь со стихом Быт 1:2
      prefs.setString('sermons', jsonEncode([
        {
          'id': 's1', 'title': 'Благодать', 'date': '', 'createdAt': 1, 'updatedAt': 5,
          'blocks': [{'id': 'b1', 'type': 'verse', 'book': 'Gen', 'chapter': 1, 'verse': 2, 'to': null, 'text': 'Слово Gen 1:2 и любовь', 'moduleId': 'rst-plus'}],
        },
      ]));
      await pumpApp(tester, v, (ctx) => Consumer(builder: (ctx, ref, _) {
            final s = ref.watch(settingsProvider);
            final bt = loadBook('rst-plus', 'Gen');
            return ListView(children: [
              for (final it in bt.items.where((x) => x.kind == ItemKind.verse && x.chapter == 1))
                VerseView(item: it, book: 'Gen', settings: s, pane: 0, moduleId: 'rst-plus'),
            ]);
          }));
      // значок — только у стиха 2
      expect(find.byTooltip('Открыть проповедь'), findsOneWidget);
      await tester.tap(find.byTooltip('Открыть проповедь'));
      await spin(tester, 700);
      expect(find.text('Благодать'), findsWidgets); // открылась именно эта проповедь

      // «Добавить стих»: ссылка добавляет все стихи сразу
      await tapExact(tester, 'Стих');
      await spin(tester, 500);
      await tester.enterText(find.byType(EditableText).last, 'Ин 3:16-18');
      await spin(tester, 500);
      expect(find.textContaining('Добавить в проповедь: '), findsWidgets);
      await tapText(tester, 'Добавить в проповедь: ', last: true);
      await spin(tester, 500);
      final blocks = blocksOf(c.read(sermonsProvider).first);
      final john = blocks.where((b) => b['book'] == 'John').toList();
      expect(john.length, 1);
      expect(john.first['verse'], 16);
      expect(john.first['to'], 18);
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: слова ищутся тем же поиском, область «Новый Завет»', (tester) async {
      prefs.setString('sermons', jsonEncode([
        {'id': 's1', 'title': 'Благодать', 'date': '', 'createdAt': 1, 'updatedAt': 5, 'blocks': <dynamic>[]},
      ]));
      await pumpApp(tester, v, (ctx) => Center(child: GestureDetector(onTap: () => showPage(ctx, (_) => const SermonsSheet(pane: 0, open: 's1'), page: true), child: const Text('открыть'))));
      await tester.tap(find.text('открыть'));
      await spin(tester, 700);
      await tapExact(tester, 'Стих');
      await spin(tester, 500);
      await tester.enterText(find.byType(EditableText).last, 'любовь');
      await spin(tester, 500);
      await real(tester, 400); // поиск идёт в отдельном потоке
      await spin(tester, 500);
      expect(find.textContaining('Найдено: '), findsOneWidget);
      // область «НЗ» оставляет только Ин и Деян
      await tapText(tester, 'НЗ');
      await spin(tester, 500);
      await real(tester, 400);
      await spin(tester, 500);
      expect(find.textContaining('Gen 1:1'), findsNothing);
      // нажатие на место добавляет один стих и остаётся в поиске
      final hit = find.textContaining('Слово John').first;
      await tester.tap(hit);
      await spin(tester, 400);
      expect(blocksOf(c.read(sermonsProvider).first).length, 1);
      await finish(tester);
    });

    testWidgets('проповеди [${v.name}]: «Часть стиха» → «В проповедь» кладёт выбранные слова', (tester) async {
      Hub.reset();
      registerFeatures();
      await pumpApp(tester, v, (ctx) => Consumer(builder: (ctx, ref, _) => Center(child: GestureDetector(onTap: () => Hub.addFragmentToSermon!(ctx, ref, const VerseRef('Gen', 1, 1), 'rst-plus', 'так возлюбил'), child: const Text('часть')))));
      await tester.tap(find.text('часть'));
      await spin(tester, 700);
      expect(find.text('Добавить в проповедь'), findsOneWidget);
      expect(find.textContaining('(часть)'), findsWidgets);
      await tester.enterText(find.byType(EditableText).last, 'Мысль');
      await tapText(tester, 'Создать');
      await spin(tester, 400);
      final b = blocksOf(c.read(sermonsProvider).first).single;
      expect(b['part'], true);
      expect(b['text'], 'так возлюбил');
      await finish(tester);
    });
  }

  // ===== ЗАПИСИ НЕТ ==============================================================================================

  testWidgets('нет записи: заглушка диктора не читает, человек видит прежнее сообщение', (tester) async {
    await pumpApp(tester, variants.first, (ctx) => const SizedBox(), bottom: const AudioBar());
    await tester.runAsync(() => AudioEngine.I.listenFrom(c, 0, 'rst-plus', const VerseRef('Gen', 1, 1)));
    await spin(tester, 300);
    expect(find.text('Для этой главы нет аудиозаписи.'), findsOneWidget);
    expect(find.textContaining('диктор'), findsNothing);
    await finish(tester);
  });

  // ===== МЕНЮ «ЕЩЁ» ПО ФЛАГАМ ====================================================================================

  for (final wide in [false, true]) {
    testWidgets('меню «Ещё» [${wide ? 'широкий экран' : 'телефон'}]: проповеди, «Слушать», планы — по флагам', (tester) async {
      Hub.reset();
      registerFeatures();
      await pumpApp(tester, variants.first, (ctx) => Consumer(builder: (ctx, ref, _) => Center(child: GestureDetector(onTap: () => Hub.openMore!(ctx, ref, 0), child: const Text('меню')))));
      if (wide) {
        tester.view.physicalSize = const Size(1000, 800);
        await spin(tester, 200);
      }
      await tester.tap(find.text('меню'));
      await spin(tester, 800);
      expect(find.text('Проповеди'), findsOneWidget);
      expect(find.text('Слушать с этого места'), findsOneWidget);
      expect(find.text('Планы чтения'), wide ? findsOneWidget : findsNothing); // на телефоне у планов своя вкладка
      // флаги выключены — пунктов нет
      await tester.tapAt(const Offset(5, 5));
      await spin(tester, 600);
      c.read(settingsProvider.notifier).set({
        'menu': {'help': true, 'lastBookmark': true, 'sermons': false, 'plans': false, 'listen': false, 'maps': true, 'focus': false, 'book': false, 'split': true},
      });
      await tester.tap(find.text('меню'));
      await spin(tester, 800);
      expect(find.text('Проповеди'), findsNothing);
      expect(find.text('Слушать с этого места'), findsNothing);
      expect(find.text('Планы чтения'), findsNothing);
      await finish(tester);
    });
  }
}

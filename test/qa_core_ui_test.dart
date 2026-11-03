// Мощная проверка ядра и оболочки: читалка, «Перейти», поиск, вкладки, две панели — на телефоне 400×830
// в светлой и тёмной теме и при крупном шрифте. Любое исключение Flutter (переполнение, бесконечные
// ограничения, setState после dispose) роняет тест.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/features.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/main.dart';
import 'package:aobible/ui/kit.dart';
import 'package:aobible/ui/reader_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

/// Маленький модуль-перевод в том же виде, как его пишет ModuleStore (verses, headings, xrefs, verses_fts)
void makeBible(String id, String name, String lang, Map<String, List<List<String>>> books) {
  final db = sqlite3.open('${dir.path}/$id.db');
  db.execute('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  var n = 0;
  final list = <Map<String, dynamic>>[];
  books.forEach((book, chapters) {
    list.add({'id': book, 'name': book, 'short': book, 'chapters': chapters.length});
    for (var c = 0; c < chapters.length; c++) {
      for (var v = 0; v < chapters[c].length; v++) {
        n++;
        db.execute('INSERT INTO verses VALUES (?,?,?,?,?)', [n, book, c + 1, v + 1, chapters[c][v]]);
        db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, chapters[c][v].replaceAll(RegExp(r'<[^>]*>'), '')]);
      }
    }
    db.execute('INSERT INTO headings VALUES (?,?,?,?)', [book, 1, 1, 'Заголовок раздела']);
  });
  db.execute('INSERT INTO meta VALUES (?,?)', [
    'json',
    jsonEncode({'id': id, 'type': 'bible', 'name': name, 'title': 'Тестовый $name', 'language': lang, 'bookList': list}),
  ]);
  db.close();
}

List<List<String>> chapters(String word, int count, int verses) => [
      for (var c = 1; c <= count; c++)
        [for (var v = 1; v <= verses; v++) 'Стих $v главы $c: $word светильник и свет мира, и в начале было Слово.'],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_qa_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final books = {
      'Gen': chapters('Бог', 3, 12),
      'John': [
        ...chapters('Слово', 2, 10),
        [for (var v = 1; v <= 20; v++) v == 16 ? 'Ибо так возлюбил Бог мир, что отдал Сына Своего Единородного.' : 'Стих $v главы 3: <w s="G26">любовь</w> и истина.'],
      ],
      'Rev': chapters('Агнец', 2, 8),
    };
    makeBible('rst-plus', 'РСТ', 'ru', books);
    makeBible('kjv', 'KJV', 'en', books);
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.reset();
    livePositions.clear();
    SyncHub.listeners.clear();
    SyncHub.driver = 0;
  });

  void phone(WidgetTester tester, {double scale = 1.0}) {
    tester.view.physicalSize = const Size(400, 830);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  Future<ProviderContainer> start(WidgetTester tester, {String theme = 'light', double scale = 1.0, Map<String, dynamic>? settings, String? panes}) async {
    phone(tester, scale: scale);
    prefs.setString('settings', jsonEncode({'theme': theme, ...?settings}));
    if (panes != null) prefs.setString('panes', panes);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const AoBibleApp()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    return c;
  }

  // Поиск идёт в отдельном потоке — отдаём ему реальное время
  Future<void> settle(WidgetTester tester, {int ms = 600}) async {
    await tester.pump(const Duration(milliseconds: 400)); // пауза ввода (в поддельном времени)
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  String paneBook(ProviderContainer c, [int i = 0]) => c.read(panesProvider)[i].ref.book;

  for (final (theme, scale) in [('light', 1.0), ('dark', 1.0), ('light', 1.3), ('dark', 1.3)]) {
    final tag = '$theme x$scale';

    testWidgets('Читалка и шапка: открытие, главы, история — $tag', (tester) async {
      final c = await start(tester, theme: theme, scale: scale);
      expect(find.text('Глава 1'), findsWidgets);
      expect(find.byType(RoundFab), findsWidgets);
      await tester.tap(find.byTooltip('Следующая глава'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.read(panesProvider)[0].ref.chapter, 2);
      await tester.tap(find.byTooltip('Предыдущая глава'));
      await tester.pump();
      expect(c.read(panesProvider)[0].ref.chapter, 1);
      await tester.tap(find.byTooltip('Назад по истории'));
      await tester.pump();
      expect(c.read(panesProvider)[0].ref.chapter, 2);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.fling(find.byType(Scrollable).first, const Offset(-300, 0), 1500);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('РСТ').first);
      await tester.pumpAndSettle();
      expect(find.text('Перевод'), findsOneWidget);
      await tester.tap(find.text('KJV'));
      await tester.pumpAndSettle();
      expect(c.read(panesProvider)[0].moduleId, 'kjv');
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Перейти»: книга, глава, ссылка, ошибка — $tag', (tester) async {
      final c = await start(tester, theme: theme, scale: scale);
      await tester.tap(find.textContaining('1:1').first);
      await tester.pumpAndSettle();
      expect(find.text('Перейти'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Новый Завет'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Books.instance.meta('John').name).first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AobSheet), matching: find.text('3')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('С начала главы')); // глава → стихи (BookNavigator.jsx): с начала главы
      await tester.pumpAndSettle();
      expect(c.read(panesProvider)[0].ref, const VerseRef('John', 3, 1));
      expect(find.text('Перейти'), findsNothing);
      await tester.tap(find.textContaining('3:').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'абракадабра');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(find.text('Не понял ссылку. Пример: Ин 3:16'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ин 3:16');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(c.read(panesProvider)[0].ref, const VerseRef('John', 3, 16));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Поиск: слово, область, целые слова, ссылка, Стронг, история — $tag', (tester) async {
      await start(tester, theme: theme, scale: scale);
      await tester.tap(find.text('Поиск').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'светильник');
      await settle(tester);
      expect(find.textContaining('Найдено:'), findsOneWidget);
      expect(find.textContaining('Найдено: 0'), findsNothing);
      for (final o in ['НЗ', 'ВЗ', 'Вся Библия']) {
        await tester.tap(find.text(o).first);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: o);
      }
      await tester.enterText(find.byType(TextField), 'свет');
      await settle(tester);
      await tester.ensureVisible(find.text('Только целые слова'));
      await tester.tap(find.text('Только целые слова'));
      await settle(tester);
      if (find.text('Во всех модулях').evaluate().isNotEmpty) {
        await tester.tap(find.text('Во всех модулях').first);
        await settle(tester);
      }
      await tester.enterText(find.byType(TextField), 'Ин 3:16');
      await settle(tester);
      expect(find.textContaining('Перейти:'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'G26');
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'любовь');
      await settle(tester);
      await tester.tap(find.byTooltip('Очистить'));
      await tester.pump();
      expect((tester.widget(find.byType(TextField)) as TextField).controller!.text, '');
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Поиск').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Откр 2:3');
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Выделение стиха и две панели — $tag', (tester) async {
      final c = await start(tester, theme: theme, scale: scale);
      await tester.longPress(find.textContaining('Стих 1 главы 1').first);
      await tester.pump();
      expect(c.read(selectionProvider)[0], isNotEmpty);
      await tester.tap(find.textContaining('Стих 2 главы 1').first);
      await tester.pump();
      expect(c.read(selectionProvider)[0]!.length, 2);
      c.read(selectionProvider.notifier).clear(0);
      await tester.pump();
      await tester.tap(find.byTooltip('Читать параллельно'));
      await tester.pumpAndSettle();
      expect(c.read(panesProvider).length, 2);
      expect(find.byType(ReaderPane), findsNWidgets(2));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      c.read(settingsProvider.notifier).set({'splitLayout': 'cols'});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      c.read(settingsProvider.notifier).set({'splitLayout': 'rows'});
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Закрыть вторую панель'));
      await tester.pumpAndSettle();
      expect(c.read(panesProvider).length, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Вкладки нижней панели без функций и настройки вида — $tag', (tester) async {
      final c = await start(tester, theme: theme, scale: scale, settings: {'showStrongs': true, 'showVerseNumbers': true});
      for (final tab in ['Планы', 'Закладки', 'Ещё']) {
        await tester.tap(find.text(tab).last);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: tab);
      }
      await tester.pump(const Duration(seconds: 5));
      for (final patch in [
        {'fontSize': 28.0},
        {'strongPos': 'inline'},
        {'strongPos': 'sub'},
        {'verseNumPos': 'inline'},
        {'textAlign': 'justify'},
        {'showHeadings': false},
        {'theme': 'sepia'},
        {'fontSize': 14.0, 'lineHeight': 1.2},
      ]) {
        c.read(settingsProvider.notifier).set(patch);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '$patch');
      }
    });
  }

  testWidgets('Конец книги и переход в соседнюю', (tester) async {
    final c = await start(tester, panes: jsonEncode([{'moduleId': 'rst-plus', 'ref': {'book': 'Gen', 'chapter': 3, 'verse': 1}}]));
    await tester.tap(find.byTooltip('Следующая глава'));
    await tester.pump();
    expect(paneBook(c), isNot('Gen'));
    await tester.tap(find.byTooltip('Предыдущая глава'));
    await tester.pump();
    expect(paneBook(c), 'Gen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Окно: потянули вниз и тем же движением вверх — окно встаёт на место, список не прокручивается; дальше 90 px — закрывается', (tester) async {
    await start(tester);
    final ctx = tester.element(find.byType(ReaderPane).first);
    final list = ScrollController();
    addTearDown(list.dispose);
    Future<void> open() async {
      unawaited(showAobSheet(ctx, builder: (_) => AobSheet(title: 'Окно', scroll: false, child: ListView(controller: list, children: [for (var i = 0; i < 80; i++) SizedBox(height: 44, child: Text('Строка $i'))]))));
      await tester.pumpAndSettle();
    }

    await open();
    final sheetTop = tester.getTopLeft(find.text('Окно')).dy;
    final g = await tester.startGesture(tester.getCenter(find.text('Строка 3')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 10)); // вниз на 60
      await tester.pump();
    }
    final pulled = tester.getTopLeft(find.text('Окно')).dy - sheetTop;
    expect(pulled, greaterThan(30), reason: 'окно едет за пальцем (первые 20 px — порог жеста)');
    expect(list.offset, 0);
    for (var i = 0; i < pulled ~/ 10; i++) {
      await g.moveBy(const Offset(0, -10)); // обратно вверх ровно на столько, на сколько опустилось окно
      await tester.pump();
    }
    await g.moveBy(Offset(0, -(pulled % 10)));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Окно')).dy, closeTo(sheetTop, 1), reason: 'окно поднялось до конца');
    expect(list.offset, 0, reason: 'пока окно поднималось, список стоял');
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -10)); // дальше вверх — уже прокрутка списка
      await tester.pump();
    }
    expect(list.offset, greaterThan(30));
    expect(tester.getTopLeft(find.text('Окно')).dy, closeTo(sheetTop, 1));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Окно'), findsOneWidget);

    // список у верха, потянули дальше 90 px и отпустили — окно закрылось
    list.jumpTo(0);
    await tester.pump();
    final g2 = await tester.startGesture(tester.getCenter(find.text('Строка 3')));
    for (var i = 0; i < 12; i++) {
      await g2.moveBy(const Offset(0, 12));
      await tester.pump();
    }
    await g2.up();
    await tester.pumpAndSettle();
    expect(find.text('Окно'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant(const {TargetPlatform.android, TargetPlatform.iOS})); // на iPhone список у верха пружинит — окно всё равно едет

  testWidgets('«×» закрывает свою панель: у первой — остаётся вторая (её перевод и место), у второй — первая', (tester) async {
    final two = jsonEncode([
      {'moduleId': 'rst-plus', 'ref': {'book': 'Gen', 'chapter': 3, 'verse': 1}},
      {'moduleId': 'kjv', 'ref': {'book': 'John', 'chapter': 3, 'verse': 16}},
    ]);
    final c = await start(tester, panes: two);
    expect(find.byTooltip('Закрыть эту панель'), findsOneWidget);
    expect(find.byTooltip('Закрыть вторую панель'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть эту панель'));
    await tester.pumpAndSettle();
    final ps = c.read(panesProvider);
    expect(ps.length, 1);
    expect(ps.first.moduleId, 'kjv');
    expect(paneBook(c), 'John');
    expect(ps.first.ref.chapter, 3);
    expect(find.byTooltip('Читать параллельно'), findsOneWidget);
    // «×» второй панели — по-прежнему закрывает вторую
    c.read(panesProvider.notifier).toggleSplit();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Закрыть вторую панель'));
    await tester.pumpAndSettle();
    expect(c.read(panesProvider).single.moduleId, 'kjv');
    expect(tester.takeException(), isNull);
  });

  testWidgets('До четырёх панелей: «+» у последней, поровну по высоте, «×» средней — следующие встают на её место', (tester) async {
    final two = jsonEncode([
      {'moduleId': 'rst-plus', 'ref': {'book': 'Gen', 'chapter': 3, 'verse': 1}},
      {'moduleId': 'kjv', 'ref': {'book': 'John', 'chapter': 3, 'verse': 16}},
    ]);
    final c = await start(tester, panes: two);
    expect(find.byTooltip('Ещё одна панель'), findsOneWidget);
    await tester.tap(find.byTooltip('Ещё одна панель'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ещё одна панель'));
    await tester.pumpAndSettle();
    expect(c.read(panesProvider).length, 4);
    expect(find.byTooltip('Ещё одна панель'), findsNothing); // больше четырёх нельзя
    // поровну: шапки панелей — через одинаковые промежутки
    final tops = [for (final e in find.byTooltip('Закрыть эту панель').evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dy]..sort();
    expect(tops.length, 4);
    expect((tops[2] - tops[1]) - (tops[1] - tops[0]), closeTo(0, 2));
    // «×» второй: третья (была перевод первой) и четвёртая сдвигаются, вторая панель kjv закрыта
    c.read(panesProvider.notifier).closePane(1);
    await tester.pumpAndSettle();
    final ps = c.read(panesProvider);
    expect(ps.length, 3);
    expect(ps.map((p) => p.moduleId), isNot(contains('kjv')));
    expect(find.byTooltip('Ещё одна панель'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Широкий экран: две панели, поиск; снятие дерева не оставляет слушателей', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    prefs.setString('settings', jsonEncode({'theme': 'dark'}));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const AoBibleApp()));
    await tester.pump(const Duration(milliseconds: 100));
    c.read(panesProvider.notifier).toggleSplit();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Поиск'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(SyncHub.listeners, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('С подключёнными функциями: вкладки, «Ещё», выделение (панель действий)', (tester) async {
    registerFeatures();
    addTearDown(Hub.reset);
    final c = await start(tester);
    for (final tab in ['Планы', 'Закладки', 'Ещё']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester, ms: 300);
      expect(tester.takeException(), isNull, reason: tab);
      Hub.navigatorKey.currentState!.popUntil((r) => r.isFirst);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.longPress(find.textContaining('Стих 1 главы 1').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.read(selectionProvider)[0], isNotEmpty);
    expect(tester.takeException(), isNull);
    c.read(selectionProvider.notifier).clear(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Стих 2 главы 1').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Окна функций держатся открытыми: нет переполнений (Планы, Закладки, Ещё)', (tester) async {
    registerFeatures();
    addTearDown(Hub.reset);
    await start(tester);
    for (final tab in ['Планы', 'Закладки', 'Ещё']) {
      await tester.tap(find.text(tab).last);
      await settle(tester, ms: 500);
      await tester.pump(const Duration(seconds: 2));
      final ex = tester.takeException();
      expect(ex, isNull, reason: tab);
      Hub.navigatorKey.currentState!.popUntil((r) => r.isFirst);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.longPress(find.textContaining('Стих 1 главы 1').first);
    await tester.pump(const Duration(seconds: 1));
    final ex = tester.takeException();
    expect(ex, isNull);
  });
}

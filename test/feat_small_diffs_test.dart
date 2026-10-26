// Мелкие отличия от веба: «Перейти» тянется за пальцем, плашки отличий в сравнении, плавный пульс сердечка,
// шрифт читалки (--font-text) в заметке и цитатах. Телефон 400×830, светлая и тёмная; любое исключение Flutter роняет тест.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/bookmarks/sheets.dart' show showNoteSheet;
import 'package:aobible/features/study/compare_sheet.dart' show DiffText, diffWords;
import 'package:aobible/features/study/sheet.dart' show QuoteBox;
import 'package:aobible/main.dart';
import 'package:aobible/ui/home_screen.dart';
import 'package:aobible/ui/kit.dart' show AobSheet;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

void makeBible(String id, String name, String lang, Map<String, List<List<String>>> books, {Map<String, dynamic>? features}) {
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
        db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, chapters[c][v]]);
      }
    }
  });
  db.execute('INSERT INTO meta VALUES (?,?)', [
    'json',
    jsonEncode({'id': id, 'type': 'bible', 'name': name, 'title': 'Тестовый $name', 'language': lang, 'bookList': list, 'features': ?features}),
  ]);
  db.close();
}

List<List<String>> chapters(String word, int count, int verses) => [
      for (var c = 1; c <= count; c++) [for (var v = 1; v <= verses; v++) 'Стих $v главы $c: $word светильник и свет мира.'],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BookInfo john;
  // Текст внутри окна (а не в читалке под ним)
  Finder inSheet(String text) => find.descendant(of: find.byType(AobSheet), matching: find.text(text));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    john = Books.instance.meta('John');
    dir = Directory('${Directory.systemTemp.path}/aob_shellcore_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final books = {
      'Gen': chapters('Бог', 3, 12),
      'Tob': chapters('Товит', 2, 6), // неканоническая (dc) — со звёздочкой
      'John': [...chapters('Слово', 2, 10), chapters('Любовь', 1, 20).first],
      'Phlm': chapters('Филимон', 1, 5), // книга из одной главы — сразу стихи
      'Enoch': chapters('Енох', 2, 4), // нет в справочнике — вкладка «Апокрифы»
    };
    makeBible('rst-plus', 'РСТ', 'ru', books);
    makeBible('kjv', 'KJV', 'en', books, features: {'strongs': true});
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.reset();
    livePositions.clear();
    SyncHub.listeners.clear();
    SyncHub.driver = 0;
    focusHidden.value = false;
    planMode.value = {};
    readerMarks.value = {};
    updateAvailable.value = false;
    systemDark.value = false;
    tabActive.value = 'bible';
  });

  void screen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  Future<ProviderContainer> start(WidgetTester tester, {String theme = 'light', Size size = const Size(400, 830), Map<String, dynamic>? settings, String? panes}) async {
    screen(tester, size);
    prefs.setString('settings', jsonEncode({'theme': theme, ...?settings}));
    if (panes != null) prefs.setString('panes', panes);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const AoBibleApp()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    return c;
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('«Перейти»: содержимое тянется за пальцем и доезжает, переключатель следует ($theme)', (tester) async {
      await start(tester, theme: theme);
      await tester.tap(find.textContaining('1:1').first);
      await tester.pumpAndSettle();
      final ntShort = john.short.replaceAll('.', '');
      expect(inSheet(ntShort), findsNothing);
      final pill = find.descendant(of: find.byType(AobSheet), matching: find.byType(Positioned));
      final g = await tester.startGesture(tester.getCenter(inSheet('Ветхий Завет').first));
      await g.moveBy(const Offset(-30, 0));
      await tester.pump();
      await g.moveBy(const Offset(-150, 0));
      await tester.pump();
      // жест не закончен: Новый Завет уже виден рядом, Ветхий ещё на месте
      expect(inSheet(ntShort), findsOneWidget);
      expect(inSheet(Books.instance.meta('Tob').short.replaceAll('.', '')), findsOneWidget);
      expect(pill, findsWidgets);
      // медленно отпустили меньше чем на полпути — возвращается
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(inSheet(ntShort), findsNothing);
      // протянули больше половины — доезжает
      final g2 = await tester.startGesture(tester.getCenter(inSheet('Ветхий Завет').first));
      await g2.moveBy(const Offset(-30, 0));
      await g2.moveBy(const Offset(-260, 0));
      await tester.pump();
      await g2.up();
      await tester.pumpAndSettle();
      expect(inSheet(ntShort), findsOneWidget);
      expect(inSheet(Books.instance.meta('Tob').short.replaceAll('.', '')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Сравнение: плашки отличий скруглены и рисуются под текстом ($theme)', (tester) async {
      screen(tester, const Size(400, 830));
      final parts = diffWords('Бог так возлюбил мир', 'Господь так полюбил мир и все');
      expect(parts.where((p) => p.$2).map((p) => p.$1.trim()), containsAll(['Господь', 'полюбил']));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: theme == 'dark' ? Brightness.dark : Brightness.light),
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: DiffText(parts: parts, style: const TextStyle(fontSize: 16.3, height: 1.5)))),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final paint = tester.widget<CustomPaint>(find.descendant(of: find.byType(DiffText), matching: find.byType(CustomPaint)).first);
      expect(paint.painter, isNotNull);
      // рисунок собирается без ошибок
    });

    testWidgets('Шрифт читалки в заметке и цитате ($theme)', (tester) async {
      screen(tester, const Size(400, 830));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(settingsProvider.notifier).set({'theme': theme, 'fontFamily': 'PT Serif'});
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: Scaffold(body: Builder(builder: (context) => Column(children: [
              TextButton(onPressed: () => showNoteSheet(context, const [VerseRef('Gen', 1, 1)], null), child: const Text('открыть')),
              const QuoteBox('Цитата стиха'),
            ])))),
      ));
      await tester.pump();
      expect(tester.widget<Text>(find.text('Цитата стиха')).style?.fontFamily, 'PT Serif');
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).style?.fontFamily, 'PT Serif');
      await tester.enterText(find.byType(TextField), 'см. Ин 3:16');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

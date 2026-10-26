// Нижние вкладки поверх окон: окно открыто — вкладки видны и нажимаются, нажатие закрывает окна и открывает раздел,
// внизу окна есть отступ под панель. Телефон 400×830, светлая и тёмная тема, крупный шрифт; любое исключение Flutter роняет тест.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/main.dart';
import 'package:aobible/features/shell/library_sheet.dart';
import 'package:aobible/features/shell/prefs_sheet.dart';
import 'package:aobible/ui/search_screen.dart';
import 'package:aobible/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

void makeBible() {
  final db = sqlite3.open('${dir.path}/rst-plus.db');
  db.execute('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  var n = 0;
  for (var v = 1; v <= 60; v++) {
    n++;
    db.execute('INSERT INTO verses VALUES (?,?,?,?,?)', [n, 'John', 1, v, 'Стих $v: светильник и свет мира.']);
    db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, 'Стих $v светильник и свет мира']);
  }
  db.execute('INSERT INTO meta VALUES (?,?)', [
    'json',
    jsonEncode({'id': 'rst-plus', 'type': 'bible', 'name': 'РСТ', 'title': 'Тестовый РСТ', 'language': 'ru', 'bookList': [{'id': 'John', 'name': 'John', 'short': 'John', 'chapters': 1}]}),
  ]);
  db.close();
  // ещё модули — чтобы «Библиотека» была длиннее экрана
  for (var i = 0; i < 25; i++) {
    final d = sqlite3.open('${dir.path}/m$i.db');
    d.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT); CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT, chapter INTEGER, verse INTEGER, text TEXT);');
    d.execute('INSERT INTO meta VALUES (?,?)', ['json', jsonEncode({'id': 'm$i', 'type': 'bible', 'name': 'М$i', 'title': 'Модуль номер $i', 'language': 'ru', 'bookList': [{'id': 'John', 'name': 'John', 'short': 'John', 'chapters': 1}]})]);
    d.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_tabinset_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    makeBible();
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.reset();
    livePositions.clear();
    SyncHub.listeners.clear();
    SyncHub.driver = 0;
    focusHidden.value = false;
    systemDark.value = false;
    tabActive.value = 'bible';
    tabBarInset.value = 0;
    sheetsOpen.value = 0;
  });

  Future<void> start(WidgetTester tester, {String theme = 'light', Size size = const Size(400, 830), Map<String, dynamic>? settings}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    prefs.setString('panes', jsonEncode([{'moduleId': 'rst-plus', 'ref': const VerseRef('John', 1, 1).toJson()}]));
    prefs.setString('settings', jsonEncode({'theme': theme, ...?settings}));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const AoBibleApp()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }


  // Прокручиваем самый нижний список окна до конца и проверяем: список доходит до низа экрана (содержимое видно под
  // вкладками), а последняя строка — выше капсулы вкладок
  Future<void> checkEnd(WidgetTester tester) async {
    final pill = find.byKey(const ValueKey('tab-pill'));
    expect(pill, findsOneWidget);
    // самый высокий вертикальный список окна
    final all = find.descendant(of: find.byType(AobSheet).last, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)).evaluate().toList();
    all.sort((a, b) => tester.getSize(find.byElementPredicate((x) => x == b)).height.compareTo(tester.getSize(find.byElementPredicate((x) => x == a)).height));
    final list = find.byElementPredicate((x) => x == all.first);
    final rect = tester.getRect(list);
    expect(rect.bottom, closeTo(830, 1), reason: 'список доходит до низа окна');
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
    }
    var lastBottom = 0.0;
    for (final e in find.descendant(of: list, matching: find.byType(RichText)).evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      if (r.top < rect.bottom && r.bottom > rect.top) lastBottom = r.bottom > lastBottom ? r.bottom : lastBottom;
    }
    final capTop = tester.getTopLeft(pill).dy;
    expect(lastBottom, greaterThan(0));
    expect(lastBottom, lessThanOrEqualTo(capTop + 1), reason: 'последняя строка выше вкладок ($lastBottom против $capTop)');
    expect(tester.takeException(), isNull);
  }

  testWidgets('Библиотека: последняя строка выше вкладок', (tester) async {
    await start(tester);
    openLibrary(Hub.navigatorKey.currentContext!);
    await tester.pumpAndSettle();
    await checkEnd(tester);
  });

  testWidgets('Настройки: последняя строка выше вкладок', (tester) async {
    await start(tester);
    openPrefs(Hub.navigatorKey.currentContext!);
    await tester.pumpAndSettle();
    await checkEnd(tester);
  });

  testWidgets('Поиск с результатами: последняя строка выше вкладок', (tester) async {
    await start(tester);
    openSearch(Hub.navigatorKey.currentContext!, 0, query: 'светильник');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await checkEnd(tester);
  });
}

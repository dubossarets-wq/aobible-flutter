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
import 'package:aobible/ui/home_screen.dart';
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
  for (var v = 1; v <= 10; v++) {
    n++;
    db.execute('INSERT INTO verses VALUES (?,?,?,?,?)', [n, 'John', 1, v, 'Стих $v: светильник и свет мира.']);
    db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, 'Стих $v светильник и свет мира']);
  }
  db.execute('INSERT INTO meta VALUES (?,?)', [
    'json',
    jsonEncode({'id': 'rst-plus', 'type': 'bible', 'name': 'РСТ', 'title': 'Тестовый РСТ', 'language': 'ru', 'bookList': [{'id': 'John', 'name': 'John', 'short': 'John', 'chapters': 1}]}),
  ]);
  db.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_tabbar_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
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

  // Своё окно с длинным содержимым, открытое от навигатора (как окна функций)
  Future<void> openLong(WidgetTester tester) async {
    showAobSheet<void>(
      Hub.navigatorKey.currentContext!,
      initial: 0.6,
      builder: (_) => AobSheet(title: 'Длинное окно', child: Column(children: [for (var i = 0; i < 40; i++) SizedBox(height: 40, child: Text('Строка $i')), const SizedBox(key: ValueKey('last'), height: 40, child: Text('Последняя'))])),
    );
    await tester.pumpAndSettle();
  }

  for (final theme in ['light', 'dark']) {
    for (final big in [false, true]) {
      testWidgets('Окно открыто: вкладки видны, последняя строка выше панели, вкладка закрывает окно и открывает раздел — $theme${big ? ', крупный шрифт' : ''}', (tester) async {
        await start(tester, theme: theme, settings: big ? {'uiFontSize': 22} : null);
        expect(tabBarInset.value, closeTo(80, 0.5));
        await openLong(tester);
        expect(find.text('Длинное окно'), findsOneWidget);
        // панель видна поверх окна и затемнения
        final pill = find.byKey(const ValueKey('tab-pill'));
        expect(pill, findsOneWidget);
        expect(sheetsOpen.value, 1);
        // прокрутили в конец: последняя строка целиком выше капсулы
        await tester.drag(find.text('Строка 3'), const Offset(0, -3000));
        await tester.pumpAndSettle();
        final capTop = tester.getTopLeft(pill).dy - 5;
        expect(tester.getBottomLeft(find.byKey(const ValueKey('last'))).dy, lessThanOrEqualTo(capTop + 1));
        // нажали «Поиск» — окно закрылось, открылся поиск, вкладка подсвечена
        await tester.tap(find.text('Поиск').last);
        await tester.pumpAndSettle();
        expect(find.text('Длинное окно'), findsNothing);
        expect(tabActive.value, 'search');
        expect(pill, findsOneWidget);
        // повторное нажатие на ту же вкладку закрывает окно
        await tester.tap(find.text('Поиск').last);
        await tester.pumpAndSettle();
        expect(tabActive.value, 'bible');
        expect(sheetsOpen.value, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('«Библия» при открытом окне закрывает окно', (tester) async {
    await start(tester);
    await openLong(tester);
    await tester.tap(find.text('Библия').last);
    await tester.pumpAndSettle();
    expect(find.text('Длинное окно'), findsNothing);
    expect(tabActive.value, 'bible');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Широкий экран: вкладки — та же капсула по центру, не шире 544', (tester) async {
    await start(tester, size: const Size(1200, 800));
    expect(find.byKey(const ValueKey('tab-pill')), findsOneWidget);
    expect(find.text('Библия'), findsWidgets);
    expect(tabBarInset.value, greaterThan(0));
    final bar = tester.getRect(find.byType(ClipRRect).last);
    expect(bar.width, lessThanOrEqualTo(544));
    expect((bar.center.dx - 600).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });
}

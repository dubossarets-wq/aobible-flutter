// Инструкция: у каждого шага каждого урока подсвечена именно та кнопка, что в веб-версии (tours.js), а «Далее»
// нажимает её за человека. Проходим уроки по порядку кнопкой «Далее» на телефоне (400×830) и на компьютере (1000×800)
// и проверяем: цель найдена и это не всё окно целиком (запасной вариант «подсветить окно» — только там, где он есть в вебе).
// Таблица «урок → шаг → цель → чем найдена» печатается в консоль.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/features.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/shell/tour.dart';
import 'package:aobible/features/shell/tour_targets.dart';
import 'package:aobible/main.dart';
import 'package:aobible/ui/kit.dart' show AobSheet;
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
  for (var v = 1; v <= 12; v++) {
    n++;
    final text = 'Стих $v: {любовь|G26} и истина, {свет|G5457} мира.';
    db.execute('INSERT INTO verses VALUES (?,?,?,?,?)', [n, 'John', 1, v, text]);
    db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, 'Стих $v любовь и истина свет мира']);
    // параллельные места, чтобы у стиха было число [⇅ n]
    db.execute('INSERT INTO xrefs VALUES (?,?,?,?)', ['John', 1, v, jsonEncode(['Gen.1.1', 'Gen.1.2'])]);
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
    dir = Directory('${Directory.systemTemp.path}/aob_tourt_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    makeBible();
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.reset();
    registerFeatures();
    livePositions.clear();
    SyncHub.listeners.clear();
    SyncHub.driver = 0;
  });

  // Цели, у которых в вебе запасной вариант — всё окно (|| $('.sheet')), либо цель и есть окно
  const sheetOk = {'sheet'};

  Future<void> pumpMs(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final wide in [false, true]) {
    final tag = wide ? 'компьютер 1000×800' : 'телефон 400×830';
    for (final tour in tourDefs) {
      testWidgets('урок «${tour.id}» [$tag]: у каждого шага цель найдена', (tester) async {
        tester.view.physicalSize = wide ? const Size(1000, 800) : const Size(400, 830);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        prefs.setString('panes', jsonEncode([{'moduleId': 'rst-plus', 'ref': const VerseRef('John', 1, 1).toJson()}]));
        prefs.setString('settings', jsonEncode({'theme': 'light'}));
        final c = ProviderContainer();
        addTearDown(c.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const AoBibleApp()));
        await pumpMs(tester, 800);

        addTearDown(stopTour);
        startTour(tour.id);
        final steps = tour.steps(!wide);
        final rows = <String>[];
        final bad = <String>[];
        for (var i = 0; i < steps.length; i++) {
          final s = steps[i];
          await pumpMs(tester, 700); // before шага (80 мс) и анимации окон
          final id = s.target;
          final how = id == null
              ? '—'
              : id.startsWith('menu:') || id.startsWith('pref:')
                  ? 'поиск по подписи'
                  : tourResolvers.containsKey(id)
                      ? 'резолвер'
                      : tourKeys[id]?.currentContext != null
                          ? 'ключ'
                          : 'поиск по дереву';
          final r = id == null ? null : stepRect(s);
          final sheet = sheetRect();
          final isWholeSheet = r != null && sheet != null && r == sheet;
          rows.add('${tour.id} | шаг ${i + 1} | ${id ?? "нет цели"} | $how | ${r == null ? "НЕТ" : "${r.left.round()},${r.top.round()} ${r.width.round()}×${r.height.round()}"}${isWholeSheet ? " (окно целиком)" : ""} [окна: ${tester.widgetList<AobSheet>(find.byType(AobSheet)).map((x) => x.title).toList()}]');
          // ignore: avoid_print
          print('ROW ${rows.last}');
          if (id != null && (r == null || (isWholeSheet && !sheetOk.contains(id)))) bad.add('шаг ${i + 1} «$id»: ${r == null ? "не найдена" : "подсвечено всё окно"}');
          final ex = tester.takeException();
          if (ex != null) {
            bad.add('шаг ${i + 1}: исключение ${ex.toString().split("
").take(12).join(" / ")}');
            // ignore: avoid_print
            print('ИСКЛЮЧЕНИЕ ${ex.toString().split("
").take(14).join("
")}');
          }
          if (i == steps.length - 1) break;
          await tester.tap(find.text('Далее'), warnIfMissed: false);
          await pumpMs(tester, 600);
        }
        // ignore: avoid_print
        print('--- ${tour.id} [$tag]\n${rows.join('\n')}');
        stopTour();
        await pumpMs(tester, 600);
        expect(bad, isEmpty, reason: '${tour.id}: ${bad.join('; ')}');
      });
    }
  }
}

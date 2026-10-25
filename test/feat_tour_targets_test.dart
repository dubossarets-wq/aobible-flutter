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
import 'package:aobible/features/audio/audio_engine.dart';
import 'package:aobible/features/features.dart';
import 'package:aobible/features/maps/maps.dart' as maps;
import 'package:aobible/features/study/study_tables.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/shell/tour.dart';
import 'package:aobible/features/shell/tour_targets.dart';
import 'package:aobible/features/shell/news_sheet.dart' show markNewsSeen;
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
    final text = '{Любовь|G26} стих $v и истина, {свет|G5457} мира.';
    db.execute('INSERT INTO verses VALUES (?,?,?,?,?)', [n, 'John', 1, v, text]);
    db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, 'Стих $v любовь и истина свет мира']);
    // параллельные места, чтобы у стиха было число [⇅ n]
    db.execute('INSERT INTO xrefs VALUES (?,?,?,?)', ['John', 1, v, jsonEncode(['Gen.1.1', 'Gen.1.2'])]);
  }
  db.execute('INSERT INTO meta VALUES (?,?)', [
    'json',
    jsonEncode({'id': 'rst-plus', 'type': 'bible', 'name': 'РСТ', 'title': 'Тестовый РСТ', 'language': 'ru', 'features': {'strongs': true}, 'bookList': [{'id': 'John', 'name': 'John', 'short': 'John', 'chapters': 1}]}),
  ]);
  db.close();
}

// Греческий словарь Стронга: без него у слова нет статей и подсвечивать в окне нечего
void makeDict() {
  final db = sqlite3.open('${dir.path}/strongs-ru-greek.db');
  final j = {
    'id': 'strongs-ru-greek', 'type': 'dictionary', 'name': 'Стронг: греческий', 'title': 'Тест', 'language': 'ru', 'catalogVersion': '1', 'dictionaryKind': 'strongs', 'license': 'PD',
    'entries': {
      'G26': {'lemma': 'ἀγάπη', 'xlit': 'agape', 'definition': 'любовь'},
      'G5457': {'lemma': 'φῶς', 'xlit': 'phos', 'definition': 'свет'},
    },
  };
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({...j}..remove('entries'))]);
  buildStudyTables(db, j, 'dictionary');
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
    makeDict();
    sqlite3.open('${dir.path}/maps-test.db')
      ..execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)')
      ..execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': 'maps-test', 'type': 'maps', 'name': 'Карты', 'title': 'Карты', 'language': 'ru', 'catalogVersion': '1'})])
      ..close();
    await ModuleStore.initAt(dir);
    await setLang('ru');
    markNewsSeen();
    Hub.reset();
    registerFeatures();
    maps.register(); // в features.dart «Карты» пока не подключены — подключаем здесь, чтобы проверить урок
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
        await pumpMs(tester, 2600); // стартовое окно (_showStartup) ждёт 2 с

        addTearDown(stopTour);
        startTour(tour.id);
        final steps = tour.steps(!wide);
        final rows = <String>[];
        final bad = <String>[];
        for (var i = 0; i < steps.length; i++) {
          final s = steps[i];
          await pumpMs(tester, 700); // before шага (80 мс) и анимации окон
          if (tour.id == 'audio' && i == 1) {
            // в тесте нет записи чтеца — показываем проигрыватель с сообщением, как после нажатия без звука
            AudioEngine.I.state.value = const AudioState(active: true, error: 'нет записи');
            await pumpMs(tester, 300);
          }
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
            final head = ex.toString().split('\n').take(12).join(' / ');
            bad.add('шаг ${i + 1}: исключение $head');
            // ignore: avoid_print
            print('ИСКЛЮЧЕНИЕ $head');
          }
          if (i == steps.length - 1) break;
          if (s.target == 'sermon-new') {
            // шаг без «Далее»: человек сам впишет название и нажмёт «Создать» — делаем это за него
            await tester.tap(find.text('Создать'), warnIfMissed: false);
            await pumpMs(tester, 900);
            continue; // шаг закончился сам (until) — «Далее» нажимать не нужно
          }
          if (tour.id == 'xref' && i == 1) {
            // человек выбрал место в списке: оно открылось на второй половине экрана
            c.read(panesProvider.notifier).toggleSplit();
            await pumpMs(tester, 300);
          }
          await tester.tap(find.text('Далее'), warnIfMissed: false);
          await pumpMs(tester, 600);
        }
        // ignore: avoid_print
        print('--- ${tour.id} [$tag]\n${rows.join('\n')}');
        stopTour();
        await pumpMs(tester, 600);
        AudioEngine.I.state.value = const AudioState();
        expect(bad, isEmpty, reason: '${tour.id}: ${bad.join('; ')}');
      });
    }
  }
}

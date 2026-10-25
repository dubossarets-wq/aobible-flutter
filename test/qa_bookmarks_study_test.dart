// Сквозная проверка «Закладок» и «Изучения» так, как их нажимает человек: поверхность 400×830, светлая и тёмная
// тема, масштаб текста 1.0 и 1.3. Любое исключение Flutter (переполнение, бесконечные ограничения,
// setState после dispose) роняет тест — flutter_test сам проверяет tester.takeException() в конце.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/markup.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/bookmarks/bookmarks.dart' as bm;
import 'package:aobible/features/bookmarks/manager.dart';
import 'package:aobible/features/bookmarks/marks.dart';
import 'package:aobible/features/bookmarks/mydata_page.dart';
import 'package:aobible/features/bookmarks/sel_inline.dart';
import 'package:aobible/features/bookmarks/selection_bar.dart';
import 'package:aobible/features/bookmarks/sheets.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/study/commentary_sheet.dart';
import 'package:aobible/features/study/compare_sheet.dart';
import 'package:aobible/features/study/concordance_sheet.dart';
import 'package:aobible/features/study/dictionary_sheet.dart';
import 'package:aobible/features/study/image_viewer.dart';
import 'package:aobible/features/study/interlinear_sheet.dart';
import 'package:aobible/features/study/study.dart' as study;
import 'package:aobible/features/study/study_data.dart';
import 'package:aobible/features/study/study_tables.dart';
import 'package:aobible/features/study/verse_guide.dart';
import 'package:aobible/features/study/xrefs_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;
const _verbose = bool.fromEnvironment('QA_VERBOSE');

// --- Тестовые модули ------------------------------------------------------------------------

void _meta(Database db, Map<String, dynamic> meta) {
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode(meta)]);
}

/// Перевод: книга -> глава -> стихи (как таблицы ModuleStore)
void _bible(String id, String name, String lang, Map<String, List<List<String>>> books, {Map<String, dynamic> features = const {}, Map<String, List<String>> xrefs = const {}}) {
  final db = sqlite3.open('${dir.path}/$id.db');
  _meta(db, {'id': id, 'type': 'bible', 'name': name, 'title': 'Тест $name', 'language': lang, 'features': features, 'catalogVersion': '1'});
  db.execute('''
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
  ''');
  var n = 0;
  books.forEach((book, chapters) {
    for (var c = 0; c < chapters.length; c++) {
      for (var v = 0; v < chapters[c].length; v++) {
        db.execute('INSERT INTO verses VALUES (?, ?, ?, ?, ?)', [++n, book, c + 1, v + 1, chapters[c][v]]);
      }
    }
  });
  xrefs.forEach((k, refs) {
    final p = k.split('.');
    db.execute('INSERT INTO xrefs VALUES (?, ?, ?, ?)', [p[0], int.parse(p[1]), int.parse(p[2]), jsonEncode(refs)]);
  });
  db.close();
}

void _study(String id, String type, String name, String lang, Map<String, dynamic> body, {Map<String, dynamic> extra = const {}}) {
  final db = sqlite3.open('${dir.path}/$id.db');
  final j = {'id': id, 'type': type, 'name': name, 'title': 'Тест $name', 'language': lang, 'catalogVersion': '1', ...extra, ...body};
  _meta(db, {...j}..removeWhere((k, _) => k == 'entries' || k == 'refs' || k == 'wordIndex'));
  buildStudyTables(db, j, type);
  db.close();
}

const _jn316 = '{Ибо|G1063} так {возлюбил|G25|V-AAI-3S} {Бог|G2316} мир, что отдал Сына Своего Единородного';
const _gen1 = '{В начале|H7225} {сотворил|H1254 H853|TH8804} {Бог|H430} небо и землю.';

void _buildModules() {
  _bible('rst-plus', 'RST+', 'ru', {
    'Gen': [
      [_gen1, 'Земля же была безвидна и пуста.', 'И сказал Бог: да будет свет.']
    ],
    'John': [
      [],
      [],
      List.generate(18, (i) => i == 15 ? _jn316 : 'Стих номер ${i + 1}.'),
    ],
    'Rom': [
      ['Павел.'],
    ],
  }, features: {'strongs': true}, xrefs: {'Gen.1.1': ['John.1.1', 'Ps.33.6']});
  _bible('kjv', 'KJV', 'en', {
    'Gen': [
      ['In the beginning God created the heaven and the earth.', 'And the earth was without form.', 'And God said, Let there be light.']
    ],
    'John': [
      [],
      [],
      List.generate(18, (i) => i == 15 ? 'For God so loved the world.' : 'Verse ${i + 1}.'),
    ],
  });
  _bible('oshb', 'OSHB', 'he', {
    'Gen': [
      ['{בְּרֵאשִׁית|H7225} {בָּרָא|H1254|HVqp3ms} {אֱלֹהִים|H430} {אֵת|H853}'],
    ],
  }, features: {'helper': true});
  _bible('byz-rp2018', 'RP2018', 'grc', {
    'John': [
      [],
      [],
      List.generate(18, (i) => i == 15 ? '{Οὕτως|G3779} {γὰρ|G1063} {ἠγάπησεν|G25|V-AAI-3S} {ὁ|G3588} {θεὸς|G2316}' : '{Λόγος|G3056}'),
    ],
  }, features: {'helper': true});
  _study('strongs-ru-hebrew', 'dictionary', 'Стронг: иврит', 'ru', {
    'entries': {
      'H1254': {'lemma': 'בָּרָא', 'xlit': 'bara', 'pron': 'бара', 'definition': 'создавать, творить; от H7225 (рэйшит)', 'derivation': 'primitive', 'refs': ['Gen.1.1', 'Gen.1.21']},
      'H7225': {'lemma': 'רֵאשִׁית', 'xlit': 'reshit', 'definition': 'начало'},
      'H430': {'lemma': 'אֱלֹהִים', 'xlit': 'elohim', 'definition': 'Бог, боги'},
    },
  }, extra: {'dictionaryKind': 'strongs', 'license': 'PD'});
  _study('strongs-ru-greek', 'dictionary', 'Стронг: греческий', 'ru', {
    'entries': {
      'G25': {'lemma': 'ἀγαπάω', 'xlit': 'agapao', 'definition': 'любить'},
      'G2316': {'lemma': 'θεός', 'xlit': 'theos', 'definition': 'Бог'},
      'G1063': {'lemma': 'γάρ', 'xlit': 'gar', 'definition': 'ибо'},
    },
  }, extra: {'dictionaryKind': 'strongs', 'license': 'PD'});
  _study('rst-symphony', 'dictionary', 'Симфония RST+', 'ru', {
    'entries': {
      'H1254': {'lemma': 'בָּרָא', 'count': 48, 'renderings': [['сотворил', 30], ['создал', 12], ['произвёл', 6]], 'refs': ['Gen.1.1']},
      'G25': {'lemma': 'ἀγαπάω', 'count': 100, 'renderings': [['возлюбил', 50], ['любит', 50]]},
    },
    'wordIndex': {
      'сотворил': [['H1254', 30]],
      'возлюбил': [['G25', 50]],
    },
  }, extra: {'dictionaryKind': 'symphony'});
  _study('nikifor', 'dictionary', 'Никифор', 'ru', {
    'entries': {
      'бог': {'word': 'Бог', 'text': 'Единый Создатель всего.'},
    },
  });
  _study('xrefs-rst', 'crossrefs', 'Параллельные', 'ru', {
    'refs': {
      'Gen.1.1': ['John.1.1', 'Gen.1.2-3', 'Rom.1.1']
    },
  });
  _study('lopukhin', 'commentary', 'Лопухин', 'ru', {
    'entries': {
      'Gen.1.1': {'title': 'Начало', 'text': 'В начале (см. Ин. 3:16) сотворил Бог.'},
      'Gen.1.2-3': {'title': '', 'text': 'Земля безвидна.'},
      'John.3.16': {'title': 'Любовь', 'text': 'Бог так возлюбил мир.'},
    },
  }, extra: {'author': 'А. П. Лопухин', 'license': 'PD'});
  _study('bible-illustrations', 'illustrations', 'Иллюстрации', 'ru', {
    'entries': {
      'Gen.1.1': [
        {'img': 'https://upload.example/a.jpg', 'title': 'Сотворение', 'author': 'Доре', 'year': '1866', 'license': 'PD', 'src': 'https://example.org/a'},
        {'img': 'https://upload.example/b.jpg', 'title': 'Свет', 'author': 'Доре', 'license': 'PD'},
      ],
    },
  });
}

// --- Окружение ------------------------------------------------------------------------------

const _variants = [('light', 1.0), ('dark', 1.0), ('light', 1.3), ('dark', 1.3)];

Future<ProviderContainer> _pump(WidgetTester tester, Widget Function(BuildContext, WidgetRef) home, {String theme = 'light', double scale = 1.0, ProviderContainer? container}) async {
  tester.view.physicalSize = const Size(400, 830);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = container ?? ProviderContainer();
  c.read(settingsProvider.notifier).set({'theme': theme});
  addTearDown(c.dispose);
  if (_verbose) {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      FlutterError.dumpErrorToConsole(d); // сразу, пока виджеты живы: в итоговом отчёте они уже «DISPOSED»
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
  }
  await tester.pumpWidget(const SizedBox()); // прежнее дерево (и окна в нём) убираем целиком
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: ThemeData(brightness: themes[theme]!.dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Consumer(builder: (context, ref, _) => Scaffold(body: home(context, ref))),
    ),
  ));
  await tester.pump();
  return c;
}

/// Кнопка «открыть» запускает окно; возвращает контейнер
Future<ProviderContainer> _opened(WidgetTester tester, void Function(BuildContext, WidgetRef) open, {String theme = 'light', double scale = 1.0}) async {
  final c = await _pump(tester, (context, ref) => Center(child: TextButton(onPressed: () => open(context, ref), child: const Text('открыть'))), theme: theme, scale: scale);
  await tester.tap(_ft('открыть'));
  await _settle(tester);
  return c;
}

/// pumpAndSettle с запасом на асинхронные загрузки (Future(() async …) в окнах) и запросы к SQLite
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<void> _tapText(WidgetTester tester, String text, {int index = 0}) async {
  final f = _ft(text).evaluate().isNotEmpty ? _ft(text) : _ftc(text);
  expect(f, findsWidgets, reason: 'нет «$text»');
  try {
    await tester.ensureVisible(f.at(index)); // вкладки прокручиваются, если не помещаются
  } catch (_) {}
  await tester.tap(f.at(index), warnIfMissed: false);
  await _settle(tester);
}

/// Все надписи на экране — для сообщений об ошибках
String _texts(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        if ((w.data ?? w.textSpan?.toPlainText() ?? '').isNotEmpty) w.data ?? w.textSpan!.toPlainText(),
    ].join(' | ');

Future<void> _tapTip(WidgetTester tester, String tip) async {
  final f = find.byTooltip(tip);
  expect(f, findsWidgets, reason: 'нет кнопки «$tip»');
  await tester.tap(f.first, warnIfMissed: false);
  await _settle(tester);
}

const _john = VerseRef('John', 3, 16);
const _gen = VerseRef('Gen', 1, 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_qa_bs_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    _buildModules();
    await ModuleStore.initAt(dir);
    await setLang('ru');
    await StudyData.ensure();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    Hub.selectionBar = null;
    Hub.verseDecorators.clear();
    Hub.moreItems.clear();
    Hub.afterStart.clear();
    study.register();
    bm.register();
    // Действия других функций, которых в этом тесте нет
    Hub.listenFrom = (c, r, pane, from) => _log.add('listen');
    Hub.addToSermon = (c, r, refs, m) => _log.add('sermon');
    Hub.openVerseImage = (c, r, refs, m) => _log.add('image');
    _log.clear();
  });

  // =========================== ЗАКЛАДКИ ===========================

  Widget barHost(BuildContext context, WidgetRef ref) => Column(children: [
        buildSelectionBar(context, ref, 0),
        const Expanded(child: SizedBox()),
      ]);

  for (final (theme, scale) in _variants) {
    final v = '$theme x$scale';

    testWidgets('панель выделения, кнопки: $v', (tester) async {
      final c = await _pump(tester, barHost, theme: theme, scale: scale);
      final sel = c.read(selectionProvider.notifier);
      // пусто — только заглушка
      expect(find.byTooltip('Ещё действия'), findsNothing);

      Future<void> select([List<VerseRef> refs = const [_john]]) async {
        for (final r in refs) {
          sel.toggle(0, r);
        }
        await tester.pump();
      }

      // цвета: выбрать второй цвет, потом убрать
      await select();
      expect(_ft('Ин. 3:16'), findsOneWidget);
      await _tapTip(tester, 'Выделить цветом');
      await tester.tapAt(tester.getCenter(find.byTooltip('Убрать выделение')));
      await _settle(tester);
      expect(c.read(marksProvider).highlights, isEmpty);

      await select();
      await _tapTip(tester, 'Выделить цветом');
      await tester.tap(find.byTooltip(t(hlColors[1].name)).first, warnIfMissed: false);
      await _settle(tester);
      expect(c.read(marksProvider).highlights[refKey(_john)], hlColors[1].id);

      // закладка и обратно
      await select();
      await _tapTip(tester, 'Закладка: продолжить отсюда');
      expect(c.read(marksProvider).isBookmarked(_john), true);
      await select();
      await _tapTip(tester, 'Убрать закладку');
      expect(c.read(marksProvider).isBookmarked(_john), false);

      // любимые (кнопка видна на ширине 400)
      await select();
      await _tapTip(tester, 'В любимые');
      expect(c.read(marksProvider).isFavorite(_john), true);
      await select();
      await _tapTip(tester, 'Убрать из любимых');
      expect(c.read(marksProvider).isFavorite(_john), false);

      // «Читать параллельно»: два перевода кроме открытого — одна кнопка открывает вторую панель сразу
      await select();
      await _tapTip(tester, 'Читать параллельно');
      expect(c.read(panesProvider).length, 2);

      // много стихов: подпись и счётчик
      await select([_john, const VerseRef('John', 3, 17), const VerseRef('John', 3, 18)]);
      expect(_ft('3'), findsWidgets);
      sel.clear(0);
      await tester.pump();

      // заметка из панели
      await select();
      await _tapTip(tester, 'Добавить заметку');
      expect(_ft('Новая заметка'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Моя мысль о Ин 3:16');
      await _tapText(tester, 'Сохранить');
      expect(c.read(marksProvider).noteOf(_john)!['text'], 'Моя мысль о Ин 3:16');
      expect(_ft('Новая заметка'), findsNothing);
    });

    testWidgets('панель выделения, меню «Ещё»: $v', (tester) async {
      final c = await _pump(tester, barHost, theme: theme, scale: scale);
      final sel = c.read(selectionProvider.notifier);
      Future<void> more(String item, {List<VerseRef> refs = const [_john]}) async {
        for (final r in refs) {
          sel.toggle(0, r);
        }
        await tester.pump();
        await _tapTip(tester, 'Ещё действия');
        await _tapText(tester, item);
        // окно, открытое из меню, закрываем «назад»/крестиком
        for (var i = 0; i < 3 && find.byType(BackButton).evaluate().isEmpty && find.byTooltip('Закрыть').evaluate().isNotEmpty; i++) {
          await tester.tap(find.byTooltip('Закрыть').first, warnIfMissed: false);
          await _settle(tester);
        }
        c.read(selectionProvider.notifier).clear(0);
        await tester.pump();
      }

      await more('Подстрочник');
      await more('Всё о стихе', refs: const [_gen]);
      await more('В проповедь');
      expect(_log, contains('sermon'));
      await more('В любимые');
      expect(c.read(marksProvider).isFavorite(_john), true);
      await more('Сравнить переводы');
      await more('Параллельные места', refs: const [_gen]);
      await more('Слушать отсюда');
      expect(_log, contains('listen'));
      await more('Картинка со стихом');
      expect(_log, contains('image'));
      await more('Копировать');
      await more('Поделиться'); // плагина в тесте нет: ловим исключение и копируем текст
      // много стихов: «Параллельные места» скрыты
      sel
        ..toggle(0, _john)
        ..toggle(0, const VerseRef('John', 3, 17));
      await tester.pump();
      await _tapTip(tester, 'Ещё действия');
      expect(_ft('Параллельные места'), findsNothing);
      expect(_ft('Подстрочник'), findsOneWidget);
      await tester.tapAt(const Offset(5, 700));
      await _settle(tester);
      sel.clear(0);
      await tester.pump();

      // «В подборку…» — новая подборка, потом добавление в существующую
      sel.toggle(0, _john);
      await tester.pump();
      await _tapTip(tester, 'Ещё действия');
      await _tapText(tester, 'В подборку…');
      expect(_ft('В подборку'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'К уроку');
      await tester.pump();
      await _tapTip(tester, 'Создать подборку');
      expect(c.read(marksProvider).collections.single['name'], 'К уроку');
    });

    testWidgets('строка под выделенным стихом: $v', (tester) async {
      var done = 0, part = 0;
      await _pump(
          tester,
          (context, ref) => Padding(
                padding: const EdgeInsets.all(16),
                child: buildSelectionInline(context, ref, pane: 0, moduleId: 'rst-plus', refs: const [_john], onDone: () => done++, onPart: () => part++),
              ),
          theme: theme,
          scale: scale);
      await _tapText(tester, 'Часть стиха');
      expect(part, 1);
      await _tapText(tester, 'В проповедь');
      await _tapTip(tester, 'Слушать');
      expect(done, 2);
      await _tapText(tester, 'Подстрочник');
      expect(find.byType(InterlinearSheet), findsOneWidget);
    });

    testWidgets('заметка и подборки: $v', (tester) async {
      // заметка: новая → сохранить → открыть снова → удалить с подтверждением
      final c = await _opened(tester, (context, ref) => showNoteSheet(context, const [_john], 'rst-plus'), theme: theme, scale: scale);
      expect(_ftc('возлюбил'), findsWidgets); // цитата стиха в окне
      await tester.enterText(find.byType(TextField), 'Строка 1\nСтрока 2');
      await _tapText(tester, 'Сохранить');
      expect(c.read(marksProvider).noteOf(_john)!['text'], 'Строка 1\nСтрока 2');
      await tester.tap(_ft('открыть'));
      await _settle(tester);
      expect(_ft('Заметка'), findsWidgets);
      expect(_ftc('Создана'), findsOneWidget);
      await _tapText(tester, 'Удалить'); // первое нажатие — «Удалить / Отмена»
      await _tapText(tester, 'Отмена');
      expect(c.read(marksProvider).noteOf(_john), isNotNull);
      await _tapText(tester, 'Удалить');
      await _tapText(tester, 'Удалить', index: 0);
      expect(c.read(marksProvider).noteOf(_john), isNull);

      // подборка
      final c2 = await _opened(tester, (context, ref) => showCollectSheet(context, const [_john], 'rst-plus'), theme: theme, scale: scale);
      await tester.enterText(find.byType(TextField), 'Утешение');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(c2.read(marksProvider).collections.single['name'], 'Утешение');
      final id = c2.read(marksProvider).collections.single['id'] as String;
      await tester.tap(_ft('открыть'));
      await _settle(tester);
      expect(_ft('Утешение'), findsOneWidget);
      await _tapText(tester, 'Утешение');
      expect(((c2.read(marksProvider).collections.single['items']) as List).length, 1);
      expect(c2.read(marksProvider).collections.single['id'], id);
    });

    testWidgets('«Закладки и заметки», все вкладки: $v', (tester) async {
      // данные во всех разделах
      final seed = ProviderContainer();
      final n = seed.read(marksProvider.notifier);
      n.toggleBookmark(_john, 'Ибо так возлюбил Бог мир');
      n.toggleBookmark(_gen, 'В начале сотворил Бог');
      n.setFavorites([(_john, 'Так возлюбил'), (_gen, 'В начале')], true);
      for (var i = 1; i <= 5; i++) {
        n.setNote(VerseRef('John', 3, i), 'Заметка $i с довольно длинным текстом, чтобы строка переносилась на вторую и на третью строки экрана', 'Ин. 3:$i');
      }
      n.setHighlight([_john, _gen, const VerseRef('John', 3, 17)], '1');
      n.setHighlight([const VerseRef('John', 3, 18)], '3');
      n.addToCollection(null, [
        {'book': 'John', 'chapter': 3, 'verse': 16, 'text': 'Так возлюбил'},
        {'book': 'Gen', 'chapter': 1, 'verse': 1, 'text': 'В начале'}
      ], 'К уроку', 'Подборка');
      seed.dispose();

      final c = await _opened(tester, (context, ref) => openBookmarksPage(context, ref, 0), theme: theme, scale: scale);
      expect(_ft('Закладки и заметки'), findsOneWidget);
      expect(_ft('Продолжить чтение'), findsOneWidget);

      // закладки: смахивание влево, отмена
      expect(c.read(marksProvider).bookmarks.length, 2);
      await tester.drag(_ftc('Иоанн').first, const Offset(-300, 0));
      await _settle(tester);
      expect(c.read(marksProvider).bookmarks.length, 1);
      await _tapText(tester, 'Отменить');
      expect(c.read(marksProvider).bookmarks.length, 2);
      // кнопкой
      await _tapTip(tester, 'Удалить закладку');
      expect(c.read(marksProvider).bookmarks.length, 1);

      // любимые
      await _tapText(tester, 'Любимые стихи');
      expect(_ft('Так возлюбил'), findsOneWidget);
      await _tapTip(tester, 'Убрать из любимых');
      expect(c.read(marksProvider).favorites.length, 1);
      await _tapText(tester, 'Отменить');
      expect(c.read(marksProvider).favorites.length, 2);

      // заметки: поиск (>3 заметок), изменение, смахивание
      await _tapText(tester, 'Заметки');
      await tester.enterText(find.byType(TextField).first, 'заметка 2');
      await tester.pump();
      expect(_ftc('Заметка 2'), findsWidgets);
      expect(_ftc('Заметка 4'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await _tapTip(tester, 'Изменить заметку');
      expect(_ft('Заметка'), findsWidgets);
      await _tapText(tester, 'Сохранить');
      await tester.drag(_ftc('Заметка 5').first, const Offset(-300, 0));
      await _settle(tester);
      expect(c.read(marksProvider).notes.length, 4);
      await _tapText(tester, 'Отменить');
      expect(c.read(marksProvider).notes.length, 5);

      // выделения: фильтр по цвету, убрать, вернуть
      await _tapText(tester, 'Выделения');
      expect(_ft('Все'), findsOneWidget);
      final chip = _ft(t(hlColor('3')!.name));
      expect(chip, findsOneWidget);
      await tester.tap(chip, warnIfMissed: false);
      await _settle(tester);
      expect(_ftc('Иоанна 3:18'), findsWidgets);
      await _tapText(tester, 'Все');
      await _tapTip(tester, 'Убрать выделение');
      expect(c.read(marksProvider).highlights.length, 3);
      await _tapText(tester, 'Отменить');
      expect(c.read(marksProvider).highlights.length, 4);

      // подборки: внутрь, назад, удаление подборки с возвратом
      await _tapText(tester, 'Подборки');
      await _tapText(tester, 'К уроку');
      expect(_ft('Все подборки'), findsOneWidget);
      await _tapTip(tester, 'Убрать из подборки');
      await _tapText(tester, 'Отменить');
      await _tapText(tester, 'Все подборки');
      await tester.drag(_ft('К уроку'), const Offset(-300, 0));
      await _settle(tester);
      expect(c.read(marksProvider).collections, isEmpty);
      expect(_ft('Подборок пока нет'), findsOneWidget);
      await _tapText(tester, 'Отменить');
      expect(c.read(marksProvider).collections.length, 1);

      // свайп по содержимому между вкладками
      await tester.drag(find.byType(TabBarView), const Offset(300, 0));
      await _settle(tester);
      // переход к стиху закрывает окно
      await _tapText(tester, 'Закладки 1'); // подпись вкладки с числом (просто «Закладки» совпало бы с заголовком окна)
      expect(_ftc('Продолжить чтение'), findsOneWidget, reason: _texts(tester));
      await _tapText(tester, 'Продолжить чтение');
      expect(_ft('Закладки и заметки'), findsNothing);
    });

    testWidgets('«Закладки и заметки», пустые вкладки: $v', (tester) async {
      await _opened(tester, (context, ref) => openBookmarksPage(context, ref, 0), theme: theme, scale: scale);
      for (final (tab, empty) in [
        ('Закладки', 'Закладок пока нет'),
        ('Любимые стихи', 'Любимых стихов пока нет'),
        ('Заметки', 'Заметок пока нет'),
        ('Выделения', 'Выделений пока нет'),
        ('Подборки', 'Подборок пока нет'),
      ]) {
        await _tapText(tester, tab);
        expect(_ft(empty), findsOneWidget, reason: tab);
      }
    });

    testWidgets('«Мои данные»: $v', (tester) async {
      // резервная копия в prefs — как её пишет обновление
      prefs.setString('backups', jsonEncode([
        {'at': DateTime(2026, 10, 1, 12, 5).millisecondsSinceEpoch, 'reason': 'до обновления с версии 1.0', 'data': {'bookmarks': [{}], 'notes': {}, 'favorites': []}},
      ]));
      final c = await _opened(tester, (context, ref) => openMyData(context, ref, 0), theme: theme, scale: scale);
      expect(_ft('Мои данные'), findsWidgets);
      await _tapText(tester, 'Сохранить в файл'); // плагинов в тесте нет — окно показывает ошибку, но не падает
      await _tapText(tester, 'Восстановить из файла');
      expect(find.byType(MyDataPage), findsOneWidget);
      final bk = _ft('Восстановить эту копию');
      if (bk.evaluate().isNotEmpty) {
        await _tapText(tester, 'Восстановить эту копию');
        await _tapText(tester, 'Отмена');
        await _tapText(tester, 'Восстановить эту копию');
        await _tapText(tester, 'Восстановить');
      }
      expect(c.read(settingsProvider), isNotNull);
    });
  }

  // =========================== ИЗУЧЕНИЕ ===========================

  for (final (theme, scale) in _variants) {
    final v = '$theme x$scale';

    testWidgets('статья Стронга, «Все места», словари: $v', (tester) async {
      // точная привязка: сотворил -> H1254, с подстрочной формой
      await _opened(
          tester,
          (context, ref) => openDictionary(
              context,
              const DictRequest(text: 'сотворил', strongs: ['H1254', 'H853'], morph: ['TH8804'], ref: _gen, pane: 0, wordIndex: 1, autoOpen: true),
              full: true),
          theme: theme,
          scale: scale);
      expect(_ftc('H1254'), findsWidgets);
      expect(_ftc('создавать'), findsWidgets);
      // ссылка внутри статьи (H7225)
      final link = _ftc('H7225');
      if (link.evaluate().isNotEmpty) await tester.tap(link.first, warnIfMissed: false);
      await _settle(tester);
      // «Все места»
      final all = _ftc('Все места');
      if (all.evaluate().isNotEmpty) {
        await tester.tap(all.first, warnIfMissed: false);
        await _settle(tester);
      }
      // список словарей и слово без разметки
      await _opened(
          tester,
          (context, ref) => openDictionary(context, const DictRequest(text: 'Бога', strongs: [], morph: [], ref: _gen, pane: 0)),
          theme: theme,
          scale: scale);
      expect(find.byType(DictionarySheet), findsOneWidget);
      // слово, которого нет нигде
      await _opened(tester, (context, ref) => openDictionary(context, const DictRequest(text: 'абракадабра', strongs: [], morph: [], ref: _gen, pane: 0)), theme: theme, scale: scale);
    });

    testWidgets('«Все места» Стронга: $v', (tester) async {
      await _opened(tester, (context, ref) => openConcordance(context, num: 'H1254', lemma: 'בָּרָא', onOpen: (r) {}), theme: theme, scale: scale);
      expect(find.byType(ConcordanceSheet), findsOneWidget);
      expect(_ftc('сотворил'), findsWidgets);
      await _tapText(tester, 'сотворил');
      // номер без употреблений
      await _opened(tester, (context, ref) => openConcordance(context, num: 'H9999', onOpen: (r) {}), theme: theme, scale: scale);
    });

    testWidgets('подстрочник, все виды: $v', (tester) async {
      await _opened(tester, (context, ref) => openInterlinearSheet(context, ref, _john, 'rst-plus'), theme: theme, scale: scale);
      expect(find.byType(InterlinearSheet), findsOneWidget);
      // вкладки и переключатели, какие есть
      for (final label in ['Порядок оригинала', 'Порядок синодального', 'Оригинал', 'Синодальный']) {
        final f = _ftc(label);
        if (f.evaluate().isNotEmpty) await tester.tap(f.first, warnIfMissed: false);
        await _settle(tester);
      }
      // слово оригинала → статья
      final w = _ftc('возлюбил');
      if (w.evaluate().isNotEmpty) {
        await tester.tap(w.first, warnIfMissed: false);
        await _settle(tester);
      }
      // Ветхий Завет
      await _opened(tester, (context, ref) => openInterlinearSheet(context, ref, _gen, 'rst-plus'), theme: theme, scale: scale);
      expect(find.byType(InterlinearSheet), findsOneWidget);
      // стих без оригинала
      await _opened(tester, (context, ref) => openInterlinearSheet(context, ref, const VerseRef('Rom', 1, 1), 'rst-plus'), theme: theme, scale: scale);
    });

    testWidgets('параллельные места: $v', (tester) async {
      await _opened(tester, (context, ref) => openXrefs(context, pane: 0, moduleId: 'rst-plus', at: _gen), theme: theme, scale: scale);
      expect(find.byType(XrefsSheet), findsOneWidget);
      expect(_ftc('От Иоанна 1:1'), findsWidgets, reason: _texts(tester));
      // у стиха нет ссылок
      await _opened(tester, (context, ref) => openXrefs(context, pane: 1, moduleId: 'rst-plus', at: const VerseRef('Rom', 1, 1)), theme: theme, scale: scale);
      expect(_ft('Параллельных мест нет'), findsOneWidget);
      // нажатие на ссылку открывает место во второй панели
      final c = await _opened(tester, (context, ref) => openXrefs(context, pane: 0, moduleId: 'rst-plus', at: _gen), theme: theme, scale: scale);
      final row = _ftc('Ин. 1:1');
      if (row.evaluate().isNotEmpty) {
        await tester.tap(row.first, warnIfMissed: false);
        await _settle(tester);
        expect(c.read(panesProvider).length, 2);
      }
    });

    testWidgets('комментарии: $v', (tester) async {
      await _opened(tester, (context, ref) => openCommentary(context, pane: 0, at: _gen), theme: theme, scale: scale);
      expect(_ftc('безвидна').evaluate().isEmpty && _ftc('сотворил').evaluate().isEmpty, false);
      expect(_ftc('Лопухин'), findsWidgets);
      // ссылка внутри текста «Ин. 3:16»
      final link = _ftc('Ин. 3:16');
      if (link.evaluate().isNotEmpty) {
        await tester.tap(link.first, warnIfMissed: false);
        await _settle(tester);
      }
      await _opened(tester, (context, ref) => openCommentary(context, pane: 0, at: const VerseRef('Rom', 1, 1)), theme: theme, scale: scale);
      expect(_ft('Комментариев к этому стиху нет'), findsOneWidget, reason: _texts(tester));
    });

    testWidgets('сравнение переводов: $v', (tester) async {
      await _opened(tester, (context, ref) => openCompare(context, ref, const [_john, VerseRef('John', 3, 17)], 'rst-plus'), theme: theme, scale: scale);
      expect(find.byType(CompareSheet), findsOneWidget);
      expect(_ft('KJV'), findsWidgets);
      final par = _ftc('Параллельно');
      if (par.evaluate().isNotEmpty) {
        await tester.tap(par.first, warnIfMissed: false);
        await _settle(tester);
      }
      final lang = _ft('English');
      if (lang.evaluate().isNotEmpty) await _tapText(tester, 'English');
    });

    testWidgets('«Всё о стихе»: $v', (tester) async {
      final seed = ProviderContainer();
      seed.read(marksProvider.notifier)
        ..setNote(_gen, 'Моя заметка', 'Быт. 1:1')
        ..setHighlight([_gen], '2')
        ..addToCollection(null, [
          {'book': 'Gen', 'chapter': 1, 'verse': 1, 'text': 'x'}
        ], 'Начало', 'Подборка');
      seed.dispose();
      await _opened(tester, (context, ref) => openVerseGuide(context, ref, 0, _gen, 'rst-plus'), theme: theme, scale: scale);
      expect(_ftc('Ваши пометки'), findsOneWidget);
      expect(_ftc('Комментарии'), findsWidgets);
      expect(_ftc('Параллельные места'), findsWidgets);
      // карточка слова → статья
      final w = _ftc('H1254');
      if (w.evaluate().isNotEmpty) {
        await tester.tap(w.first, warnIfMissed: false);
        await _settle(tester);
      }
      await _opened(tester, (context, ref) => openVerseGuide(context, ref, 0, const VerseRef('Rom', 1, 1), 'rst-plus'), theme: theme, scale: scale);
    });

    testWidgets('просмотр картинки: $v', (tester) async {
      final items = StudyData.illustrationsFor(_gen);
      expect(items.length, 2);
      await _opened(tester, (context, ref) => openImageViewer(context, at: _gen, items: items), theme: theme, scale: scale);
      expect(_ft('1 из 2'), findsOneWidget);
      await _tapTip(tester, 'Следующая картинка');
      expect(_ft('2 из 2'), findsOneWidget);
      await _tapTip(tester, 'Предыдущая картинка');
      await _tapTip(tester, 'Увеличить');
      await _tapTip(tester, 'Уменьшить');
      // нажатие — увеличить в точке, ещё раз — вернуть
      final box = find.byType(Listener).first;
      await tester.tap(box, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      // смахивание вниз закрывает
      await tester.drag(box, const Offset(0, 300));
      await _settle(tester);
    });

    testWidgets('выборка над словом: $v', (tester) async {
      Rect? anchor;
      await _pump(
          tester,
          (context, ref) => Center(
                child: GestureDetector(
                  onTap: () {
                    final box = context.findRenderObject() as RenderBox;
                    anchor = box.localToGlobal(Offset.zero) & box.size;
                    final text = _gen;
                    final raw = StudyData.verse('rst-plus', text)!;
                    final toks = parseVerse(raw);
                    final idx = toks.indexWhere((x) => x.text == 'сотворил') - 1;
                    Hub.onWordTap!(context, ref, WordTap(pane: 0, moduleId: 'rst-plus', ref: text, token: toks[idx + 1], tokenIndex: idx + 1, rect: const Rect.fromLTWH(180, 300, 60, 24), verseText: raw));
                  },
                  child: const Text('слово'),
                ),
              ),
          theme: theme,
          scale: scale);
      await tester.tap(_ft('слово'));
      await _settle(tester);
      expect(anchor, isNotNull);
      // выбор строки открывает статью
      final row = _ftc('H1254');
      expect(row, findsWidgets, reason: _texts(tester));
      await tester.tap(row.first);
      await _settle(tester);
      expect(find.byType(DictionarySheet), findsOneWidget);
    });

    testWidgets('выборка над словом без разметки и на краю: $v', (tester) async {
      await _pump(
          tester,
          (context, ref) => Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  onTap: () {
                    final raw = StudyData.verse('rst-plus', const VerseRef('Rom', 1, 1))!;
                    final toks = parseVerse(raw);
                    Hub.onWordTap!(context, ref, WordTap(pane: 0, moduleId: 'rst-plus', ref: const VerseRef('Rom', 1, 1), token: toks.first, tokenIndex: 0, rect: const Rect.fromLTWH(370, 800, 30, 24), verseText: raw));
                  },
                  child: const Text('слово'),
                ),
              ),
          theme: theme,
          scale: scale);
      await tester.tap(_ft('слово'));
      await _settle(tester);
    });
  }
}

final _log = <String>[];

// Подписи вкладок и ссылки — составной текст (Text.rich): ищем и в нём
Finder _ft(String s) => find.text(s, findRichText: true);
Finder _ftc(String s) => find.textContaining(s, findRichText: true);

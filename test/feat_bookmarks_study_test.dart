// Сценарные проверки доработок «Закладок» и «Изучения» (жесты читалки, «Часть стиха», номер Стронга, «История»,
// ссылки в заметке, «Читать параллельно», копия при обновлении, «Мои данные», пункты «Ещё»).
// Поверхность 400×830, светлая и тёмная тема; любое исключение Flutter роняет тест (flutter_test проверяет сам).
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/bible.dart';
import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/markup.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/bookmarks/bookmarks.dart' as bm;
import 'package:aobible/features/bookmarks/decor.dart';
import 'package:aobible/features/bookmarks/gestures.dart';
import 'package:aobible/features/bookmarks/manager.dart';
import 'package:aobible/features/bookmarks/marks.dart';
import 'package:aobible/features/bookmarks/selection_bar.dart';
import 'package:aobible/features/bookmarks/sheets.dart';
import 'package:aobible/features/bookmarks/userdata.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/features/shell/shell.dart' show appVersion;
import 'package:aobible/features/study/compare_sheet.dart';
import 'package:aobible/features/study/dictionary_sheet.dart';
import 'package:aobible/features/study/study.dart' as study;
import 'package:aobible/features/study/study_data.dart';
import 'package:aobible/features/study/study_tables.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

void _meta(Database db, Map<String, dynamic> meta) {
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode(meta)]);
}

void _bible(String id, String name, String lang, Map<String, List<List<String>>> books, {Map<String, dynamic> features = const {}}) {
  final db = sqlite3.open('${dir.path}/$id.db');
  _meta(db, {'id': id, 'type': 'bible', 'name': name, 'title': 'Тест $name', 'language': lang, 'features': features, 'catalogVersion': '1', 'bookList': [for (final b in books.keys) {'id': b, 'name': b, 'short': b, 'chapters': books[b]!.length}]});
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
  db.close();
}

void _dict(String id, String name, Map<String, dynamic> entries) {
  final db = sqlite3.open('${dir.path}/$id.db');
  final j = {'id': id, 'type': 'dictionary', 'name': name, 'title': 'Тест $name', 'language': 'ru', 'catalogVersion': '1', 'dictionaryKind': 'strongs', 'license': 'PD', 'entries': entries};
  _meta(db, {...j}..remove('entries'));
  buildStudyTables(db, j, 'dictionary');
  db.close();
}

const _jn316 = '{Ибо|G1063} так {возлюбил|G25|V-AAI-3S} {Бог|G2316} мир, что отдал Сына Своего Единородного';
const _gen1 = '{В начале|H7225} {сотворил|H1254 H853|TH8804} {Бог|H430} небо и землю.';

const _variants = [('light', 1.0), ('dark', 1.0), ('light', 1.3), ('dark', 1.3)];
const _john = VerseRef('John', 3, 16);
const _gen = VerseRef('Gen', 1, 1);

Finder _ft(String s) => find.text(s, findRichText: true);
Finder _ftc(String s) => find.textContaining(s, findRichText: true);

Future<ProviderContainer> _pump(WidgetTester tester, Widget Function(BuildContext, WidgetRef) home, {String theme = 'light', double scale = 1.0}) async {
  tester.view.physicalSize = const Size(400, 830);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer();
  c.read(settingsProvider.notifier).set({'theme': theme});
  addTearDown(c.dispose);
  await tester.pumpWidget(const SizedBox());
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<ProviderContainer> _opened(WidgetTester tester, void Function(BuildContext, WidgetRef) open, {String theme = 'light', double scale = 1.0}) async {
  final c = await _pump(tester, (context, ref) => Center(child: TextButton(onPressed: () => open(context, ref), child: const Text('открыть'))), theme: theme, scale: scale);
  await tester.tap(_ft('открыть'));
  await _settle(tester);
  return c;
}

Future<void> _tapText(WidgetTester tester, String text, {int index = 0}) async {
  final f = _ft(text).evaluate().isNotEmpty ? _ft(text) : _ftc(text);
  expect(f, findsWidgets, reason: 'нет «$text»');
  try {
    await tester.ensureVisible(f.at(index));
  } catch (_) {}
  await tester.tap(f.at(index), warnIfMissed: false);
  await _settle(tester);
}

String _texts(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        if ((w.data ?? w.textSpan?.toPlainText() ?? '').isNotEmpty) w.data ?? w.textSpan!.toPlainText(),
    ].join(' | ');

/// Нажать ссылку внутри Text.rich по её тексту (у ссылок свои TapGestureRecognizer)
bool _tapSpan(WidgetTester tester, String text) {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final root = w.textSpan;
    if (root == null) continue;
    var hit = false;
    root.visitChildren((s) {
      if (s is TextSpan && s.text == text && s.recognizer is TapGestureRecognizer) {
        (s.recognizer as TapGestureRecognizer).onTap!();
        hit = true;
        return false;
      }
      return true;
    });
    if (hit) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
    dir = Directory('${Directory.systemTemp.path}/aob_feat_bs_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    _bible('rst-plus', 'RST+', 'ru', {
      'Gen': [
        [_gen1, 'Земля же была безвидна и пуста.', 'И сказал Бог: да будет свет.']
      ],
      'John': [
        [],
        [],
        List.generate(18, (i) => i == 15 ? _jn316 : 'Стих номер ${i + 1}.'),
      ],
    }, features: {'strongs': true});
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
    _bible('nrt', 'NRT', 'ru', {
      'Gen': [
        ['В начале Бог сотворил небо и землю.', 'Земля была пуста.', 'Бог сказал: да будет свет.']
      ],
      'John': [
        [],
        [],
        List.generate(18, (i) => i == 15 ? 'Так Бог полюбил мир.' : 'Стих ${i + 1}.'),
      ],
    });
    _dict('strongs-ru-hebrew', 'Стронг: иврит', {
      'H1254': {'lemma': 'בָּרָא', 'xlit': 'bara', 'definition': 'создавать, творить'},
      'H7225': {'lemma': 'רֵאשִׁית', 'xlit': 'reshit', 'definition': 'начало'},
      'H430': {'lemma': 'אֱלֹהִים', 'xlit': 'elohim', 'definition': 'Бог, боги'},
    });
    _dict('strongs-ru-greek', 'Стронг: греческий', {
      'G25': {'lemma': 'ἀγαπάω', 'xlit': 'agapao', 'definition': 'любить'},
      'G2316': {'lemma': 'θεός', 'xlit': 'theos', 'definition': 'Бог'},
      'G1063': {'lemma': 'γάρ', 'xlit': 'gar', 'definition': 'ибо'},
    });
    await ModuleStore.initAt(dir);
    await setLang('ru');
    await StudyData.ensure();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    Hub.reset();
    Hub.afterStart.clear();
    livePositions.clear();
    readerMarks.value = {};
    activeWord.value = null;
    partSelection.value = null;
    SyncHub.driver = 0;
    study.register();
    bm.register();
    Hub.listenFrom = (c, r, pane, from) {};
    Hub.addToSermon = (c, r, refs, m) {};
  });

  test('register подключает все точки', () {
    expect(Hub.onVerseDoubleTap, isNotNull);
    expect(Hub.addFavoritePart, isNotNull);
    expect(Hub.openStrong, isNotNull);
    final ids = Hub.moreItems.map((x) => x.id).toList();
    expect(ids, containsAll(['bookmark-here', 'bookmark-off', 'bookmark-last', 'mydata']));
    // register можно звать повторно (смена языка): задания запуска не дублируются
    bm.register();
    expect(Hub.afterStart.where((f) => f == bootBackup).length, 1);
  });

  // =========================== жесты и «Часть стиха» ===========================

  for (final (theme, scale) in _variants) {
    final v = '$theme x$scale';

    testWidgets('двойное касание: в любимые и обратно, вспышка: $v', (tester) async {
      late WidgetRef wref;
      late BuildContext ctx;
      final c = await _pump(tester, (context, ref) {
        wref = ref;
        ctx = context;
        return const SizedBox();
      }, theme: theme, scale: scale);
      activeWord.value = (pane: 0, ref: _john, token: 1);
      Hub.onVerseDoubleTap!(ctx, wref, 0, _john, 'rst-plus');
      expect(c.read(marksProvider).isFavorite(_john), isTrue);
      expect(jsonDecode(prefs.getString('favorites')!).single['text'], contains('возлюбил'));
      expect(activeWord.value, isNull, reason: 'подсветка слова снимается');
      // вспышка: фон стиха любимого — розовее обычного, потом гаснет
      expect(favPulse['John.3.16'], 0.3);
      final item = ReaderItem.verse(3, 16, _jn316);
      final d0 = verseDecor(ctx, wref, 0, 'rst-plus', item, 'John')!;
      expect(d0.background!.a, greaterThan(0.25));
      await tester.pump(const Duration(milliseconds: 900));
      expect(favPulse, isEmpty);
      expect(verseDecor(ctx, wref, 0, 'rst-plus', item, 'John')!.background!.a, lessThan(0.15));
      // второе двойное касание — убрать
      Hub.onVerseDoubleTap!(ctx, wref, 0, _john, 'rst-plus');
      expect(c.read(marksProvider).isFavorite(_john), isFalse);
      await tester.pump(const Duration(milliseconds: 900));
      expect(favPulse, isEmpty);
    });

    testWidgets('«Часть стиха»: кнопка и любимая часть: $v', (tester) async {
      late BuildContext ctx;
      late WidgetRef wref;
      final c = await _pump(tester, (context, ref) {
        ctx = context;
        wref = ref;
        final sel = ref.watch(selectionProvider);
        final item = ReaderItem.verse(3, 16, _jn316);
        final d = sel[0]?.isNotEmpty == true ? verseDecor(context, ref, 0, 'rst-plus', item, 'John') : null;
        return Padding(padding: const EdgeInsets.all(16), child: d?.below ?? const SizedBox());
      }, theme: theme, scale: scale);
      c.read(selectionProvider.notifier).toggle(0, _john);
      await tester.pump();
      await tester.tap(_ft('Часть стиха'));
      await tester.pump();
      final p = partSelection.value!;
      expect((p.pane, p.ref, p.moduleId, p.from, p.to), (0, _john, 'rst-plus', null, null));
      expect(c.read(selectionProvider)[0], isEmpty, reason: 'выделение снято, выбор слов ведёт читалка');

      // читалка выбрала слова 1..3 — «в любимые»
      Hub.addFavoritePart!(ctx, wref, _john, 'rst-plus', 3, 1, 'так возлюбил Бог');
      final f = jsonDecode(prefs.getString('favorites')!).single as Map;
      expect(f['part'], {'from': 1, 'to': 3});
      expect(f['text'], 'так возлюбил Бог');
      final item = ReaderItem.verse(3, 16, _jn316);
      expect(verseDecor(ctx, wref, 0, 'rst-plus', item, 'John')!.parts, [(1, 3)]);
      expect(c.read(marksProvider).flags['John.3.16'], contains('p'));
      // новая часть заменяет прежнюю отметку стиха
      Hub.addFavoritePart!(ctx, wref, _john, 'rst-plus', 0, 0, 'Ибо');
      expect(jsonDecode(prefs.getString('favorites')!), hasLength(1));
      expect(verseDecor(ctx, wref, 0, 'rst-plus', item, 'John')!.parts, [(0, 0)]);
    });

    testWidgets('номер Стронга: статья на всю высоту: $v', (tester) async {
      await _opened(tester, (context, ref) => Hub.openStrong!(context, ref, 0, _john, 'G25'), theme: theme, scale: scale);
      expect(find.byType(DictionarySheet), findsOneWidget);
      expect(_ftc('любить'), findsWidgets, reason: _texts(tester));
      // на всю высоту: окно занимает почти весь экран
      expect(tester.getTopLeft(find.byType(DictionarySheet)).dy, lessThan(40));
    });

    testWidgets('выборка над словом: подсветка и закрытие касанием: $v', (tester) async {
      final raw = StudyData.verse('rst-plus', _gen)!;
      final toks = parseVerse(raw);
      final idx = toks.indexWhere((x) => x.text == 'сотворил');
      await _pump(
          tester,
          (context, ref) => Center(
                child: TextButton(
                  onPressed: () => Hub.onWordTap!(context, ref, WordTap(pane: 0, moduleId: 'rst-plus', ref: _gen, token: toks[idx], tokenIndex: idx, rect: const Rect.fromLTWH(180, 300, 60, 24), verseText: raw)),
                  child: const Text('слово'),
                ),
              ),
          theme: theme,
          scale: scale);
      await tester.tap(_ft('слово'));
      await _settle(tester);
      expect(activeWord.value, (pane: 0, ref: _gen, token: idx));
      // касание там, где слово, при открытой выборке только закрывает её
      await tester.tapAt(const Offset(210, 312));
      await _settle(tester);
      expect(activeWord.value, isNull);
      expect(_ftc('H1254'), findsNothing, reason: 'выборка заново не открылась');
      // выбор строки: слово остаётся подсвеченным, пока открыта статья
      await tester.tap(_ft('слово'));
      await _settle(tester);
      await tester.tap(_ftc('H1254').first);
      await _settle(tester);
      expect(find.byType(DictionarySheet), findsOneWidget);
      expect(activeWord.value, isNotNull);
      await tester.tap(find.byTooltip('Закрыть').first);
      await _settle(tester);
      expect(find.byType(DictionarySheet), findsNothing);
      expect(activeWord.value, isNull);
    });

    testWidgets('«История» переходов: $v', (tester) async {
      final c = await _opened(tester, (context, ref) => openBookmarksPage(context, ref, 0), theme: theme, scale: scale);
      final n = c.read(panesProvider.notifier);
      n.navigate(0, _john);
      n.navigate(0, const VerseRef('Gen', 1, 2));
      await _settle(tester);
      expect(c.read(panesProvider)[0].history.length, 3);
      await _tapText(tester, 'История');
      expect(_ftc('Бытие 1:2'), findsWidgets, reason: _texts(tester));
      expect(_ft('сейчас'), findsOneWidget);
      expect(_ftc('Иоанна 3:16'), findsWidgets);
      await _tapText(tester, 'Иоанна 3:16');
      // переход назад на один шаг по истории, окно закрыто
      expect(c.read(panesProvider)[0].hIndex, 1);
      expect(c.read(panesProvider)[0].ref, _john);
      expect(find.byType(BookmarksPage), findsNothing);
    });

    testWidgets('ссылки в тексте заметки: $v', (tester) async {
      final c = await _opened(tester, (context, ref) => showNoteSheet(context, const [_gen], 'rst-plus', pane: 0), theme: theme, scale: scale);
      // без ссылок — предпросмотра нет
      await tester.enterText(find.byType(TextField), 'Просто мысль');
      await tester.pump();
      expect(_tapSpan(tester, 'Ин 3:16'), isFalse);
      await tester.enterText(find.byType(TextField), 'Сравни: Ин 3:16 и ещё');
      await tester.pump();
      expect(_tapSpan(tester, 'Ин 3:16'), isTrue);
      await _settle(tester);
      // заметка сохранена, место открыто во второй панели, окно закрыто
      expect(c.read(marksProvider).noteOf(_gen)!['text'], 'Сравни: Ин 3:16 и ещё');
      expect(c.read(panesProvider).length, 2);
      expect(c.read(panesProvider)[1].ref, _john);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('«Читать параллельно» при нескольких переводах: $v', (tester) async {
      Hub.compareTranslations = (c, r, refs, m) => fail('вместо выбора открылось обычное сравнение');
      final c = await _pump(tester, (context, ref) => Column(children: [buildSelectionBar(context, ref, 0), const Expanded(child: SizedBox())]), theme: theme, scale: scale);
      c.read(selectionProvider.notifier).toggle(0, _john);
      await tester.pump();
      await tester.tap(find.byTooltip('Читать параллельно'));
      await _settle(tester);
      expect(find.byType(CompareSheet), findsOneWidget);
      expect(_ft('Читать параллельно'), findsOneWidget, reason: 'заголовок окна выбора'); // не «Сравнение переводов»
      expect(_ft('Сравнение переводов'), findsNothing);
      expect(c.read(selectionProvider)[0], isEmpty);
      expect(_ftc('For God so loved'), findsOneWidget);
      expect(_ftc('Так Бог полюбил'), findsOneWidget);
      // выбрать перевод: вторая панель с ним на том же стихе
      await tester.tap(find.byTooltip('Читать параллельно').last);
      await _settle(tester);
      final panes = c.read(panesProvider);
      expect(panes.length, 2);
      expect(panes[1].moduleId, anyOf('kjv', 'nrt'));
      expect(panes[1].ref, _john);
      expect(find.byType(CompareSheet), findsNothing);
    });
  }

  // =========================== пункты «Ещё», копия, «Мои данные» ===========================

  testWidgets('«Ещё»: закладка на это место и к последней закладке', (tester) async {
    prefs.setString('panes', jsonEncode([{'moduleId': 'rst-plus', 'ref': _gen.toJson()}]));
    late WidgetRef wref;
    late BuildContext ctx;
    final c = await _pump(tester, (context, ref) {
      wref = ref;
      ctx = context;
      return const SizedBox();
    });
    MoreItem item(String id) => Hub.moreItems.firstWhere((x) => x.id == id);
    expect(item('bookmark-here').visible!(wref), isTrue);
    expect(item('bookmark-off').visible!(wref), isFalse);
    expect(item('bookmark-last').visible!(wref), isFalse, reason: 'закладок нет');
    // стоим на Быт. 1:1 — закладка с текстом стиха
    item('bookmark-here').run(ctx, wref, 0);
    var marks = c.read(marksProvider);
    expect(marks.bookmarks.single['book'], 'Gen');
    expect(marks.bookmarks.single['text'], contains('сотворил'));
    expect(item('bookmark-here').visible!(wref), isFalse);
    expect(item('bookmark-off').visible!(wref), isTrue);
    expect(item('bookmark-last').visible!(wref), isTrue);
    // новая закладка — первая в списке; «к последней» ведёт на неё
    c.read(marksProvider.notifier).toggleBookmark(_john, 'Так возлюбил');
    c.read(panesProvider.notifier).navigate(0, const VerseRef('Gen', 1, 3));
    item('bookmark-last').run(ctx, wref, 0);
    expect(c.read(panesProvider)[0].ref, _john);
    // флаг меню выключен — пункта нет
    c.read(settingsProvider.notifier).set({
      'menu': {...(Settings.defaults['menu'] as Map), 'lastBookmark': false}
    });
    expect(item('bookmark-last').visible!(wref), isFalse);
    // убрать закладку с текущего места
    c.read(panesProvider.notifier).navigate(0, _john);
    expect(item('bookmark-off').visible!(wref), isTrue);
    item('bookmark-off').run(ctx, wref, 0);
    marks = c.read(marksProvider);
    expect(marks.isBookmarked(_john), isFalse);
  });

  testWidgets('автокопия при первом запуске новой версии', (tester) async {
    late WidgetRef wref;
    await _pump(tester, (context, ref) {
      wref = ref;
      return const SizedBox();
    });
    // первый запуск вообще: копии нет, версия запоминается
    prefs.setString('bookmarks', jsonEncode([{'book': 'John', 'chapter': 3, 'verse': 16, 'text': 'x', 'at': 1}]));
    await bootBackup(wref);
    expect(prefs.getString('lastBuild'), appVersion);
    expect(listBackups(), isEmpty);
    // тот же запуск ещё раз — без копий
    await bootBackup(wref);
    expect(listBackups(), isEmpty);
    // версия сменилась: копия «до обновления с версии …»
    prefs.setString('lastBuild', '0.9.0');
    await bootBackup(wref);
    final b = listBackups().single;
    expect(b.reason, 'до обновления с версии 0.9.0');
    expect(b.bookmarks, 1);
    expect(prefs.getString('lastBuild'), appVersion);
  });

  test('«Мои данные»: поиск и панели — как в файле веб-версии, и обратно', () async {
    prefs.setString('searchQuery', 'любовь');
    prefs.setString('lang', 'ru');
    prefs.setString('panes', jsonEncode([
      {'moduleId': 'rst-plus', 'ref': _john.toJson()},
      {'moduleId': 'kjv', 'ref': _gen.toJson()},
    ]));
    final file = exportData();
    final d = (file['data'] as Map).cast<String, String>();
    expect(d['searchQuery'], '"любовь"', reason: 'в вебе это JSON-строка');
    expect(d['lang'], '"ru"');
    final panes = jsonDecode(d['panes']!) as List;
    expect(panes.length, 2);
    expect(panes[0]['moduleId'], 'rst-plus');
    expect(panes[0]['ref'], {'book': 'John', 'chapter': 3, 'verse': 16});
    expect(panes[0]['history'], [panes[0]['ref']]);
    expect(panes[0]['hIndex'], 0);
    // одна панель → вторая null, как в веб-версии
    prefs.setString('panes', jsonEncode([{'moduleId': 'rst-plus', 'ref': _john.toJson()}]));
    final one = jsonDecode(((exportData()['data'] as Map)['panes']) as String) as List;
    expect(one.length, 2);
    expect(one[1], isNull);
    // файл веба → у нас
    prefs.remove('searchQuery');
    prefs.remove('panes');
    expect(importData(jsonDecode(jsonEncode(file)) as Map<String, dynamic>), isTrue);
    expect(prefs.getString('searchQuery'), 'любовь');
    final back = jsonDecode(prefs.getString('panes')!) as List;
    expect(back.length, 2);
    expect(back[1]['moduleId'], 'kjv');
    expect(back[0]['ref'], {'book': 'John', 'chapter': 3, 'verse': 16});
  });
}

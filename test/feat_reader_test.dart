// Читалка как в веб-версии: «Как книга» и «Сплошной», подсветка найденного слова и мигание стиха, режим чтения,
// двойное касание, щипок, номер Стронга, «Часть стиха», иврит справа налево, полоса прогресса, свайп главы.
// Телефон 400×830, светлая и тёмная тема; любое исключение Flutter роняет тест.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/bible.dart';
import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/markup.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/panes.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/hub.dart';
import 'package:aobible/main.dart';
import 'package:aobible/ui/reader_pane.dart';
import 'package:aobible/ui/verse_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

late Directory dir;

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
        db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (?,?)', [n, plainText(chapters[c][v])]);
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
    dir = Directory('${Directory.systemTemp.path}/aob_fr_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final books = {
      'Gen': chapters('Бог', 3, 30),
      'John': [
        for (var c = 1; c <= 3; c++) [for (var v = 1; v <= 12; v++) 'Стих $v: {любовь|G26} и истина, {свет|G5457} мира.'],
      ],
    };
    makeBible('rst-plus', 'РСТ', 'ru', books);
    makeBible('heb', 'Иврит', 'he', {'Gen': chapters('אלהים', 2, 8)});
    await ModuleStore.initAt(dir);
    await setLang('ru');
    Hub.reset();
    livePositions.clear();
    SyncHub.listeners.clear();
    SyncHub.driver = 0;
    readerMarks.value = {};
    focusHidden.value = false;
    partSelection.value = null;
    activeWord.value = null;
  });

  Future<ProviderContainer> start(WidgetTester tester, {String theme = 'light', Map<String, dynamic>? settings, String? panes}) async {
    tester.view.physicalSize = const Size(400, 830);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    prefs.setString('settings', jsonEncode({'theme': theme, ...?settings}));
    if (panes != null) prefs.setString('panes', panes);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const AoBibleApp()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    return c;
  }

  Future<void> go(WidgetTester tester, [int ms = 100]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump(const Duration(milliseconds: 50));
  }

  // Центр слова в тексте (n-е вхождение) в координатах экрана
  Offset wordAt(WidgetTester tester, Finder text, String word, [int nth = 0, String? after]) {
    final rp = tester.renderObject<RenderParagraph>(text);
    final plain = rp.text.toPlainText(includePlaceholders: true);
    var at = after == null ? -1 : plain.indexOf(after);
    for (var i = 0; i <= nth; i++) {
      at = plain.indexOf(word, at + 1);
    }
    expect(at, greaterThanOrEqualTo(0), reason: word);
    final box = rp.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + word.length)).first.toRect();
    return rp.localToGlobal(box.center);
  }

  // Подложки читалки (приватный painter — читаем динамически): сколько плашек данного вида нарисовано
  int plates(WidgetTester tester, int kind) {
    var n = 0;
    for (final cp in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
      final p = cp.painter as dynamic;
      if (p.runtimeType.toString() != '_PlatePainter') continue;
      for (final pl in (p.plates as List)) {
        if ((pl as dynamic).kind == kind) n++;
      }
    }
    return n;
  }

  Finder para(String s) => find.textContaining(s, findRichText: true);

  test('Слова стиха и часть стиха — как в веб-версии', () {
    final toks = parseVerse('В {начале|G746} было ‹Слово›, и Слово было у Бога.');
    final words = wordsOf(toks);
    expect([for (final w in words) toks[w.token].text.substring(w.start, w.end)], ['В', 'начале', 'было', 'Слово', 'и', 'Слово', 'было', 'у', 'Бога']);
    expect(partText(toks, words, 1, 3), 'начале было Слово');
    expect(partText(toks, words, 3, 1), 'начале было Слово');
    expect(partText(toks, words, 4, 4), 'и');
    expect(partText(toks, words, 7, 8), 'у Бога');
  });

  test('Подсветка найденного слова: часть слова, ё = е', () {
    final it = ReaderItem.verse(1, 1, 'Светильник и свет мира, всё в нём.');
    final w = wordsOf(it.tokens);
    expect({for (final i in highlightWords(it, 'свет')) it.tokens[w[i].token].text.substring(w[i].start, w[i].end)}, {'Светильник', 'свет'});
    expect({for (final i in highlightWords(it, 'все')) it.tokens[w[i].token].text.substring(w[i].start, w[i].end)}, {'всё'});
    expect(highlightWords(it, 'я'), isEmpty);
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('«Как книга»: абзац без номеров, переход к стиху, выделение, слово — $theme', (tester) async {
      final tapped = <String>[];
      final c = await start(tester, theme: theme, settings: {'bookMode': true, 'showVerseNumbers': true});
      Hub.onWordTap = (ctx, ref, tap) => tapped.add(tap.token.text);
      // Стихи 1–12 идут одним абзацем (заголовок раздела перед стихом 1 — отдельно)
      final p = para('Стих 2 главы 1');
      expect(p, findsOneWidget);
      expect(tester.widget<RichText>(p).text.toPlainText(includePlaceholders: true).contains('Стих 5 главы 1'), isTrue);
      // номеров стихов нет: в тексте только красная строка (метка WidgetSpan) вместо номеров
      expect(RegExp('￼').allMatches(tester.widget<RichText>(p).text.toPlainText(includePlaceholders: true)).length, 1);
      // переход к стиху внутри абзаца: стих встаёт к верхнему краю
      c.read(panesProvider.notifier).navigate(0, const VerseRef('Gen', 1, 20), flash: false);
      await go(tester);
      await go(tester);
      expect(livePositions[0]!.value.chapter, 1);
      expect((livePositions[0]!.value.verse - 20).abs(), lessThanOrEqualTo(1));
      // слово: нажатие и пауза двойного касания
      Hub.onVerseDoubleTap = (ctx, ref, pane, at, m) {};
      final t = find.textContaining('Стих 21 главы 1', findRichText: true).first;
      await tester.tapAt(wordAt(tester, t, 'светильник', 0, 'Стих 21 главы 1'));
      await go(tester, 100);
      expect(tapped, isEmpty); // ждём: вдруг двойное касание
      await go(tester, 400);
      expect(tapped, ['светильник']);
      // долгое нажатие выделяет стих
      await tester.longPressAt(wordAt(tester, t, 'свет', 0, 'Стих 22 главы 1'));
      await go(tester);
      expect(c.read(selectionProvider)[0], isNotNull);
      expect(c.read(selectionProvider)[0]!.isNotEmpty, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Сплошной»: номера стихов остаются, абзац один, выделение стиха — $theme', (tester) async {
      final c = await start(tester, theme: theme, settings: {'continuousVerses': true});
      final p = para('Стих 3 главы 1');
      expect(p, findsOneWidget);
      expect(tester.widget<RichText>(p).text.toPlainText(includePlaceholders: true).contains('Стих 4 главы 1'), isTrue);
      // нажатие на номер стиха выделяет его
      final rp = tester.renderObject<RenderParagraph>(p);
      final plain = rp.text.toPlainText(includePlaceholders: true);
      final at = plain.indexOf('Стих 3 главы 1') - 1; // метка номера стиха 3
      final box = rp.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 1)).first.toRect();
      await tester.tapAt(rp.localToGlobal(box.center));
      await go(tester);
      expect(c.read(selectionProvider)[0], {const VerseRef('Gen', 1, 3)});
      expect(plates(tester, 0), greaterThan(0)); // подложка выделенного стиха
      // нажатие на слово при выделении добавляет стих
      await tester.tapAt(wordAt(tester, para('Стих 4 главы 1'), 'свет', 0, 'Стих 4 главы 1'));
      await go(tester);
      expect(c.read(selectionProvider)[0]!.length, 2, reason: '${c.read(selectionProvider)[0]}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Найденное слово подсвечено 8 с, стих мигает — $theme', (tester) async {
      final c = await start(tester, theme: theme);
      c.read(panesProvider.notifier).navigate(0, const VerseRef('Gen', 1, 5), highlight: 'светильник');
      await go(tester);
      await go(tester);
      expect(plates(tester, 2), 1); // одно слово «светильник» в стихе 5
      expect(plates(tester, 1), 1); // мигание
      await tester.pump(const Duration(milliseconds: 2500));
      expect(plates(tester, 1), 0);
      expect(plates(tester, 2), 1);
      await tester.pump(const Duration(milliseconds: 6000));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(plates(tester, 2), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Без анимаций стих не мигает', (tester) async {
    final c = await start(tester, settings: {'animations': false});
    c.read(panesProvider.notifier).navigate(0, const VerseRef('Gen', 1, 5), highlight: 'свет');
    await go(tester);
    await go(tester);
    expect(plates(tester, 1), 0);
    expect(plates(tester, 2), greaterThan(0));
  });

  testWidgets('Касание текста сразу гасит подсветку слова', (tester) async {
    final c = await start(tester);
    c.read(panesProvider.notifier).navigate(0, const VerseRef('Gen', 1, 5), highlight: 'светильник');
    await go(tester);
    await go(tester);
    expect(plates(tester, 2), 1);
    await tester.tapAt(const Offset(200, 600));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));
    expect(plates(tester, 2), 0);
  });

  testWidgets('Режим чтения: прокрутка вниз прячет панели, вверх возвращает', (tester) async {
    await start(tester, settings: {'focusMode': true});
    expect(focusHidden.value, isFalse);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(focusHidden.value, isTrue);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(focusHidden.value, isFalse);
  });

  testWidgets('Без режима чтения панели не прячутся', (tester) async {
    await start(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(focusHidden.value, isFalse);
  });

  testWidgets('Двойное касание стиха — Hub.onVerseDoubleTap, слово не открывается', (tester) async {
    final words = <String>[];
    var doubles = 0;
    await start(tester);
    Hub.onWordTap = (ctx, ref, tap) => words.add(tap.token.text);
    Hub.onVerseDoubleTap = (ctx, ref, pane, at, m) => doubles++;
    final t = para('Стих 3 главы 1').first;
    final pos = wordAt(tester, t, 'светильник');
    await tester.tapAt(pos);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(pos);
    await go(tester, 500);
    expect(doubles, 1);
    expect(words, isEmpty);
    expect(activeWord.value, isNull);
    // одиночное нажатие: слово подсвечено сразу, выборка — после паузы
    await tester.tapAt(pos);
    await go(tester, 50);
    expect(activeWord.value, isNotNull);
    expect(plates(tester, 0), greaterThan(0));
    await go(tester, 450);
    expect(words, ['светильник']);
  });

  testWidgets('Номер Стронга в тексте — Hub.openStrong', (tester) async {
    String? got;
    final c = await start(tester, settings: {'showStrongs': true}, panes: jsonEncode([{'moduleId': 'rst-plus', 'ref': const VerseRef('John', 2, 1).toJson()}]));
    expect(c.read(panesProvider)[0].ref.book, 'John');
    Hub.openStrong = (ctx, ref, pane, at, strongNum) => got = strongNum;
    Hub.onVerseDoubleTap = (ctx, ref, pane, at, m) {};
    await tester.tap(find.text('G26').first);
    await go(tester);
    expect(got, 'G26');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 450))); // двойное касание считается по реальному времени
    await tester.tap(find.text('G5457').first);
    await go(tester, 400);
    expect(got, 'G5457');
  });

  testWidgets('Часть стиха: два слова, текст, «В проповедь», «В любимые», «Отмена»', (tester) async {
    String? sermon;
    (int, int, String)? fav;
    final c = await start(tester);
    Hub.addFragmentToSermon = (ctx, ref, at, m, fragment) => sermon = fragment;
    Hub.addFavoritePart = (ctx, ref, at, m, from, to, text) => fav = (from, to, text);
    partSelection.value = const PartSelection(0, VerseRef('Gen', 1, 3), 'rst-plus');
    await go(tester);
    expect(find.text('Нажмите на первое и последнее слово.'), findsOneWidget);
    // кнопки недоступны, пока не выбрано слово
    final t = para('Стих 3 главы 1').first;
    await tester.tapAt(wordAt(tester, t, 'главы'));
    await go(tester);
    expect(partSelection.value!.from, 1);
    expect(partSelection.value!.to, isNull);
    expect(find.textContaining('«главы»'), findsOneWidget);
    await tester.tapAt(wordAt(tester, para('Стих 3 главы 1').first, 'светильник'));
    await go(tester);
    expect(partSelection.value!.to, 3);
    expect(find.textContaining('«главы 1: Бог светильник»'), findsOneWidget);
    expect(plates(tester, 0), greaterThan(0));
    await tester.tap(find.byTooltip('В любимые'));
    await go(tester);
    expect(fav, (1, 3, 'главы 1: Бог светильник'));
    expect(partSelection.value, isNull);
    expect(find.text('Нажмите на первое и последнее слово.'), findsNothing);
    // «В проповедь»
    partSelection.value = const PartSelection(0, VerseRef('Gen', 1, 3), 'rst-plus', from: 6, to: 7);
    await go(tester);
    await tester.tap(find.text('В проповедь'));
    await go(tester);
    expect(sermon, isNotNull);
    expect(partSelection.value, isNull);
    // «Отмена»
    partSelection.value = const PartSelection(0, VerseRef('Gen', 1, 3), 'rst-plus');
    await go(tester);
    await tester.tap(find.text('Отмена'));
    await go(tester);
    expect(partSelection.value, isNull);
    expect(c.read(selectionProvider)[0]?.isEmpty ?? true, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Любимые части стиха подчёркнуты плашкой', (tester) async {
    await start(tester);
    Hub.verseDecorators.add((ctx, ref, pane, m, item, book) => item.kind == ItemKind.verse && item.verse == 2 ? const VerseDecor(parts: [(1, 3)]) : null);
    ProviderScope.containerOf(tester.element(find.byType(ReaderPane).first)).read(decorVersionProvider.notifier).bump();
    await go(tester);
    expect(plates(tester, 0), greaterThan(0));
  });

  testWidgets('Иврит: чтение справа налево', (tester) async {
    await start(tester, panes: jsonEncode([{'moduleId': 'heb', 'ref': const VerseRef('Gen', 1, 1).toJson()}]));
    final ctx = tester.element(find.byType(VerseView).at(1));
    expect(Directionality.of(ctx), TextDirection.rtl);
  });

  testWidgets('Русский текст — слева направо', (tester) async {
    await start(tester);
    expect(Directionality.of(tester.element(find.byType(VerseView).at(1))), TextDirection.ltr);
  });

  testWidgets('Полоса прогресса книги растёт вместе с чтением', (tester) async {
    final c = await start(tester);
    double w() => tester.widget<AnimatedFractionallySizedBox>(find.byType(AnimatedFractionallySizedBox).first).widthFactor!;
    final a = w();
    c.read(panesProvider.notifier).navigate(0, const VerseRef('Gen', 3, 15), flash: false);
    await go(tester);
    await go(tester);
    expect(w(), greaterThan(a));
    expect(w(), greaterThan(0.7));
  });

  testWidgets('Свайп: влево — следующая глава, у края и при выделении — нет', (tester) async {
    final c = await start(tester);
    expect(c.read(panesProvider)[0].ref.chapter, 1);
    // у левого края экрана — системный жест, глава не меняется
    await tester.dragFrom(const Offset(10, 400), const Offset(-200, 0));
    await go(tester);
    expect(c.read(panesProvider)[0].ref.chapter, 1);
    // выделение открыто — свайп не листает
    c.read(selectionProvider.notifier).toggle(0, const VerseRef('Gen', 1, 2));
    await go(tester);
    await tester.dragFrom(const Offset(300, 400), const Offset(-200, 0));
    await go(tester);
    expect(c.read(panesProvider)[0].ref.chapter, 1);
    c.read(selectionProvider.notifier).clear(0);
    await go(tester);
    // короткий свайп — текст возвращается на место
    await tester.dragFrom(const Offset(300, 400), const Offset(-40, 0));
    await go(tester, 300);
    expect(c.read(panesProvider)[0].ref.chapter, 1);
    await tester.dragFrom(const Offset(300, 400), const Offset(-200, 0));
    await go(tester);
    expect(c.read(panesProvider)[0].ref.chapter, 2);
    await tester.dragFrom(const Offset(100, 400), const Offset(200, 0));
    await go(tester);
    expect(c.read(panesProvider)[0].ref.chapter, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Щипок двумя пальцами меняет размер шрифта и сохраняет его', (tester) async {
    final c = await start(tester);
    expect(c.read(settingsProvider).d('fontSize'), 19.0);
    final a = await tester.startGesture(const Offset(150, 400), pointer: 1);
    final b = await tester.startGesture(const Offset(250, 400), pointer: 2);
    await a.moveTo(const Offset(100, 400));
    await b.moveTo(const Offset(300, 400));
    await go(tester);
    expect(find.text('38 px'), findsOneWidget);
    await a.up();
    await b.up();
    await go(tester, 500);
    expect(c.read(settingsProvider).d('fontSize'), 38.0);
    expect(find.text('38 px'), findsNothing);
    // свести — мельче, но не меньше 13
    final a2 = await tester.startGesture(const Offset(100, 400), pointer: 3);
    final b2 = await tester.startGesture(const Offset(300, 400), pointer: 4);
    await a2.moveTo(const Offset(199, 400));
    await b2.moveTo(const Offset(201, 400));
    await a2.up();
    await b2.up();
    await go(tester, 500);
    expect(c.read(settingsProvider).d('fontSize'), 13.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Две панели в режиме «Сплошной»: вторая идёт за первой', (tester) async {
    final c = await start(tester, settings: {'continuousVerses': true}, panes: jsonEncode([
      {'moduleId': 'rst-plus', 'ref': const VerseRef('Gen', 1, 1).toJson()},
      {'moduleId': 'rst-plus', 'ref': const VerseRef('Gen', 1, 1).toJson()},
    ]));
    expect(c.read(panesProvider).length, 2);
    final first = find.byType(Scrollable).first;
    await tester.drag(first, const Offset(0, -700));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final a = livePositions[0]!.value, b = livePositions[1]!.value;
    expect(a.verse, greaterThan(3));
    expect((a.verse - b.verse).abs(), lessThanOrEqualTo(2), reason: '$a / $b');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

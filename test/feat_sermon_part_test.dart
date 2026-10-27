// «Часть стиха» в блоке проповеди: кнопка в нижней строке блока, выбор первого и последнего слова, «Готово», «Весь стих».
// Окно 400×830, светлая и тёмная тема; шрифт и тестовый перевод — как в qa_plans_sermons_audio_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/i18n.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/plans/ui_kit.dart' show showPage;
import 'package:aobible/features/sermons/sermon_store.dart';
import 'package:aobible/features/sermons/sermons_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
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
const full = 'Ибо так возлюбил Бог мир, что отдал Сына Своего Единородного';

late Directory root;
bool realFont = false;
late ProviderContainer c;

Future<void> loadRoboto() async {
  var d = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++, d = d.parent) {
    final dir = Directory('${d.path}/artifacts/material_fonts');
    if (!dir.existsSync()) continue;
    final loader = FontLoader('Roboto');
    for (final f in ['regular', 'medium', 'bold']) {
      final file = File('${dir.path}/roboto-$f.ttf');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
    realFont = true;
    return;
  }
}

void makeBible(Directory dir) {
  final db = sqlite3.open('${dir.path}/rst-plus.db');
  db.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
  db.execute('''
    CREATE TABLE verses(id INTEGER PRIMARY KEY, book TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE headings(book TEXT, chapter INTEGER, verse INTEGER, text TEXT);
    CREATE TABLE xrefs(book TEXT, chapter INTEGER, verse INTEGER, refs TEXT);
    CREATE VIRTUAL TABLE verses_fts USING fts5(plain, content='', tokenize='unicode61 remove_diacritics 2');
  ''');
  db.execute('INSERT INTO verses VALUES (1, ?, 3, 16, ?)', ['John', full]);
  db.execute('INSERT INTO verses_fts(rowid, plain) VALUES (1, ?)', [full]);
  db.execute('CREATE INDEX verses_ref ON verses(book, chapter, verse)');
  db.execute('INSERT INTO meta VALUES (?, ?)', ['json', jsonEncode({'id': 'rst-plus', 'type': 'bible', 'name': 'РСТ+', 'title': 'Тест', 'language': 'ru', 'bookList': [{'id': 'John', 'name': 'John', 'short': 'John', 'chapters': 3}]})]);
  db.close();
}

Future<void> spin(WidgetTester tester, [int ms = 700]) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapTip(WidgetTester tester, String tip) async {
  final f = find.byTooltip(tip);
  expect(f, findsWidgets, reason: 'нет подсказки «$tip»');
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await spin(tester, 300);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: 'нет «$text»');
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await spin(tester, 300);
}

/// Нажать слово в тексте стиха блока (Text.rich со словами-ссылками) — по середине слова
Future<void> tapWord(WidgetTester tester, String word) async {
  final f = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == full);
  final rt = tester.renderObject<RenderParagraph>(f.first);
  final i = full.indexOf(word);
  final boxes = rt.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + word.length));
  // настоящая мышь, как в Windows: нажатие по координатам слова
  final at = rt.localToGlobal(boxes.first.toRect().center);
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: at);
  await g.down(at);
  await g.up();
  await g.removePointer();
  await spin(tester, 200);
}

Future<void> boot(WidgetTester tester, V v, String id) async {
  tester.view.physicalSize = const Size(400, 830);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(settingsProvider.notifier).set({'theme': v.theme});
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: ThemeData(brightness: v.theme == 'dark' ? Brightness.dark : Brightness.light, fontFamily: realFont ? 'Roboto' : null),
      home: Consumer(
        builder: (ctx, ref, _) => Scaffold(body: Center(child: GestureDetector(onTap: () => showPage(ctx, (_) => SermonsSheet(pane: 0, open: id), page: true), child: const Text('открыть')))),
      ),
    ),
  ));
  await tester.tap(find.text('открыть'));
  await spin(tester, 300);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await spin(tester, 600);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    root = Directory('${Directory.systemTemp.path}/aob_part_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final mods = Directory('${root.path}/modules')..createSync();
    makeBible(mods);
    await loadRoboto();
    await Books.load();
    await ModuleStore.initAt(mods);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await setLang('ru');
  });

  for (final v in variants) {
    testWidgets('часть стиха в проповеди [${v.name}]: выбор слов, «Готово», «Весь стих»', (tester) async {
      final tmp = ProviderContainer();
      final id = tmp.read(sermonsProvider.notifier).create('Любовь');
      tmp.read(sermonsProvider.notifier).addVerses(id, [const VerseItem('John', 3, 16, full)], 'rst-plus');
      tmp.dispose();
      await boot(tester, v, id);
      final store = c.read(sermonsProvider.notifier);
      Block blk() => blocksOf(store.byId(id)!).first;

      // на полном стихе есть «Часть стиха», «Весь стих» — нет
      expect(find.text('Часть стиха'), findsOneWidget);
      expect(find.text('Весь стих'), findsNothing);
      await tapText(tester, 'Часть стиха');
      expect(find.text('Нажмите на первое и последнее слово.'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
      // «Готово» без выбора не работает
      await tapText(tester, 'Готово');
      expect(blk()['part'], isNull);

      // первое нажатие — начало, второе — конец, третье — заново
      await tapWord(tester, 'возлюбил');
      await tester.pumpAndSettle(); // подсказка сворачивается плавно
      expect(find.text('Нажмите на первое и последнее слово.'), findsNothing, reason: 'нажатие по слову не отмечено');
      await tapWord(tester, 'Бог');
      expect(find.text('Нажмите на первое и последнее слово.'), findsNothing);
      await tapWord(tester, 'Сына'); // третье: начало заново
      await tapWord(tester, 'Бог'); // конец раньше начала — порядок не важен
      await tapText(tester, 'Готово');
      expect(blk()['text'], 'Бог мир, что отдал Сына');
      expect(blk()['part'], true);
      expect(blockRef(blk()), contains('(часть)'));
      expect(find.text('Весь стих'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // у части — одна кнопка «Весь стих»: возвращает полный текст и убирает пометку
      expect(find.text('Часть стиха'), findsNothing);
      await tapText(tester, 'Весь стих');
      expect(blk()['text'], full);
      expect(blk().containsKey('part'), false);
      expect(find.text('Весь стих'), findsNothing);

      // «Отмена» ничего не меняет
      await tapText(tester, 'Часть стиха');
      await tapWord(tester, 'Ибо');
      await tapText(tester, 'Отмена');
      expect(blk()['text'], full);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await spin(tester, 200);
    });
  }

  testWidgets('отмена и повтор в шапке редактора: часть стиха и название', (tester) async {
    final tmp = ProviderContainer();
    final id = tmp.read(sermonsProvider.notifier).create('Любовь');
    tmp.read(sermonsProvider.notifier).addVerses(id, [const VerseItem('John', 3, 16, full)], 'rst-plus');
    tmp.dispose();
    await boot(tester, variants.first, id);
    final store = c.read(sermonsProvider.notifier);
    Block blk() => blocksOf(store.byId(id)!).first;
    expect(find.byTooltip('Отменить'), findsOneWidget);
    await tapText(tester, 'Часть стиха');
    await tapWord(tester, 'Бог');
    await tapWord(tester, 'мир');
    await tapText(tester, 'Готово');
    expect(blk()['part'], true);
    await tapTip(tester, 'Отменить');
    expect(blk()['text'], full);
    expect(blk().containsKey('part'), false);
    await tapTip(tester, 'Повторить');
    expect(blk()['text'], 'Бог мир');
    expect(blk()['part'], true);
    await tester.pumpWidget(const SizedBox());
    await spin(tester, 200);
  });
}

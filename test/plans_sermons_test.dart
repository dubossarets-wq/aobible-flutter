// Проповеди: блоки, склейка стихов подряд, удаление стиха из диапазона, перестановка, текст для отправки, разбор ссылок.
import 'dart:convert';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/sermons/sermon_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer c;

  setUp(() async {
    await Books.load();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    c = ProviderContainer();
  });
  tearDown(() => c.dispose());

  SermonsNotifier store() => c.read(sermonsProvider.notifier);
  List<VerseItem> john(List<int> vs) => [for (final v in vs) VerseItem('John', 3, v, 'текст $v')];

  test('создание, переименование, удаление и «Отменить»', () {
    final id = store().create('  Благодать  ');
    expect(c.read(sermonsProvider).single['title'], 'Благодать');
    expect(store().create('').isNotEmpty, true);
    expect(c.read(sermonsProvider).first['title'], 'Новая проповедь'); // новая — сверху
    store().rename(id, 'Новое имя');
    final s = c.read(sermonsProvider).firstWhere((x) => x['id'] == id);
    final i = c.read(sermonsProvider).indexOf(s);
    store().delete(id);
    expect(c.read(sermonsProvider).length, 1);
    store().restore(s, i);
    expect(c.read(sermonsProvider).indexWhere((x) => x['id'] == id), i);
    // данные лежат в prefs тем же JSON, что и в веб-версии
    final saved = jsonDecode(prefs.getString('sermons')!) as List;
    expect(saved.length, 2);
    expect((saved.first as Map).keys, containsAll(['id', 'title', 'date', 'blocks', 'createdAt', 'updatedAt']));
    expect(store().byId(id)!['title'], 'Новое имя');
  });

  test('стихи подряд — один блок с texts, не подряд — отдельные', () {
    final id = store().create('П');
    store().addVerses(id, john([16, 17, 18, 20]), 'rst-plus');
    final blocks = blocksOf(store().byId(id)!);
    expect(blocks.length, 2);
    expect((blocks[0]['verse'], blocks[0]['to']), (16, 18));
    expect(blocks[0]['texts'], ['текст 16', 'текст 17', 'текст 18']);
    expect(blocks[0]['text'], 'текст 16 текст 17 текст 18');
    expect(blocks[1]['to'], isNull);
    expect(blockRef(blocks[0]), 'Ин 3:16–18');
    expect(blockRefFull(blocks[0]), 'От Иоанна 3:16–18');
  });

  test('вставка в нужное место, свой текст, перестановка', () {
    final id = store().create('П');
    store().addVerses(id, [const VerseItem('John', 3, 1, 'а')], 'rst-plus');
    store().addVerses(id, [const VerseItem('John', 3, 5, 'б')], 'rst-plus');
    store().addVerses(id, [const VerseItem('John', 3, 3, 'в')], 'rst-plus', at: 1); // между
    expect(blocksOf(store().byId(id)!).map((b) => b['verse']), [1, 3, 5]);
    final tid = store().addTextBlock(id, after: 0);
    expect(blocksOf(store().byId(id)!)[1]['id'], tid);
    store().addTextBlock(id, after: -1); // в самое начало
    expect(blocksOf(store().byId(id)!).first['type'], 'text');
    store().updateBlock(id, tid, {'text': 'Мысль'});
    store().moveBlock(id, 0, 3);
    final order = blocksOf(store().byId(id)!);
    expect(order.length, 5);
    expect(order[3]['type'], 'text');
    store().removeBlock(id, tid);
    expect(blocksOf(store().byId(id)!).length, 4);
  });

  test('убрать стих из диапазона: блок делится; из одиночного — исчезает', () {
    final id = store().create('П');
    store().addVerses(id, john([16, 17, 18, 19]), 'rst-plus');
    final bid = blocksOf(store().byId(id)!).single['id'] as String;
    final before = blocksOf(store().byId(id)!);
    store().removeVerse(id, bid, 17);
    var blocks = blocksOf(store().byId(id)!);
    expect(blocks.length, 2);
    expect((blocks[0]['verse'], blocks[0]['to'], blocks[0]['id']), (16, null, bid));
    expect((blocks[1]['verse'], blocks[1]['to']), (18, 19));
    expect(blocks[1]['texts'], ['текст 18', 'текст 19']);
    store().removeVerse(id, '${blocks[0]['id']}', 16);
    expect(blocksOf(store().byId(id)!).length, 1);
    store().restoreBlocks(id, before); // «Отменить»
    blocks = blocksOf(store().byId(id)!);
    expect(blocks.single['to'], 19);
    // убрать первый стих диапазона — остаток 17–19
    store().removeVerse(id, bid, 16);
    expect(blocksOf(store().byId(id)!).single['verse'], 17);
  });

  test('текст проповеди для отправки', () {
    final id = store().create('Благодать');
    store().addVerses(id, john([16, 17]), 'rst-plus');
    final tid = store().addTextBlock(id);
    store().updateBlock(id, tid, {'text': '  Бог любит  '});
    store().addTextBlock(id); // пустой — не попадает
    final text = sermonText(store().byId(id)!);
    expect(text, 'Благодать\n\nОт Иоанна 3:16–17\n«16 текст 16\n17 текст 17»\n\nБог любит');
  });

  test('старый диапазон без texts не разбивается, но показывается одним абзацем', () {
    final b = <String, dynamic>{'id': 'x', 'type': 'verse', 'book': 'John', 'chapter': 3, 'verse': 16, 'to': 18, 'text': 'всё вместе'};
    expect(verseTexts(b), isNull);
    expect(verseTexts({...b, 'texts': ['а', 'б', 'в']}), ['а', 'б', 'в']);
    expect(verseTexts({...b, 'texts': ['а']}), isNull);
  });

  test('поиск проповеди со стихом: самая недавняя', () {
    final a = store().create('A');
    final b = store().create('B');
    store().addVerses(a, john([16]), 'rst-plus');
    store().addVerses(b, john([15, 16, 17]), 'rst-plus');
    expect(sermonWith(c.read(sermonsProvider), const VerseRef('John', 3, 16))!['id'], b);
    expect(sermonWith(c.read(sermonsProvider), const VerseRef('John', 3, 20)), isNull);
  });

  test('ссылка из строки поиска: глава целиком или диапазон', () {
    expect(isWholeChapter('Ин 3'), true);
    expect(isWholeChapter('Ин 3:16-18'), false);
    expect(isWholeChapter('1 Кор 13'), true);
    final r = parseRange('Ин 3:16-18')!;
    expect((r.book, r.chapter, r.verse, r.end), ('John', 3, 16, 18));
    expect(refRangeLabel('Ин 3:16-18', r), 'От Иоанна 3:16–18');
    expect(refRangeLabel('Ин 3', parseRange('Ин 3')!), 'От Иоанна 3');
    expect(parseRange('любовь'), isNull);
  });
}

// Новые источники переводов на настоящих данных: bible.helloao.org (скачивается целиком) и API.Bible
// (через посредник aobible.app/bapi — главы по одной, хранятся недолго).
import 'dart:io';

import 'package:aobible/core/apibible.dart';
import 'package:aobible/core/bible.dart';
import 'package:aobible/core/books.dart';
import 'package:aobible/core/modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // настоящая сеть

  late ModuleStore store;
  late List<CatalogEntry> cat;
  setUpAll(() async {
    await Books.load();
    final dir = Directory('${Directory.systemTemp.path}/aob_test_online');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    store = await ModuleStore.initAt(dir);
    cat = await store.catalog();
  });

  test('каталог: переводы helloao скачиваются, API.Bible — только недоступные иначе', () {
    final hao = cat.where((c) => c.json['helloao'] != null).toList();
    final online = cat.where((c) => c.json['online'] != null).toList();
    expect(hao.length, greaterThan(1000));
    expect(online.map((c) => c.name), containsAll(['AMP', 'NASB 1995', 'NIrV']));
    // без дублей: Синодальный — только наш RST+, не копия с helloao
    expect(cat.where((c) => c.id == 'hao-rus_syn'), isEmpty);
  });

  test('helloao: Тиндейл — скачать, книга, заголовки', () async {
    final e = cat.firstWhere((c) => c.id == 'hao-eng_tnt');
    await store.install(e);
    final b = loadBook('hao-eng_tnt', 'Matt');
    final first = b.items.firstWhere((i) => i.kind == ItemKind.verse);
    expect(first.text, startsWith('This is the boke'));
    expect(bookList('hao-eng_tnt').length, 27);
  });

  test('API.Bible: AMP — добавить, глава по сети, права', () async {
    final e = cat.firstWhere((c) => c.name == 'AMP' && c.json['online'] != null);
    final sw = Stopwatch()..start();
    await store.install(e);
    // ignore: avoid_print
    print('добавить: ${sw.elapsedMilliseconds} мс');
    expect(isOnline(e.id), isTrue);
    expect(bookList(e.id).length, 66);
    expect(hasChapter(e.id, 'John', 3), isFalse);
    await loadChapter(e.id, 'John', 3);
    // ignore: avoid_print
    print('глава: ${sw.elapsedMilliseconds} мс');
    expect(hasChapter(e.id, 'John', 3), isTrue);
    final b = loadBook(e.id, 'John');
    final v16 = b.items[b.indexOf(3, 16)];
    expect(v16.text, contains('loved'));
    expect(onlineCopyright(e.id), contains('Lockman'));
  });

  test('синодальная нумерация: Пс 21:2 = западный Пс 22:1 (helloao и API.Bible)', () async {
    await store.install(cat.firstWhere((c) => c.id == 'hao-eng_bbe'));
    final bbe = loadBook('hao-eng_bbe', 'Ps');
    expect(bbe.items[bbe.indexOf(21, 2)].text, contains('My God, my God'));
    expect(bbe.items.firstWhere((i) => i.kind == ItemKind.verse && i.chapter == 22 && i.verse == 1).text, contains('The Lord takes care of me'));
    final amp = cat.firstWhere((c) => c.name == 'AMP' && c.json['online'] != null).id;
    await loadChapter(amp, 'Ps', 21);
    final ps = loadBook(amp, 'Ps');
    expect(ps.items[ps.indexOf(21, 2)].text, contains('My God, my God'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('API.Bible: разбор главы — заголовок, стихи, курсив добавленных слов', () {
    final (v, h, _) = parseChapter([
      {
        'name': 'para', 'type': 'tag', 'attrs': {'style': 's'},
        'items': [{'text': 'The New Birth', 'type': 'text'}],
      },
      {
        'name': 'para', 'type': 'tag', 'attrs': {'style': 'p'},
        'items': [
          {'name': 'verse', 'type': 'tag', 'attrs': {'number': '1', 'style': 'v'}, 'items': [{'text': '1', 'type': 'text'}]},
          {'text': 'Now there was ', 'type': 'text', 'attrs': {'verseId': 'JHN.3.1'}},
          {'name': 'char', 'type': 'tag', 'attrs': {'style': 'it'}, 'items': [{'text': 'a man', 'type': 'text', 'attrs': {'verseId': 'JHN.3.1'}}]},
          {'name': 'verse', 'type': 'tag', 'attrs': {'number': '2', 'style': 'v'}, 'items': [{'text': '2', 'type': 'text'}]},
          {'text': 'who came.', 'type': 'text', 'attrs': {'verseId': 'JHN.3.2'}},
        ],
      },
    ]);
    expect(v, ['Now there was ‹a man›', 'who came.']);
    expect(h, {1: 'The New Birth'});
  });
}

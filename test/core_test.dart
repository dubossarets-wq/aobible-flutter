// Проверка ядра на настоящих данных: установка RST+ с aobible.app → SQLite, книга, поиск FTS5.
import 'dart:io';

import 'package:aobible/core/bible.dart';
import 'package:aobible/core/books.dart';
import 'package:aobible/core/modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // настоящая сеть

  test('RST+: установка, книга, поиск', () async {
    await Books.load();
    final dir = Directory('${Directory.systemTemp.path}/aob_test_modules');
    final store = await ModuleStore.initAt(dir);
    if (store.get('rst-plus') == null) {
      final sw = Stopwatch()..start();
      final cat = await store.catalog();
      await store.install(cat.firstWhere((e) => e.id == 'rst-plus'));
      // ignore: avoid_print
      print('установка RST+: ${sw.elapsedMilliseconds} мс, файл ${(File(store.get('rst-plus')!.path).lengthSync() / 1e6).toStringAsFixed(1)} МБ');
    }
    for (final b in ['Ps', 'John', 'Gen']) {
      final sw = Stopwatch()..start();
      final book = loadBook('rst-plus', b);
      // ignore: avoid_print
      print('книга $b: ${book.items.length} строк, ${sw.elapsedMicroseconds / 1000} мс');
    }
    final john = loadBook('rst-plus', 'John');
    expect(john.items[john.indexOf(3, 16)].verse, 16);
    expect(Books.instance.parseHuman('Ин 3:16'), const VerseRef('John', 3, 16));
    for (final q in ['Бог', 'возлюбил Бог мир', 'любовь']) {
      final sw = Stopwatch()..start();
      final hits = search('rst-plus', q);
      // ignore: avoid_print
      print('поиск «$q»: ${hits.length} стихов, ${sw.elapsedMilliseconds} мс');
    }
    expect(search('rst-plus', 'возлюбил Бог мир').any((h) => h.ref == const VerseRef('John', 3, 16)), true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// Закладки и выделения: правки данных, подписи ссылок, сохранение в prefs в формате веб-версии.
import 'dart:convert';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/bookmarks/marks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await Books.load();
  });

  const jn316 = VerseRef('John', 3, 16);

  test('подпись выделения: один стих, подряд, вразнобой, разные главы', () {
    expect(selectionLabel([jn316]), contains('3:16'));
    expect(selectionLabel([jn316, const VerseRef('John', 3, 17), const VerseRef('John', 3, 18)]), endsWith('3:16–18'));
    expect(selectionLabel([jn316, const VerseRef('John', 3, 18)]), endsWith('3:16, 18'));
    expect(selectionLabel([jn316, const VerseRef('John', 4, 1)]), contains('; '));
    expect(quoteLabel([jn316, const VerseRef('John', 3, 17)]), endsWith('3:16-17'));
    expect(quoteVerse('  Так  возлюбил\nБог ', 'Ин. 3:16'), '"Так возлюбил Бог" - Ин. 3:16');
  });

  test('стихи сортируются как в Библии', () {
    final s = sortedRefs([const VerseRef('Rev', 1, 1), const VerseRef('John', 3, 16), const VerseRef('Gen', 2, 3), const VerseRef('Gen', 1, 9)]);
    expect([for (final r in s) r.book], ['Gen', 'Gen', 'John', 'Rev']);
    expect(s[0].chapter, 1);
  });

  test('закладка, любимый, заметка, выделение, подборка — формат как в веб-версии', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(marksProvider.notifier);
    n.toggleBookmark(jn316, 'Так возлюбил');
    n.setFavorite(jn316, 'Так возлюбил', true);
    n.setNote(jn316, 'моя мысль', 'Ин. 3:16');
    n.setHighlight([jn316, const VerseRef('John', 3, 17)], '2');
    n.addToCollection(null, [
      {'book': 'John', 'chapter': 3, 'verse': 16, 'text': 'Так'}
    ], 'К уроку', 'Подборка');

    final b = jsonDecode(prefs.getString('bookmarks')!) as List;
    expect(b.single['book'], 'John');
    expect(b.single['text'], 'Так возлюбил');
    expect(b.single['at'], isA<int>());
    expect((jsonDecode(prefs.getString('favorites')!) as List).single['verse'], 16);
    final notes = jsonDecode(prefs.getString('notes')!) as Map;
    expect(notes['John.3.16']['text'], 'моя мысль');
    expect(notes['John.3.16']['updated'], isA<int>());
    expect(jsonDecode(prefs.getString('highlights')!), {'John.3.16': '2', 'John.3.17': '2'});
    final cols = jsonDecode(prefs.getString('collections')!) as List;
    expect(cols.single['name'], 'К уроку');
    expect((cols.single['items'] as List).single['text'], 'Так');

    final f = c.read(marksProvider).flags;
    expect(f['John.3.16'], allOf(contains('b'), contains('f'), contains('n'), contains('2'), contains('c')));
    expect(f['John.3.17'], '2');

    // та же подборка: стих не дублируется
    final id = cols.single['id'] as String;
    n.addToCollection(id, [
      {'book': 'John', 'chapter': 3, 'verse': 16, 'text': 'Так'},
      {'book': 'John', 'chapter': 3, 'verse': 17, 'text': 'Ибо'}
    ], null, 'Подборка');
    expect(((jsonDecode(prefs.getString('collections')!) as List).single['items'] as List).length, 2);

    // перезапуск: всё читается обратно
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final m = c2.read(marksProvider);
    expect(m.isBookmarked(jn316), isTrue);
    expect(m.isFavorite(jn316), isTrue);
    expect(m.noteOf(jn316)!['text'], 'моя мысль');
    expect(m.highlights.length, 2);
  });

  test('заметка: пустой текст удаляет, дата создания сохраняется при правке', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(marksProvider.notifier);
    n.setNote(jn316, 'раз', 'x');
    final at = c.read(marksProvider).noteOf(jn316)!['at'];
    await Future<void>.delayed(const Duration(milliseconds: 5));
    n.setNote(jn316, 'два', 'x');
    expect(c.read(marksProvider).noteOf(jn316)!['at'], at);
    expect(c.read(marksProvider).noteOf(jn316)!['updated'], greaterThan(at as int));
    n.setNote(jn316, '  ', 'x');
    expect(c.read(marksProvider).noteOf(jn316), isNull);
    expect(jsonDecode(prefs.getString('notes')!), isEmpty);
  });

  test('«Отменить»: элемент возвращается на своё место, но не дублируется', () {
    expect(putBack([1, 2, 4], 2, 3), [1, 2, 3, 4]);
    expect(putBack([1, 2, 3], 1, 2), [1, 2, 3]);
    expect(putBack([1], 9, 2), [1, 2]);
  });

  test('повреждённые данные в prefs не ломают чтение', () async {
    SharedPreferences.setMockInitialValues({'bookmarks': '{не json', 'notes': '[1]', 'highlights': '"x"'});
    prefs = await SharedPreferences.getInstance();
    final m = loadMarks();
    expect(m.bookmarks, isEmpty);
    expect(m.notes, isEmpty);
    expect(m.highlights, isEmpty);
  });
}

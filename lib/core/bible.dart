// Текст книги для чтения: плоский список элементов (заголовок главы, заголовок раздела, стих) —
// его рисует ленивый список, на экране строятся только видимые строки. Книга читается одним запросом.
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'books.dart';
import 'markup.dart';
import 'modules.dart';

enum ItemKind { chapter, heading, verse }

class ReaderItem {
  ReaderItem.chapter(this.chapter)
      : kind = ItemKind.chapter,
        verse = 0,
        text = '';
  ReaderItem.heading(this.chapter, this.verse, this.text) : kind = ItemKind.heading;
  ReaderItem.verse(this.chapter, this.verse, this.text) : kind = ItemKind.verse;

  final ItemKind kind;
  final int chapter;
  final int verse;
  final String text; // для стиха — сырой текст с разметкой
  List<Token>? _tokens;
  List<Token> get tokens => _tokens ??= parseVerse(text);
  List<Word>? _words;
  List<Word> get words => _words ??= wordsOf(tokens);
}

class BookText {
  BookText(this.module, this.book, this.items, this._index, this.chapterCount);
  final String module;
  final String book;
  final List<ReaderItem> items;
  final Map<int, int> _index; // chapter * 1000 + verse → индекс элемента
  final int chapterCount;

  /// Индекс элемента для перехода к стиху: стих 1 — заголовок главы, остальные — сам стих (или ближайший)
  int indexOf(int chapter, int verse) {
    if (verse <= 1) return _index[chapter * 1000] ?? 0;
    for (var v = verse; v > 0; v--) {
      final i = _index[chapter * 1000 + v];
      if (i != null) return i;
    }
    return _index[chapter * 1000] ?? 0;
  }

  /// Элемент ровно этого стиха (null — такого стиха в книге нет)
  int? exactIndex(int chapter, int verse) => _index[chapter * 1000 + verse];

  /// Ссылка на стих по индексу элемента (для шапки и запоминания места)
  VerseRef refAt(int index) {
    final i = index.clamp(0, items.length - 1);
    for (var k = i; k < items.length; k++) {
      final it = items[k];
      if (it.kind == ItemKind.verse) return VerseRef(book, it.chapter, it.verse);
      if (k > i + 3) break;
    }
    final it = items[i];
    return VerseRef(book, it.chapter, it.verse == 0 ? 1 : it.verse);
  }
}

final _cache = <String, BookText>{};

/// Книга изменилась (перевод по сети: пришла глава) — следующее чтение из базы
void forgetBook(String moduleId, String book) => _cache.remove('$moduleId|$book');

BookText loadBook(String moduleId, String book) {
  final key = '$moduleId|$book';
  final hit = _cache.remove(key);
  if (hit != null) return _cache[key] = hit; // в конец очереди
  final db = ModuleStore.instance.db(moduleId);
  final verses = db.select('SELECT chapter, verse, text FROM verses WHERE book = ? ORDER BY chapter, verse', [book]);
  final heads = <int, String>{};
  for (final r in db.select('SELECT chapter, verse, text FROM headings WHERE book = ?', [book])) {
    heads[(r['chapter'] as int) * 1000 + (r['verse'] as int)] = r['text'] as String;
  }
  final items = <ReaderItem>[];
  final index = <int, int>{};
  var lastChapter = 0;
  for (final r in verses) {
    final c = r['chapter'] as int, v = r['verse'] as int;
    if (c != lastChapter) {
      index[c * 1000] = items.length;
      items.add(ReaderItem.chapter(c));
      lastChapter = c;
    }
    final h = heads[c * 1000 + v];
    if (h != null) items.add(ReaderItem.heading(c, v, h));
    index[c * 1000 + v] = items.length;
    items.add(ReaderItem.verse(c, v, r['text'] as String));
  }
  final text = BookText(moduleId, book, items, index, lastChapter);
  _cache[key] = text;
  if (_cache.length > 12) _cache.remove(_cache.keys.first);
  return text;
}

/// Книги перевода в порядке модуля: [{id, name, short, chapters}]
List<Map<String, dynamic>> bookList(String moduleId) =>
    ((ModuleStore.instance.get(moduleId)?.meta['bookList'] as List?) ?? const []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();

class SearchHit {
  SearchHit(this.ref, this.snippet);
  final VerseRef ref;
  final String snippet; // текст с выделением [слово]
}

/// Поиск по всему переводу (FTS5): слова с любым окончанием, порядок — как в Библии
List<SearchHit> search(String moduleId, String query, {int limit = 2000}) {
  final words = query.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final match = words.map((w) => '"$w"*').join(' ');
  final db = ModuleStore.instance.db(moduleId);
  final rows = db.select(
    'SELECT v.book, v.chapter, v.verse, v.text FROM verses_fts f JOIN verses v ON v.id = f.rowid WHERE verses_fts MATCH ? ORDER BY f.rowid LIMIT ?',
    [match, limit],
  );
  return [for (final r in rows) SearchHit(VerseRef(r['book'] as String, r['chapter'] as int, r['verse'] as int), plainText(r['text'] as String))];
}

/// Регулярное выражение запроса — как queryRegex в веб-версии (core/search.js): все слова фразы по порядку,
/// часть слова тоже подходит («свет» найдёт «светильник»); «ё» = «е»; знак ударения в тексте не мешает.
RegExp? queryRegex(String query, {bool wholeWord = false}) {
  final q = query.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll('\u0301', '');
  if (q.isEmpty) return null;
  final letter = RegExp(r'\p{L}', unicode: true);
  final body = StringBuffer();
  for (final ch in q.runes.map(String.fromCharCode)) {
    if (ch == ' ') {
      body.write(r'[\s\p{P}]+');
    } else if ('еёЕЁ'.contains(ch)) {
      body.write('[её]\u0301?');
    } else {
      body.write(RegExp.escape(ch));
      if (letter.hasMatch(ch)) body.write('\u0301?');
    }
  }
  final pat = wholeWord ? r'(?<!\p{L})' '$body' r'(?!\p{L})' : '$body';
  return RegExp(pat, unicode: true, caseSensitive: false);
}

/// Поиск фразы по переводу, как в веб-версии: проход по тексту всех стихов (индекс FTS5 ищет только начала слов,
/// а здесь нужна и середина слова) — в отдельном потоке, порядок — как в Библии. books — только эти книги.
// Текст перевода без разметки — для поиска: готовится один раз в отдельном потоке (чтение базы и разбор разметки —
// самое долгое), дальше каждый запрос идёт по готовым строкам. В памяти — последние 4 перевода (~5 МБ каждый)
typedef _PlainVerse = (String book, int chapter, int verse, String text);
final _plain = <String, Future<List<_PlainVerse>>>{};
final _ready = <String, List<_PlainVerse>>{};

Future<List<_PlainVerse>> _plainOf(String moduleId, String path) {
  final key = '$moduleId|$path'; // путь меняется при обновлении модуля — старый текст не используется
  final hit = _plain.remove(key);
  if (hit != null) return _plain[key] = hit; // в конец — недавно нужный
  while (_plain.length >= 4) {
    _ready.remove(_plain.keys.first);
    _plain.remove(_plain.keys.first);
  }
  final f = Isolate.run(() {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return [
        for (final r in db.select('SELECT book, chapter, verse, text FROM verses ORDER BY id'))
          (r['book'] as String, r['chapter'] as int, r['verse'] as int, plainText(r['text'] as String)),
      ];
    } finally {
      db.close();
    }
  });
  f.then<void>((rows) {
    if (_plain.containsKey(key)) _ready[key] = rows;
  }, onError: (Object _) {
    _plain.remove(key); // не удалось — в следующий раз попробуем заново
  });
  return _plain[key] = f;
}

/// Заранее готовит текст перевода для поиска (окно поиска открыли — первый запрос уже быстрый)
void warmSearch(String moduleId) {
  final path = ModuleStore.instance.get(moduleId)?.path;
  if (path != null) _plainOf(moduleId, path).ignore();
}

Future<List<SearchHit>> searchText(String moduleId, String query, {Set<String>? books, bool wholeWord = false}) async {
  final path = ModuleStore.instance.get(moduleId)?.path;
  final re = queryRegex(query, wholeWord: wholeWord);
  if (path == null || re == null) return const [];
  final rows = _ready['$moduleId|$path'];
  if (rows == null) {
    // текст ещё готовится — этот запрос ищет сам в отдельном потоке (возвращает только найденное), а текст для
    // следующих запросов готовится рядом
    _plainOf(moduleId, path).ignore();
    return Isolate.run(() {
      final re = queryRegex(query, wholeWord: wholeWord)!;
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        final out = <SearchHit>[];
        for (final r in db.select('SELECT book, chapter, verse, text FROM verses ORDER BY id')) {
          final book = r['book'] as String;
          if (books != null && !books.contains(book)) continue;
          final text = plainText(r['text'] as String);
          if (re.hasMatch(text)) out.add(SearchHit(VerseRef(book, r['chapter'] as int, r['verse'] as int), text));
        }
        return out;
      } finally {
        db.close();
      }
    });
  }
  // готовый текст: проход по строкам — десятки миллисекунд
  final out = <SearchHit>[];
  for (final (book, c, v, text) in rows) {
    if (books != null && !books.contains(book)) continue;
    if (re.hasMatch(text)) out.add(SearchHit(VerseRef(book, c, v), text));
  }
  return out;
}

/// Текст стиха без разметки; null — такого стиха нет
String? verseAt(String moduleId, VerseRef r) {
  if (ModuleStore.instance.get(moduleId) == null) return null;
  final rows = ModuleStore.instance.db(moduleId).select('SELECT text FROM verses WHERE book = ? AND chapter = ? AND verse = ?', [r.book, r.chapter, r.verse]);
  return rows.isEmpty ? null : plainText(rows.first['text'] as String);
}

/// Слова стиха, которые подсвечиваются после перехода из поиска (highlightRegex в веб-версии): слова запроса
/// длиннее одной буквы, часть слова тоже подходит; «ё» = «е». Возвращает номера слов (индексы в item.words).
Set<int> highlightWords(ReaderItem item, String query) {
  final res = [
    for (final w in query.split(RegExp(r'[\s\p{P}]+', unicode: true)))
      if (w.length > 1) queryRegex(w),
  ].whereType<RegExp>().toList();
  if (res.isEmpty) return const {};
  final out = <int>{};
  final words = item.words;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final text = item.tokens[w.token].text.substring(w.start, w.end);
    if (res.any((r) => r.hasMatch(text))) out.add(i);
  }
  return out;
}

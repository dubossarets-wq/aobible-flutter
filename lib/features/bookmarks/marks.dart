// Закладки, любимые стихи, заметки, выделения, подборки — данные и их хранение.
// Ключи и форматы те же, что в веб-версии (App.jsx, core/highlights.js), чтобы подходил перенос из старого
// приложения и файл «Мои данные»:
//   bookmarks   [{book,chapter,verse,text,at}]
//   favorites   [{book,chapter,verse,text,at,part?:{from,to}}]
//   notes       {"Книга.глава.стих": {text,label,at,updated}}
//   highlights  {"Книга.глава.стих": "1".."6"}, highlightLabels {"1": "подпись"}
//   collections [{id,name,at,items:[{book,chapter,verse,text,at}]}]
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/markup.dart';
import '../../core/settings.dart';
import '../hub.dart';

/// Цвета выделения (оттенки Okabe–Ito, как в веб-версии): id → название, цвет
class HlColor {
  const HlColor(this.id, this.name, this.color);
  final String id, name;
  final Color color;
}

const hlColors = [
  HlColor('1', 'Жёлтый', Color(0xfff3d36b)),
  HlColor('2', 'Голубой', Color(0xff7fc4ec)),
  HlColor('3', 'Зелёный', Color(0xff7ccfa4)),
  HlColor('4', 'Оранжевый', Color(0xfff2a65a)),
  HlColor('5', 'Розовый', Color(0xffe79ac0)),
  HlColor('6', 'Сиреневый', Color(0xffb7a3e3)),
];
HlColor? hlColor(String? id) => hlColors.where((c) => c.id == id).firstOrNull;

/// Цвет любимого стиха (--love в веб-версии)
const loveColor = Color(0xffd9475e);

String refKey(VerseRef r) => '${r.book}.${r.chapter}.${r.verse}';
String itemKey(Map x) => '${x['book']}.${x['chapter']}.${x['verse']}';

VerseRef? parseKey(String k) {
  final p = k.split('.');
  if (p.length != 3) return null;
  final c = int.tryParse(p[1]), v = int.tryParse(p[2]);
  return c == null || v == null ? null : VerseRef(p[0], c, v);
}

VerseRef? refOf(Map x) {
  final c = x['chapter'], v = x['verse'], b = x['book'];
  return b is String && c is num && v is num ? VerseRef(b, c.toInt(), v.toInt()) : null;
}

int byBible(VerseRef x, VerseRef y) {
  final b = Books.instance;
  final o = b.order(x.book) - b.order(y.book);
  if (o != 0) return o;
  return x.chapter != y.chapter ? x.chapter - y.chapter : x.verse - y.verse;
}

/// Стихи в порядке Библии
List<VerseRef> sortedRefs(Iterable<VerseRef> refs) => refs.toList()..sort(byBible);

/// «Нав. 18:5», «Нав. 18:5–7» (подряд) или «Нав. 18:5, 7, 9»
String selectionLabel(List<VerseRef> refs, {bool full = false}) {
  if (refs.isEmpty) return '';
  final b = Books.instance;
  final first = refs.first;
  String one(VerseRef r) => b.formatRef(r.book, r.chapter, r.verse, full: full);
  if (refs.length == 1) return one(first);
  if (refs.every((r) => r.book == first.book && r.chapter == first.chapter)) {
    final vs = [for (final r in refs) r.verse];
    var contiguous = true;
    for (var i = 1; i < vs.length; i++) {
      if (vs[i] != vs[i - 1] + 1) contiguous = false;
    }
    final m = b.meta(first.book);
    return '${full ? m.name : m.short} ${first.chapter}:${contiguous ? '${vs.first}–${vs.last}' : vs.join(', ')}';
  }
  return refs.map(one).join('; ');
}

/// Единый формат копирования и «Поделиться»: "Текст стиха" - Еккл. 9:6 (диапазон — через обычный дефис)
String quoteLabel(List<VerseRef> refs) => selectionLabel(refs).replaceAll('–', '-');
String quoteVerse(String text, String label) => '"${text.replaceAll(RegExp(r'\s+'), ' ').trim()}" - $label';

/// Текст стиха из перевода (без разметки) или null, если перевода/стиха нет
String? verseText(String moduleId, VerseRef r) {
  try {
    final book = loadBook(moduleId, r.book);
    // Для стиха 1 indexOf даёт заголовок главы — стих следует за ним (после названий разделов)
    for (var k = book.indexOf(r.chapter, r.verse); k < book.items.length && k < book.indexOf(r.chapter, r.verse) + 6; k++) {
      final it = book.items[k];
      if (it.kind == ItemKind.verse && it.chapter == r.chapter && it.verse == r.verse) return plainText(it.text);
      if (it.chapter > r.chapter) break;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Текст нескольких стихов: у одного — без номера, у нескольких — «номер текст» по строкам
String selectionText(String moduleId, List<VerseRef> refs) {
  final lines = <String>[];
  for (final r in refs) {
    final v = verseText(moduleId, r);
    if (v != null) lines.add(refs.length > 1 ? '${r.verse} $v' : v);
  }
  return lines.join('\n');
}

/// Текст для копирования: несколько стихов — в одних кавычках через пробел
String quoteText(String moduleId, List<VerseRef> refs) {
  final parts = [for (final r in refs) verseText(moduleId, r)?.trim()].whereType<String>().where((s) => s.isNotEmpty);
  return quoteVerse(parts.join(' '), quoteLabel(refs));
}

typedef Json = Map<String, dynamic>;

/// Снимок всех пользовательских отметок (неизменяемый: правки создают новый)
class Marks {
  Marks({this.bookmarks = const [], this.favorites = const [], this.notes = const {}, this.highlights = const {}, this.hlLabels = const {}, this.collections = const []});
  final List<Json> bookmarks, favorites, collections;
  final Json notes;
  final Map<String, String> highlights, hlLabels;

  Marks copyWith({List<Json>? bookmarks, List<Json>? favorites, Json? notes, Map<String, String>? highlights, Map<String, String>? hlLabels, List<Json>? collections}) => Marks(
        bookmarks: bookmarks ?? this.bookmarks,
        favorites: favorites ?? this.favorites,
        notes: notes ?? this.notes,
        highlights: highlights ?? this.highlights,
        hlLabels: hlLabels ?? this.hlLabels,
        collections: collections ?? this.collections,
      );

  /// «Книга.глава.стих» → флаги: f любимый, p любимая часть, b закладка, n заметка, c в подборке, цифра — цвет.
  /// Считается один раз на снимок — строка стиха берёт готовое за O(1).
  late final Map<String, String> flags = _flags();
  Map<String, String> _flags() {
    final m = <String, String>{};
    void add(String k, String f) => m[k] = (m[k] ?? '') + f;
    for (final x in favorites) {
      add(itemKey(x), x['part'] != null ? 'p' : 'f');
    }
    for (final x in bookmarks) {
      add(itemKey(x), 'b');
    }
    for (final k in notes.keys) {
      add(k, 'n');
    }
    for (final c in collections) {
      for (final x in (c['items'] as List? ?? const []).whereType<Map>()) {
        if (!(m[itemKey(x)]?.contains('c') ?? false)) add(itemKey(x), 'c');
      }
    }
    highlights.forEach((k, c) => add(k, c));
    return m;
  }

  bool isBookmarked(VerseRef r) => bookmarks.any((b) => itemKey(b) == refKey(r));
  bool isFavorite(VerseRef r) => favorites.any((b) => itemKey(b) == refKey(r));
  Json? noteOf(VerseRef r) => notes[refKey(r)] as Json?;

  // --- правки (возвращают новый снимок) ---

  Marks withBookmarkToggled(VerseRef r, String text, int now) => isBookmarked(r)
      ? copyWith(bookmarks: [for (final b in bookmarks) if (itemKey(b) != refKey(r)) b])
      : copyWith(bookmarks: [{'book': r.book, 'chapter': r.chapter, 'verse': r.verse, 'text': text, 'at': now}, ...bookmarks]);

  Marks withFavorite(VerseRef r, String text, bool on, int now) {
    final rest = [for (final b in favorites) if (itemKey(b) != refKey(r)) b];
    return copyWith(favorites: on ? [{'book': r.book, 'chapter': r.chapter, 'verse': r.verse, 'text': text, 'at': now}, ...rest] : rest);
  }

  /// Любимая часть стиха: слова from..to; заменяет прежнюю отметку этого стиха (App.jsx addFavoritePart)
  Marks withFavoritePart(VerseRef r, String text, int from, int to, int now) => copyWith(favorites: [
        {'book': r.book, 'chapter': r.chapter, 'verse': r.verse, 'text': text, 'part': {'from': from, 'to': to}, 'at': now},
        for (final b in favorites) if (itemKey(b) != refKey(r)) b,
      ]);

  /// «Книга.глава.стих» → слова любимой части (включительно)
  late final Map<String, (int, int)> favParts = {
    for (final x in favorites)
      if (x['part'] is Map && (x['part'] as Map)['from'] is num && (x['part'] as Map)['to'] is num) itemKey(x): (((x['part'] as Map)['from'] as num).toInt(), ((x['part'] as Map)['to'] as num).toInt()),
  };

  /// Заметка хранится у первого из выделенных стихов; пустой текст — удалить
  Marks withNote(VerseRef r, String text, String label, int now) {
    final next = {...notes};
    if (text.trim().isEmpty) {
      next.remove(refKey(r));
    } else {
      next[refKey(r)] = {'text': text, 'label': label, 'at': (notes[refKey(r)] as Map?)?['at'] ?? now, 'updated': now};
    }
    return copyWith(notes: next);
  }

  Marks withHighlight(Iterable<VerseRef> refs, String? color) {
    final next = {...highlights};
    for (final r in refs) {
      color == null ? next.remove(refKey(r)) : next[refKey(r)] = color;
    }
    return copyWith(highlights: next);
  }

  /// В подборку: существующую (id) или новую (id == null, имя); стихи, уже бывшие в ней, не дублируются
  Marks withCollection(String? id, List<Json> items, String? newName, int now, String newId, String defaultName) {
    var list = collections;
    final cid = id ?? newId;
    if (id == null) list = [{'id': cid, 'name': newName ?? defaultName, 'at': now, 'items': <Json>[]}, ...list];
    return copyWith(collections: [
      for (final c in list)
        if (c['id'] != cid)
          c
        else
          () {
            final have = {for (final x in (c['items'] as List).whereType<Map>()) itemKey(x)};
            final add = [for (final x in items) if (!have.contains(itemKey(x))) {...x, 'at': now}];
            return <String, dynamic>{...c, 'items': [...(c['items'] as List), ...add]};
          }()
    ]);
  }
}

/// «Отменить»: вернуть элемент на прежнее место списка (если его там уже нет)
List<T> putBack<T>(List<T> list, int i, T x, [bool Function(T)? same]) {
  final has = same ?? (T a) => a == x;
  final at = i.clamp(0, list.length);
  return list.any(has) ? list : [...list.take(at), x, ...list.skip(at)];
}

List<Json> _list(String key) {
  try {
    final raw = prefs.getString(key);
    if (raw == null) return const [];
    return [for (final x in jsonDecode(raw) as List) if (x is Map) x.cast<String, dynamic>()];
  } catch (_) {
    return const [];
  }
}

Map<String, dynamic> _map(String key) {
  try {
    final raw = prefs.getString(key);
    return raw == null ? const {} : (jsonDecode(raw) as Map).cast<String, dynamic>();
  } catch (_) {
    return const {};
  }
}

Marks loadMarks() => Marks(
      bookmarks: _list('bookmarks'),
      favorites: _list('favorites'),
      notes: {for (final e in _map('notes').entries) if (e.value is Map) e.key: (e.value as Map).cast<String, dynamic>()},
      highlights: {for (final e in _map('highlights').entries) if (e.value != null) e.key: '${e.value}'},
      hlLabels: {for (final e in _map('highlightLabels').entries) if (e.value != null) e.key: '${e.value}'},
      collections: [
        for (final c in _list('collections')) {...c, 'items': [for (final x in (c['items'] as List? ?? const []).whereType<Map>()) x.cast<String, dynamic>()]}
      ],
    );

class MarksNotifier extends Notifier<Marks> {
  @override
  Marks build() => loadMarks();

  /// Применить правку, сохранить изменившееся и перерисовать отметки у стихов
  void update(Marks Function(Marks m) change) {
    final old = state, next = change(old);
    state = next;
    void save(String key, Object now, Object before) {
      if (!identical(now, before)) prefs.setString(key, jsonEncode(now));
    }

    save('bookmarks', next.bookmarks, old.bookmarks);
    save('favorites', next.favorites, old.favorites);
    save('notes', next.notes, old.notes);
    save('highlights', next.highlights, old.highlights);
    save('highlightLabels', next.hlLabels, old.hlLabels);
    save('collections', next.collections, old.collections);
    ref.read(decorVersionProvider.notifier).bump();
  }

  /// Данные в prefs заменили снаружи (перенос, восстановление) — прочитать заново
  void reload() {
    state = loadMarks();
    ref.read(decorVersionProvider.notifier).bump();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;
  void toggleBookmark(VerseRef r, String text) => update((m) => m.withBookmarkToggled(r, text, _now));
  void setFavorite(VerseRef r, String text, bool on) => update((m) => m.withFavorite(r, text, on, _now));
  void setFavorites(Iterable<(VerseRef, String)> items, bool on) => update((m) {
        var x = m;
        for (final (r, text) in items) {
          x = x.withFavorite(r, text, on, _now);
        }
        return x;
      });
  void setFavoritePart(VerseRef r, String text, int from, int to) => update((m) => m.withFavoritePart(r, text, from, to, _now));
  void setNote(VerseRef r, String text, String label) => update((m) => m.withNote(r, text, label, _now));
  void setHighlight(Iterable<VerseRef> refs, String? color) => update((m) => m.withHighlight(refs, color));
  void addToCollection(String? id, List<Json> items, String? name, String defaultName) =>
      update((m) => m.withCollection(id, items, name, _now, _now.toRadixString(36), defaultName));
}

final marksProvider = NotifierProvider<MarksNotifier, Marks>(MarksNotifier.new);

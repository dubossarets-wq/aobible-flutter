// История всех мест, где человек читал, с датой и временем («Ещё» → «История»). Каждая открытая глава — запись
// {b, c, v, s, t}: книга, глава, стих, где остановился, начало и последний раз (мс). Вернулся в ту же главу в течение
// получаса — продлевается старая запись, а не появляется новая. Хранится в prefs «readingHistory» — служебный ключ:
// в файл «Мои данные» и резервные копии не входит (до 3000 записей заняли бы место копий настроек и закладок).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'books.dart';
import 'settings.dart' show prefs;

class HistoryEntry {
  HistoryEntry({required this.book, required this.chapter, required this.verse, required this.start, required this.time});
  final String book;
  final int chapter;
  int verse;
  final int start; // мс
  int time; // мс

  VerseRef get ref => VerseRef(book, chapter, verse < 1 ? 1 : verse);
  Map<String, Object> toJson() => {'b': book, 'c': chapter, 'v': verse, 's': start, 't': time};
  static HistoryEntry? fromJson(Object? x) {
    if (x is! Map || x['b'] is! String || x['c'] is! num || x['t'] is! num) return null;
    final t = (x['t'] as num).toInt();
    return HistoryEntry(book: x['b'] as String, chapter: (x['c'] as num).toInt(), verse: ((x['v'] as num?) ?? 0).toInt(), start: ((x['s'] as num?) ?? t).toInt(), time: t);
  }
}

class ReadingHistory extends ChangeNotifier {
  ReadingHistory._();
  static final instance = ReadingHistory._();

  static const _key = 'readingHistory';
  static const _limit = 3000;
  static const _merge = 30 * 60 * 1000;

  List<HistoryEntry>? _items;
  Timer? _timer;

  /// Старые в начале, новые в конце
  List<HistoryEntry> get items => _items ??= _load();

  List<HistoryEntry> _load() {
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return [for (final x in jsonDecode(raw) as List) ?HistoryEntry.fromJson(x)];
    } catch (_) {
      return [];
    }
  }

  /// Человек сейчас в этом месте
  void record(VerseRef at) {
    final list = items;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var k = list.length - 1; k >= 0 && now - list[k].time < _merge; k--) {
      final e = list[k];
      if (e.book == at.book && e.chapter == at.chapter) {
        if (at.verse > 0) e.verse = at.verse;
        e.time = now;
        if (k != list.length - 1) list.add(list.removeAt(k));
        _changed();
        return;
      }
    }
    list.add(HistoryEntry(book: at.book, chapter: at.chapter, verse: at.verse, start: now, time: now));
    if (list.length > _limit) list.removeRange(0, list.length - _limit);
    _changed();
  }

  void remove(Iterable<HistoryEntry> gone) {
    final s = gone.toSet();
    items.removeWhere(s.contains);
    _changed();
  }

  void restore(List<HistoryEntry> back) {
    items
      ..addAll(back)
      ..sort((a, b) => a.time.compareTo(b.time));
    _changed();
  }

  void _changed() {
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), save);
  }

  void save() {
    _timer?.cancel();
    prefs.setString(_key, jsonEncode([for (final e in items) e.toJson()]));
  }
}

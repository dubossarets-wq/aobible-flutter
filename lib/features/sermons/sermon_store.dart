// Проповеди (src/core/sermons.js): заголовок, дата и блоки по порядку — стихи (с текстом на момент добавления) и свой текст.
// Хранятся в prefs «sermons» тем же форматом, что в веб-версии:
// { id, title, date, blocks: [{ id, type: 'verse', book, chapter, verse, to, text, texts?, moduleId, part? } | { id, type: 'text', text }],
//   createdAt, updatedAt }. Несколько стихов подряд — один блок (verse…to): text — весь текст одной строкой (его читают и старые
// версии приложения), texts — тот же текст по стихам, чтобы показать каждый стих с нового абзаца и убрать любой из середины.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/markup.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../plans/loc.dart';
import '../plans/verse_text.dart';

typedef Sermon = Map<String, dynamic>;
typedef Block = Map<String, dynamic>;

int _seq = 0;
String newId() => DateTime.now().millisecondsSinceEpoch.toRadixString(36) + (_seq++).toRadixString(36).padLeft(2, '0');

List<Sermon> loadSermons() {
  try {
    final raw = prefs.getString('sermons');
    if (raw == null) return [];
    final v = jsonDecode(raw);
    return v is List ? [for (final s in v) if (s is Map) Sermon.from(s)] : [];
  } catch (_) {
    return [];
  }
}

List<Block> blocksOf(Sermon s) => [for (final b in (s['blocks'] as List? ?? const [])) Block.from(b as Map)];
bool isVerse(Block b) => b['type'] == 'verse';

/// Текст блока по стихам: [текст 16, текст 17, …]; null — у старого блока-диапазона разбивки ещё нет
List<String>? verseTexts(Block b) {
  if (!isVerse(b)) return null;
  final to = b['to'] as int?;
  final verse = b['verse'] as int;
  if (to == null || to == verse) return ['${b['text']}'];
  final texts = b['texts'];
  return texts is List && texts.length == to - verse + 1 ? [for (final x in texts) '$x'] : null;
}

String _short(String book) => Books.instance.meta(book).short.replaceFirst(RegExp(r'\.$'), '');
String _part(Block b) => b['part'] == true ? ' ${t('(часть)')}' : '';

String blockRef(Block b) => '${_short(b['book'] as String)} ${b['chapter']}:${b['verse']}${b['to'] != null ? '–${b['to']}' : ''}${_part(b)}';
String blockRefFull(Block b) => '${Books.instance.meta(b['book'] as String).name} ${b['chapter']}:${b['verse']}${b['to'] != null ? '–${b['to']}' : ''}${_part(b)}';

/// Проповедь обычным текстом — чтобы отправить или распечатать
String sermonText(Sermon s) {
  final parts = <String>['${s['title']}'];
  final date = DateTime.tryParse('${s['date'] ?? ''}');
  if (date != null) parts.add(fmtDay(date, full: true, year: true));
  for (final b in blocksOf(s)) {
    if (isVerse(b)) {
      final tx = verseTexts(b);
      // Диапазон — каждый стих с новой строки, с номером
      final body = tx != null && tx.length > 1 ? [for (final (i, x) in tx.indexed) '${(b['verse'] as int) + i} $x'].join('\n') : '${b['text']}';
      parts.add('${blockRefFull(b)}\n«$body»');
    } else if ('${b['text']}'.trim().isNotEmpty) {
      parts.add('${b['text']}'.trim());
    }
  }
  return parts.join('\n\n');
}

/// Что добавляется: стих (текст уже известен)
class VerseItem {
  const VerseItem(this.book, this.chapter, this.verse, this.text, {this.moduleId, this.part = false});
  final String book;
  final int chapter, verse;
  final String text;
  final String? moduleId;
  final bool part; // часть стиха (выбранные слова)
}

/// Выделенные стихи → блоки: стихи подряд одной главы складываются в один блок «Ин 3:16–18»
List<Block> versesToBlocks(List<VerseItem> items, String moduleId) {
  final blocks = <Block>[];
  for (final it in items) {
    final last = blocks.isEmpty ? null : blocks.last;
    if (!it.part && last != null && last['part'] != true && last['book'] == it.book && last['chapter'] == it.chapter && ((last['to'] ?? last['verse']) as int) + 1 == it.verse) {
      last['to'] = it.verse;
      last['texts'] = [...((last['texts'] as List?) ?? [last['text']]), it.text];
      last['text'] = '${last['text']} ${it.text}';
    } else {
      blocks.add({'id': newId(), 'type': 'verse', 'book': it.book, 'chapter': it.chapter, 'verse': it.verse, 'to': null, 'text': it.text, 'moduleId': it.moduleId ?? moduleId, if (it.part) 'part': true});
    }
  }
  return blocks;
}

/// Блоки без одного стиха: блок-диапазон распадается на части до и после, одиночный стих убирается весь
List<Block> removeVerseFrom(List<Block> blocks, String blockId, int verse) {
  final out = <Block>[];
  for (final b in blocks) {
    if (b['id'] != blockId) {
      out.add(b);
      continue;
    }
    final texts = verseTexts(b);
    final v0 = b['verse'] as int;
    final to = (b['to'] as int?) ?? v0;
    if (texts == null || to == v0) continue;
    if (verse < v0 || verse > to) {
      out.add(b);
      continue;
    }
    List<Block> part(int from, int end, bool keepId) {
      if (from > end) return [];
      final tx = texts.sublist(from - v0, end - v0 + 1);
      final rest = Block.from(b)..remove('texts');
      return [
        {...rest, 'id': keepId ? b['id'] : newId(), 'verse': from, 'to': end > from ? end : null, 'text': tx.join(' '), if (end > from) 'texts': tx},
      ];
    }

    out.addAll([...part(v0, verse - 1, true), ...part(verse + 1, to, verse == v0)]);
  }
  return out;
}

class SermonsNotifier extends Notifier<List<Sermon>> {
  @override
  List<Sermon> build() => loadSermons();

  void _set(List<Sermon> next) {
    state = next;
    prefs.setString('sermons', jsonEncode(next));
  }

  void _touch(String id, Sermon Function(Sermon s) fn, {bool stamp = true}) =>
      _set([for (final s in state) s['id'] == id ? {...fn(s), if (stamp) 'updatedAt': DateTime.now().millisecondsSinceEpoch} : s]);

  Sermon? byId(String? id) => id == null ? null : state.where((s) => s['id'] == id).firstOrNull;

  String create(String title) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = <String, dynamic>{'id': newId(), 'title': title.trim().isEmpty ? t('Новая проповедь') : title.trim(), 'date': '', 'blocks': <dynamic>[], 'createdAt': now, 'updatedAt': now};
    _set([s, ...state]);
    return s['id'] as String;
  }

  void delete(String id) => _set([for (final s in state) if (s['id'] != id) s]);

  /// «Отменить» после удаления: проповедь возвращается на прежнее место
  void restore(Sermon s, int index) {
    if (state.any((x) => x['id'] == s['id'])) return;
    final next = [...state];
    next.insert(math.min(math.max(0, index), next.length), s);
    _set(next);
  }

  void rename(String id, String title) => _touch(id, (s) => {...s, 'title': title});
  void setDate(String id, String date) => _touch(id, (s) => {...s, 'date': date});

  /// Добавить стихи; at — куда вставить (номер блока), без него — в конец. Возвращает номера новых блоков.
  List<String> addVerses(String id, List<VerseItem> items, String moduleId, {int? at}) {
    final blocks = versesToBlocks(items, moduleId);
    _touch(id, (s) {
      final all = blocksOf(s);
      all.insertAll(at == null ? all.length : math.max(0, math.min(all.length, at)), blocks);
      return {...s, 'blocks': all};
    });
    return [for (final b in blocks) b['id'] as String];
  }

  String addTextBlock(String id, {int? after}) {
    final b = <String, dynamic>{'id': newId(), 'type': 'text', 'text': ''};
    _touch(id, (s) {
      final blocks = blocksOf(s);
      blocks.insert(after == null ? blocks.length : math.min(blocks.length, math.max(0, after + 1)), b);
      return {...s, 'blocks': blocks};
    });
    return b['id'] as String;
  }

  /// Правка текста при наборе: дата изменения тоже обновляется
  void updateBlock(String id, String blockId, Map<String, dynamic> patch) =>
      _touch(id, (s) => {...s, 'blocks': [for (final b in blocksOf(s)) b['id'] == blockId ? {...b, ...patch} : b]});

  void removeBlock(String id, String blockId) => _touch(id, (s) => {...s, 'blocks': [for (final b in blocksOf(s)) if (b['id'] != blockId) b]});

  void removeVerse(String id, String blockId, int verse) => _touch(id, (s) => {...s, 'blocks': removeVerseFrom(blocksOf(s), blockId, verse)});

  /// «Отменить»: блоки проповеди — как были
  void restoreBlocks(String id, List<Block> blocks) => _touch(id, (s) => {...s, 'blocks': blocks});

  /// Перестановка перетаскиванием: блок с места from — на место to (to — позиция после удаления, как у ReorderableListView)
  void moveBlock(String id, int from, int to) => _touch(id, (s) {
        final blocks = blocksOf(s);
        if (from < 0 || from >= blocks.length) return s;
        final b = blocks.removeAt(from);
        blocks.insert(math.min(math.max(0, to), blocks.length), b);
        return {...s, 'blocks': blocks};
      });

  final _tried = <String>{};

  /// Старые проповеди: у диапазона хранился только общий текст. Берём стихи из того же перевода и, если вместе они дают
  /// ровно сохранённый текст, запоминаем разбивку. Сам текст не меняется, дата изменения — тоже (это не правка человека).
  void fillVerseTexts(String id, String? fallbackModuleId) {
    final s = byId(id);
    if (s == null) return;
    String norm(String x) => x.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final b in blocksOf(s)) {
      final to = b['to'] as int?;
      if (!isVerse(b) || to == null || to <= (b['verse'] as int) || b['part'] == true || verseTexts(b) != null || !_tried.add('${b['id']}')) continue;
      for (final mid in {b['moduleId'], fallbackModuleId}.whereType<String>()) {
        final texts = <String>[];
        for (var v = b['verse'] as int; v <= to; v++) {
          final vt = verseText(mid, VerseRef(b['book'] as String, b['chapter'] as int, v));
          if (vt == null) break;
          texts.add(vt);
        }
        if (texts.length == to - (b['verse'] as int) + 1 && norm(texts.join(' ')) == norm('${b['text']}')) {
          _touch(id, (s) => {...s, 'blocks': [for (final y in blocksOf(s)) y['id'] == b['id'] && y['text'] == b['text'] ? {...y, 'texts': texts} : y]}, stamp: false);
          break;
        }
      }
    }
  }
}

final sermonsProvider = NotifierProvider<SermonsNotifier, List<Sermon>>(SermonsNotifier.new);

/// Проповедь, в которой есть этот стих (самая недавно изменённая)
Sermon? sermonWith(List<Sermon> sermons, VerseRef ref) {
  final sorted = [...sermons]..sort((a, b) => ((b['updatedAt'] ?? 0) as num).compareTo((a['updatedAt'] ?? 0) as num));
  for (final s in sorted) {
    for (final b in blocksOf(s)) {
      if (isVerse(b) && b['book'] == ref.book && b['chapter'] == ref.chapter && ref.verse >= (b['verse'] as int) && ref.verse <= ((b['to'] ?? b['verse']) as int)) return s;
    }
  }
  return null;
}

// --- Ссылка из строки поиска → стихи для проповеди --------------------------------------------------

/// «Ин 3» — вся глава; «Ин 3:16-18» — стихи
bool isWholeChapter(String q) => !RegExp(r'\d\s*[:.,]\s*\d|\d\s+\d').hasMatch(q.replaceFirst(RegExp(r'^\s*\d\s*'), ''));

final _refRe = RegExp(r'^((?:[1-4]\s*)?[^\d\s:.,][^\d:,]*?)\.?\s*(\d+)(?:(?:\s*[:.,]\s*|\s+)(\d+)(?:\s*[-–]\s*(\d+))?)?\s*$');

/// «Ин 3:16-18» → (книга, глава, стих, конец) или null
({String book, int chapter, int verse, int? end})? parseRange(String input) {
  final m = _refRe.firstMatch(input.trim());
  if (m == null) return null;
  final book = Books.instance.findBookId(m.group(1)!);
  if (book == null) return null;
  return (book: book, chapter: int.parse(m.group(2)!), verse: m.group(3) != null ? int.parse(m.group(3)!) : 1, end: m.group(4) != null ? int.parse(m.group(4)!) : null);
}

String refRangeLabel(String q, ({String book, int chapter, int verse, int? end}) r) {
  final name = Books.instance.meta(r.book).name;
  if (isWholeChapter(q)) return '$name ${r.chapter}';
  return '$name ${r.chapter}:${r.verse}${r.end != null && r.end! > r.verse ? '–${r.end}' : ''}';
}

/// Стихи по ссылке из выбранного перевода; null — ссылка не разобрана
List<VerseItem>? versesForRef(String moduleId, String q) {
  final r = parseRange(q);
  if (r == null) return null;
  final endV = r.end ?? (isWholeChapter(q) ? 999 : r.verse);
  final items = <VerseItem>[];
  try {
    final rows = ModuleStore.instance.db(moduleId).select('SELECT verse, text FROM verses WHERE book = ? AND chapter = ? AND verse BETWEEN ? AND ? ORDER BY verse LIMIT 400', [r.book, r.chapter, r.verse, endV]);
    for (final row in rows) {
      items.add(VerseItem(r.book, r.chapter, row['verse'] as int, plainText(row['text'] as String)));
    }
  } catch (_) {}
  return items;
}

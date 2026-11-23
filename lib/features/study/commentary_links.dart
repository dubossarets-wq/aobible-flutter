// Ссылки в тексте толкования: места Писания («Иез XVI:8», «Лев XXV:25-26; 3 Цар XVI:11», «ст. 13», «IV:3-5»),
// номера Стронга и слова на греческом и иврите (а также «евр. goel»). Нажатие открывает окно поверх толкования —
// «назад» возвращает к тексту. Порт CommentaryLinks.swift (iPhone).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart' show panesProvider;
import '../../ui/kit.dart';
import '../hub.dart';
import 'commentary_sheet.dart' show CommentarySheet;
import 'dictionary_sheet.dart';
import 'greek_nfd.dart';
import 'sheet.dart';
import 'study_data.dart';

const _verseList = r'\d+(?:\s*[-–]\s*\d+)?(?:\s*,\s*\d+(?:\s*[-–]\s*\d+)?)*';
const _chap = r'(?:\d+|[IVXLC]+)';

/// Книга (с номером впереди и, возможно, вторым словом: «Иис. Нав.»), глава (цифрами или римскими), стихи
final _bookRe = RegExp('((?:[1-4]\\s?)?[А-ЯЁ][а-яё]+\\.?)(\\s[А-ЯЁ][а-яё]+\\.?)?\\s*($_chap)\\s*[:.]\\s*($_verseList)');
/// Без книги — глава и стихи той же книги («IV:3-5»)
final _chapOnlyRe = RegExp('(?<![\\p{L}\\d])([IVXLC]+)\\s*:\\s*($_verseList)', unicode: true);
/// «ст. 13», «стт. 3-5»
final _verseOnlyRe = RegExp('(?<!\\p{L})стт?\\.\\s*($_verseList)', unicode: true);
final _partRe = RegExp(r'(\d+)(?:\s*[-–]\s*(\d+))?');
final _strongRe = RegExp(r'(?<![A-Za-z])[HG]\d+');
final _originalRe = RegExp('[Ͱ-Ͽἀ-῿]{2,}|[֐-׿]{2,}');
/// Слово латиницей после «евр.» / «греч.» — транслитерация слова оригинала
final _translitRe = RegExp("(?:евр|греч|арам)\\.\\s*([A-Za-z][A-Za-z'’ʼ]{1,})");

/// «XVI» → 16; не римское число — null
int? romanToInt(String s) {
  if (s.isEmpty || !RegExp(r'^[IVXLC]+$').hasMatch(s)) return null;
  const val = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100};
  var total = 0, prev = 0;
  for (final ch in s.split('').reversed) {
    final v = val[ch]!;
    total += v < prev ? -v : v;
    if (v > prev) prev = v;
  }
  return total > 0 && total <= 150 ? total : null;
}

int? _num(String s) => int.tryParse(s) ?? romanToInt(s);

/// Текст толкования → куски; у кусков-ссылок есть действие
List<(String, VoidCallback?)> commentaryParts(
  String s, {
  required String book,
  required int chapter,
  required void Function(VerseRef at, int? end) onVerse,
  required void Function(String strong) onStrong,
  required void Function(String word) onWord,
}) {
  final spans = <({int a, int b, VoidCallback f})>[];
  bool free(int a, int b) => !spans.any((x) => x.a < b && a < x.b);
  void put(int a, int b, VoidCallback f) {
    if (free(a, b)) spans.add((a: a, b: b, f: f));
  }

  /// Стихи «25-26», «6, 9» — у каждой части своя ссылка
  void putVerses(int listStart, String list, String bk, int ch) {
    for (final m in _partRe.allMatches(list)) {
      final v = int.parse(m.group(1)!);
      final e = m.group(2) == null ? null : int.parse(m.group(2)!);
      put(listStart + m.start, listStart + m.end, () => onVerse(VerseRef(bk, ch, v), e));
    }
  }

  // 1. С названием книги
  for (final m in _bookRe.allMatches(s)) {
    final first = m.group(1)!;
    final second = m.group(2);
    // «Иис. Нав.» целиком; нет — второе слово («Ср. Иез» → Иез); нет — первое
    final b = (second == null ? null : Books.instance.findBookId(first + second)) ??
        (second == null ? null : Books.instance.findBookId(second)) ??
        Books.instance.findBookId(first);
    final c = _num(m.group(3)!);
    if (b == null || c == null || c < 1) continue;
    final list = m.group(4)!;
    putVerses(m.end - list.length, list, b, c);
  }
  // 2. Глава римскими без книги — книга толкования
  for (final m in _chapOnlyRe.allMatches(s)) {
    final c = romanToInt(m.group(1)!);
    if (c == null || !free(m.start, m.end)) continue;
    final list = m.group(2)!;
    putVerses(m.end - list.length, list, book, c);
  }
  // 3. «ст. 13» — стих этой же главы
  for (final m in _verseOnlyRe.allMatches(s)) {
    final list = m.group(1)!;
    putVerses(m.end - list.length, list, book, chapter);
  }
  // 4. Номера Стронга
  for (final m in _strongRe.allMatches(s)) {
    final n = m.group(0)!;
    put(m.start, m.end, () => onStrong(n));
  }
  // 5. Слова на греческом и иврите
  for (final m in _originalRe.allMatches(s)) {
    final w = m.group(0)!;
    put(m.start, m.end, () => onWord(w));
  }
  for (final m in _translitRe.allMatches(s)) {
    final w = m.group(1)!;
    put(m.end - w.length, m.end, () => onWord(w));
  }

  spans.sort((x, y) => x.a.compareTo(y.a));
  final out = <(String, VoidCallback?)>[];
  var at = 0;
  for (final sp in spans) {
    if (sp.a > at) out.add((s.substring(at, sp.a), null));
    out.add((s.substring(sp.a, sp.b), sp.f));
    at = sp.b;
  }
  if (at < s.length) out.add((s.substring(at), null));
  return out;
}

/// Поиск статей Стронга по слову оригинала: греческому, ивриту или транслитерации. Без диакритики, придыханий и
/// огласовок (в толкованиях они обычно потеряны)
class OriginalWords {
  static final _lemma = <String, Map<String, List<String>>>{};
  static final _xlit = <String, Map<String, List<String>>>{};

  static const _finals = {'ς': 'σ', 'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'};
  static const _latin = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ā': 'a', 'ă': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'ō': 'o', 'ú': 'u', 'ù': 'u',
    'û': 'u', 'ü': 'u', 'ū': 'u', 'ṭ': 't', 'ḥ': 'h', 'ṣ': 's', 'š': 's', 'ś': 's', 'ḵ': 'k', 'ḳ': 'k', 'ẓ': 'z',
  };

  /// Нижний регистр, без диакритики и знаков, конечные формы букв — в обычные
  static String fold(String s) {
    final b = StringBuffer();
    for (final rune in s.toLowerCase().runes) {
      var ch = String.fromCharCode(rune);
      // греческие буквы со знаками → основа + знаки (своей нормализации в Dart нет)
      ch = greekNfd[ch] ?? ch;
      for (final r in ch.runes) {
        final c = String.fromCharCode(r);
        if (r >= 0x0300 && r <= 0x036F) continue; // знаки Unicode
        if (r >= 0x0591 && r <= 0x05C7) continue; // огласовки и знаки иврита
        final low = _latin[c] ?? c;
        final isLetter = (r >= 0x61 && r <= 0x7A) || (r >= 0x0370 && r <= 0x03FF) || (r >= 0x1F00 && r <= 0x1FFF) || (r >= 0x05D0 && r <= 0x05EA) || (r >= 0x0400 && r <= 0x04FF);
        if (!isLetter && low == c) continue;
        b.write(_finals[low] ?? low);
      }
    }
    return b.toString();
  }

  static Map<String, List<String>> _index(InstalledModule m, {required bool translit}) {
    final cache = translit ? _xlit : _lemma;
    final hit = cache[m.id];
    if (hit != null) return hit;
    final map = <String, List<String>>{};
    try {
      final rows = ModuleStore.instance.db(m.id).select(
          translit ? "SELECT key, ifnull(json_extract(json, '\$.xlit'), '') AS w FROM dict" : 'SELECT key, word AS w FROM dict');
      for (final r in rows) {
        final f = fold('${r['w'] ?? ''}');
        if (f.isNotEmpty) (map[f] ??= []).add(r['key'] as String);
      }
    } catch (_) {
      // словарь без таблицы или без JSON-функций — слов в индексе нет
    }
    return cache[m.id] = map;
  }

  /// Номера Стронга для слова: точное совпадение; нет — слова с тем же началом (формы слова)
  static List<({InstalledModule module, String key})> keys(String word) {
    final f = fold(word);
    if (f.length < 2) return const [];
    final latin = RegExp(r'^[a-z]+$').hasMatch(f);
    final mods = StudyData.dictionaries(strongsOnly: true);
    final out = <({InstalledModule module, String key})>[];
    final seen = <String>{};
    void add(InstalledModule m, List<String>? ks) {
      for (final k in ks ?? const <String>[]) {
        if (seen.add(k)) out.add((module: m, key: k));
      }
    }

    for (final m in mods) {
      add(m, _index(m, translit: latin)[f]);
    }
    if (out.isEmpty && f.length >= 5) {
      final stem = f.substring(0, f.length - 2);
      for (final m in mods) {
        final idx = _index(m, translit: latin);
        final near = idx.keys.where((k) => k.startsWith(stem) && (k.length - f.length).abs() <= 2).toList()..sort();
        for (final k in near.take(4)) {
          add(m, idx[k]);
        }
      }
    }
    return out.take(6).toList();
  }
}

/// Текст толкования со ссылками. [pane] и [at] — откуда открыли окно (для окон Стронга и стиха)
class CommentaryText extends ConsumerWidget {
  const CommentaryText({super.key, required this.text, required this.pane, required this.at, required this.book, required this.chapter, this.style});
  final String text;
  final int pane;
  final VerseRef at;
  final String book;
  final int chapter;
  final TextStyle? style;

  void _word(BuildContext context, WidgetRef ref, String w) {
    final keys = OriginalWords.keys(w).map((e) => e.key).toList();
    openDictionary(
      context,
      DictRequest(text: w, strongs: keys, morph: const [], ref: at, pane: pane, autoOpen: keys.isNotEmpty),
      full: keys.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => LinkSpans(
        parts: commentaryParts(
          text,
          book: book,
          chapter: chapter,
          onVerse: (r, end) => showSheet(context, CommentaryVerseSheet(pane: pane, at: r, end: end)),
          onStrong: (n) => Hub.openStrong?.call(context, ref, pane, at, n),
          onWord: (w) => _word(context, ref, w),
        ),
        style: style,
      );
}

/// Место Писания из толкования: текст стиха (или нескольких) перевода панели, «Читать» и «Толкования».
/// «Назад» — к толкованию
class CommentaryVerseSheet extends ConsumerStatefulWidget {
  const CommentaryVerseSheet({super.key, required this.pane, required this.at, this.end});
  final int pane;
  final VerseRef at;
  final int? end;
  @override
  ConsumerState<CommentaryVerseSheet> createState() => _CommentaryVerseSheetState();
}

class _CommentaryVerseSheetState extends ConsumerState<CommentaryVerseSheet> {
  String get _moduleId {
    final panes = ref.read(panesProvider);
    return panes[widget.pane.clamp(0, panes.length - 1)].moduleId;
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.at;
    final m = ModuleStore.instance.get(_moduleId);
    final last = widget.end == null ? at.verse : (widget.end! > at.verse + 40 ? at.verse + 40 : widget.end!);
    final texts = <(int, String)>[];
    for (var v = at.verse; v <= last; v++) {
      final raw = StudyData.verseRaw(_moduleId, at.book, at.chapter, v);
      if (raw != null) texts.add((v, raw.replaceAllMapped(RegExp(r'\{([^|}]*)\|[^}]*\}'), (x) => x.group(1)!).replaceAll('‹', '').replaceAll('›', '')));
    }
    final title = widget.end != null && widget.end! > at.verse ? '${fmtRef(at)}–${widget.end}' : fmtRef(at);
    final hasComment = StudyData.commentaryFor(at).isNotEmpty;
    return SheetScaffold(
      title: title,
      subtitle: m?.name,
      onBack: () => Navigator.pop(context),
      body: SheetList(children: [
        if (texts.isEmpty)
          Empty(icon: LucideIcons.bookOpen, title: t('Такого стиха в этом переводе нет'))
        else
          QuoteBox(texts.length == 1 ? texts.first.$2 : texts.map((x) => '${x.$1} ${x.$2}').join('\n')),
        BigButton(t('Читать'), icon: LucideIcons.bookOpen, onTap: () => openRefInOther(context, ref, widget.pane, at)),
        if (hasComment)
          BigButton(t('Толкования'), icon: LucideIcons.messageSquareText, onTap: () {
            showSheet(context, CommentarySheet(pane: widget.pane, at: at));
          }),
      ]),
    );
  }
}

// Подстрочник: порт src/core/interlinear.js веб-версии. Все слова синодального текста (RST+), под каждым — слово
// оригинала (Ветхий Завет — еврейский OSHB, Новый — греческий Робинсона — Пирпонта), сопоставленное по номерам
// Стронга; а также подстрочник Винокурова, Вульгата и Септуагинта. Оригинальные тексты ставятся сами при первом
// открытии подстрочника.
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import 'study_data.dart';

/// Слово разобранного стиха: kind w (слово) или t (текст между словами)
class Tok {
  Tok(this.isWord, this.text, {this.strongs = const [], this.morph = const [], this.orig, this.italic = false});
  final bool isWord;
  final String text;
  final List<String> strongs;
  final List<String> morph;
  final String? orig;
  final bool italic;
}

final _wordRe = RegExp(r"[\p{L}\p{M}]+(?:[-’'][\p{L}\p{M}]+)*", unicode: true);
final _ws = RegExp(r'\s+');

/// Разбор стиха на слова и промежутки (порт tokenize из verseMarkup.js):
/// {слово|номера Стронга|морфология|слово оригинала (в подстрочнике)}, ‹добавленное›
List<Tok> tokenize(String text) {
  final out = <Tok>[];
  var italic = false;
  void plain(String s) {
    var last = 0;
    for (final m in _wordRe.allMatches(s)) {
      if (m.start > last) out.add(Tok(false, s.substring(last, m.start), italic: italic));
      out.add(Tok(true, m.group(0)!, italic: italic));
      last = m.end;
    }
    if (last < s.length) out.add(Tok(false, s.substring(last), italic: italic));
  }

  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (ch == '‹') {
      italic = true;
      i++;
    } else if (ch == '›') {
      italic = false;
      i++;
    } else if (ch == '{') {
      final end = text.indexOf('}', i);
      if (end < 0) {
        plain(text.substring(i));
        break;
      }
      final p = text.substring(i + 1, end).split('|');
      final strongs = (p.length > 1 ? p[1] : '').split(_ws).where((s) => s.isNotEmpty).toList();
      final morph = (p.length > 2 ? p[2] : '').split(_ws).where((s) => s.isNotEmpty).toList();
      final o = p.length > 3 ? p[3] : '';
      if (strongs.isNotEmpty) {
        out.add(Tok(true, p[0], strongs: strongs, morph: morph, orig: o.isEmpty ? null : o, italic: italic));
      } else {
        plain(p[0]);
      }
      i = end + 1;
    } else {
      var j = i;
      while (j < text.length && !'‹›{'.contains(text[j])) {
        j++;
      }
      plain(text.substring(i, j));
      i = j;
    }
  }
  return out;
}

String plainOf(String raw) => raw.replaceAllMapped(RegExp(r'\{([^|}]*)\|[^}]*\}'), (m) => m.group(1)!).replaceAll('‹', '').replaceAll('›', '');

String? strongNum(String? s) {
  final m = RegExp(r'^([HG])0*(\d+)([a-z]?)$', caseSensitive: false).firstMatch(s ?? '');
  return m == null ? s : '${m.group(1)!.toUpperCase()}${m.group(2)}';
}

String? originalFor(String book) => switch (Books.instance.meta(book).testament) { 'OT' => 'oshb', 'NT' => 'byz-rp2018', _ => null };

// В греческом тексте у всех форм глагола один номер, а в RST+ у отдельных форм свои (ἦν «было» — G2258 и т.п.)
const _same = [
  ['G1510', 'G2258', 'G2071', 'G2070', 'G2075', 'G2076', 'G2468', 'G5600', 'G1488', 'G1526', 'G2277'], // быть
  ['G3004', 'G2036', 'G2046', 'G4483'], // говорить, сказать
  ['G3708', 'G1492', 'G3700'], // видеть
  ['G2068', 'G5315'], // есть
  ['G5143', 'G1408'], // бежать
];
final _aliases = {for (final g in _same) for (final n in g) n: g};

// Служебные слова без отдельного перевода: греческий артикль и еврейская частица прямого дополнения
const _silent = {'G3588', 'H853'};

final _cantillation = RegExp('[֑-ֽ֯׀]');

class OWord {
  OWord(this.text, this.num, this.strongs, this.morph);
  final String text;
  final String? num;
  final List<String>? strongs;
  final String? morph;
  final List<String> gloss = [];
}

/// Слово русского стиха с его оригиналом
class RuWord {
  RuWord({required this.text, this.after = '', this.orig = '', this.origMorph, this.num, this.strongs, this.morph, this.italic = false});
  final String text;
  String after;
  final String orig;
  final String? origMorph;
  final String? num;
  final List<String>? strongs;
  final String? morph;
  final bool italic;
}

/// Слово подстрочника: оригинал, перевод/значение под ним и номер Стронга
class IlWord {
  IlWord({required this.text, this.gloss = '', this.num, this.strongs, this.morph, this.guess = false, this.lemma = ''});
  final String text;
  final String gloss;
  final String? num;
  final List<String>? strongs;
  final String? morph;
  final bool guess; // значение по словарю, а не перевод стиха — показывается бледнее
  final String lemma;
}

InstalledModule? _taggedRu() {
  final bibles = ModuleStore.instance.bibles;
  return bibles.where((m) => m.id == 'rst-plus').firstOrNull ??
      bibles.where((m) => m.features['strongs'] == true && m.language == 'ru' && m.features['interlinear'] != true).firstOrNull;
}

/// Модуль с размеченным русским текстом, по которому строится сопоставление
String? interlinearRuModule() => _taggedRu()?.id;

// Сопоставление слов стиха по номерам Стронга — одно на оба порядка: ru — все слова синодального текста с их
// оригиналом, orig — все слова оригинала с русским переводом.
({List<RuWord> ru, List<OWord> orig})? alignVerse(VerseRef ref) {
  final id = originalFor(ref.book);
  if (id == null || !StudyData.isInstalled(id)) return null;
  final tagged = _taggedRu();
  final orig = StudyData.verse(id, ref);
  final ru = tagged == null ? null : StudyData.verse(tagged.id, ref);
  final origWords = <OWord>[];
  final queues = <String, List<OWord>>{};
  for (final t in tokenize(orig ?? '')) {
    if (!t.isWord) continue;
    final k = t.strongs.isNotEmpty ? strongNum(t.strongs.first) : null;
    final w = OWord(t.text.replaceAll(_cantillation, ''), k, t.strongs.isEmpty ? null : t.strongs, t.morph.isEmpty ? null : t.morph.first);
    origWords.add(w);
    if (k != null) (queues[k] ??= []).add(w);
  }
  if (ru == null) return (ru: <RuWord>[], orig: origWords);
  final last = <String, OWord>{};
  OWord? take(String k) {
    for (final n in _aliases[k] ?? [k]) {
      final q = queues[n];
      if (q != null && q.isNotEmpty) {
        final w = q.removeAt(0);
        last[k] = w;
        return w;
      }
    }
    return null;
  }

  final out = <RuWord>[];
  String? prevKey;
  OWord? prevOrig; // оригинал предыдущего русского слова — для «будет говорить» (два слова на одно)
  var gap = false; // между словами был знак препинания
  var before = ''; // открывающие кавычки и скобки — к следующему слову
  final openRe = RegExp(r'^(.*?)([«(„“‘\[]*)$', dotAll: true);
  for (final t in tokenize(ru)) {
    if (!t.isWord) {
      final txt = t.text.trim();
      if (txt.isNotEmpty) {
        gap = true;
        final m = openRe.firstMatch(txt)!;
        final close = m.group(1)!, open = m.group(2)!;
        if (close.isNotEmpty && out.isNotEmpty) {
          out.last.after += close;
        } else if (close.isNotEmpty) {
          before += close;
        }
        before += open;
      }
      continue;
    }
    final k = t.strongs.isNotEmpty ? strongNum(t.strongs.first) : null;
    OWord? o;
    if (k != null && k == prevKey && !gap) {
      prevOrig?.gloss.add(t.text);
    } else if (k != null) {
      final fresh = take(k);
      fresh?.gloss.add(t.text);
      o = fresh ?? last[k];
      prevOrig = fresh;
    }
    for (final extra in t.strongs.skip(1)) {
      take(strongNum(extra)!);
    }
    out.add(RuWord(
      text: before + t.text,
      orig: o?.text ?? '',
      origMorph: o?.morph,
      num: o != null ? k : null,
      strongs: t.strongs.isEmpty ? null : t.strongs,
      morph: t.morph.isEmpty ? null : t.morph.first,
      italic: t.italic,
    ));
    prevKey = k;
    gap = false;
    before = '';
  }
  return (ru: out, orig: origWords);
}

/// Подстрочник в порядке синодального текста: все русские слова, под каждым — оригинал (если есть)
List<RuWord>? ruInterlinear(VerseRef ref) => alignVerse(ref)?.ru;

/// Подстрочник в порядке оригинала (Ветхий Завет — справа налево): под каждым словом — как оно передано
/// в синодальном стихе; если в стихе его нет — обычный перевод из «Симфонии RST+» (guess — показывается бледнее)
List<IlWord>? origInterlinear(VerseRef ref) {
  final a = alignVerse(ref);
  if (a == null) return null;
  final needSym = a.orig.any((w) => w.gloss.isEmpty) && StudyData.isInstalled('rst-symphony');
  return [
    for (final w in a.orig)
      () {
        var gloss = w.gloss.join(' ');
        var guess = false;
        if (gloss.isEmpty && w.num != null && !_silent.contains(w.num) && !_aliases.containsKey(w.num) && needSym) {
          final r = StudyData.dictGet('rst-symphony', w.num!)?['renderings'];
          if (r is List && r.isNotEmpty) gloss = ((r.first as List).first).toString();
          guess = gloss.isNotEmpty;
        }
        return IlWord(text: w.text, gloss: gloss, num: w.num, strongs: w.strongs, morph: w.morph, guess: guess);
      }(),
  ];
}

typedef Progress = void Function(double p, String label);

/// Ставит модуль из каталога, если его ещё нет; false — модуля нет и в каталоге
Future<bool> ensureModule(String id, [Progress? onProgress]) async {
  if (StudyData.isInstalled(id)) return true;
  final entry = (await ModuleStore.instance.catalog()).where((c) => c.id == id).firstOrNull;
  if (entry == null) return false;
  await ModuleStore.instance.install(entry, onProgress: onProgress);
  return true;
}

/// Ставит оригинальный текст, если его ещё нет
Future<String?> ensureOriginal(String book, [Progress? onProgress]) async {
  final id = originalFor(book);
  if (id == null) return null;
  if (!await ensureModule(id, onProgress)) throw Exception(t('Оригинальный текст пока недоступен.'));
  return id;
}

/// Подстрочник А. Винокурова (Новый Завет, с разрешения автора): слова в порядке византийского текста
/// (Робинсон — Пирпонт), под каждым — русское слово Винокурова. Модуль ставится сам при первом открытии вкладки.
const vinModule = 'vin-interlinear';

Future<List<IlWord>?> vinInterlinear(VerseRef ref, [Progress? onProgress]) async {
  if (!isNt(ref.book)) return null;
  if (!await ensureModule(vinModule, onProgress)) return null;
  final raw = StudyData.verse(vinModule, ref);
  if (raw == null) return [];
  return [
    for (final tk in tokenize(raw))
      if (tk.isWord) IlWord(text: tk.orig ?? '', gloss: tk.text == '·' ? '' : tk.text, num: tk.strongs.isNotEmpty ? strongNum(tk.strongs.first) : null, strongs: tk.strongs.isEmpty ? null : tk.strongs),
  ];
}

/// Подстрочник по латинской Вульгате (Климентина): слова в порядке Вульгаты, у каждого — начальная форма
/// и краткое значение по словарю. Слово в модуле: «форма|лемма|значение»; пробелы в значении записаны «_».
const vulgModule = 'vulg-interlinear';

Future<List<IlWord>> vulgInterlinear(VerseRef ref, [Progress? onProgress]) async {
  if (!await ensureModule(vulgModule, onProgress)) throw Exception(t('Подстрочник к Вульгате пока недоступен.'));
  final raw = StudyData.verse(vulgModule, ref);
  if (raw == null) return [];
  return [
    for (final cell in raw.split(' ').where((c) => c.isNotEmpty))
      () {
        final p = cell.split('|');
        return IlWord(text: p[0], lemma: p.length > 1 ? p[1] : '', gloss: (p.length > 2 ? p[2] : '').replaceAll('_', ' '), guess: true);
      }(),
  ];
}

/// Подстрочник Ветхого Завета по Септуагинте (издание Свита): греческие слова в порядке LXX, под каждым — значение
/// по номеру Стронга. Значение подбирается по словам синодального стиха: из вариантов перевода этого слова
/// в синодальном Новом Завете («Симфония RST+») берётся тот, что есть в стихе (сначала точное совпадение, затем —
/// то же слово в другой форме); если в стихе такого нет — самый частый вариант или начало статьи русского словаря
/// Стронга. Это значение по словарю, а не перевод Септуагинты, поэтому оно всегда бледное (guess).
const lxxModule = 'lxx-swete';
const _synodal = ['rst-plus', 'rst', 'rst-dc'];

String _ru(String s) => s.toLowerCase().replaceAll('ё', 'е');

bool _near(String a, String b) {
  if (a == b) return true;
  final n = a.length < b.length ? a.length : b.length;
  if (n < 3) return false;
  var p = 0;
  while (p < n && a[p] == b[p]) {
    p++;
  }
  return p >= 3 && p >= n - 2;
}

Future<List<IlWord>?> lxxInterlinear(VerseRef ref, [Progress? onProgress]) async {
  if (isNt(ref.book)) return null;
  if (!await ensureModule(lxxModule, onProgress)) throw Exception(t('Оригинальный текст пока недоступен.'));
  final raw = StudyData.verse(lxxModule, ref);
  if (raw == null) return [];
  final words = [
    for (final tk in tokenize(raw))
      if (tk.isWord) (text: tk.text, num: tk.strongs.isNotEmpty ? strongNum(tk.strongs.first) : null, strongs: tk.strongs.isEmpty ? null : tk.strongs),
  ];
  final glosses = List<String>.filled(words.length, '');
  if (words.any((w) => w.num != null)) {
    // Слова синодального стиха — из первого установленного синодального текста, где этот стих есть
    var synText = '';
    for (final id in _synodal) {
      final v = StudyData.isInstalled(id) ? StudyData.verse(id, ref) : null;
      if (v != null && v.isNotEmpty) {
        synText = v;
        break;
      }
    }
    final syn = [
      for (final tk in tokenize(plainOf(synText)))
        if (tk.isWord) (text: tk.text, key: _ru(tk.text), used: [false]), // по одному слову (в RST+ метка бывает на фразе)
    ];
    final hasSym = StudyData.isInstalled('rst-symphony');
    final hasDict = StudyData.isInstalled('strongs-ru-greek');
    final optCache = <String, List<String>>{};
    List<String> options(String sn) => optCache[sn] ??= () {
          final all = <List<dynamic>>[];
          if (hasSym) {
            for (final n in _aliases[sn] ?? [sn]) {
              final r = StudyData.dictGet('rst-symphony', n)?['renderings'];
              if (r is List) all.addAll(r.cast<List>());
            }
          }
          final order = {for (final (i, x) in all.indexed) x: i};
          all.sort((a, b) => (b[1] as num) != (a[1] as num) ? (b[1] as num).compareTo(a[1] as num) : order[a]!.compareTo(order[b]!));
          return [
            for (final x in all)
              if (_ru((x[0] as String).replaceAll(RegExp(r'[^\p{L}\s-]', unicode: true), '').trim()).isNotEmpty) _ru((x[0] as String).replaceAll(RegExp(r'[^\p{L}\s-]', unicode: true), '').trim()),
          ];
        }();
    void pick(int wi, bool Function(String, String) same) {
      for (final o in options(words[wi].num!)) {
        final s = syn.where((x) => !x.used[0] && same(o, x.key)).firstOrNull;
        if (s != null) {
          s.used[0] = true;
          glosses[wi] = s.text;
          return;
        }
      }
    }

    final todo = [for (var i = 0; i < words.length; i++) if (words[i].num != null && !_silent.contains(words[i].num)) i];
    for (final i in todo) {
      pick(i, (a, b) => a == b);
    }
    for (final i in todo) {
      if (glosses[i].isEmpty) pick(i, _near);
    }
    for (final i in todo) {
      if (glosses[i].isNotEmpty) continue;
      final first = options(words[i].num!).firstOrNull;
      final def = hasDict ? (StudyData.dictGet('strongs-ru-greek', words[i].num!)?['definition'] ?? '').toString() : '';
      glosses[i] = first ?? def.split(RegExp(r'[,;(]')).first.trim();
    }
  }
  return [for (var i = 0; i < words.length; i++) IlWord(text: words[i].text, gloss: glosses[i], num: words[i].num, strongs: words[i].strongs, guess: true)];
}

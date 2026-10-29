// Поиск словарных статей для слова, на которое нажал читатель (порт src/core/lexicon.js веб-версии).
//
// 1. Если перевод размечен номерами Стронга, берём именно их (точная привязка).
// 2. Иначе сопоставляем русскую словоформу с номерами Стронга по обратному индексу симфонии (wordIndex) —
//    приблизительно, интерфейс об этом предупреждает.
// 3. Словари «по словам» ищутся по самой словоформе, затем по начальной форме (благодати → благодать,
//    агнца → агнец), затем без приставки (возлюбил → любить), и лишь потом — ближайшие слова с той же основой.
import '../../core/modules.dart';
import 'study_data.dart';

const _endings = [
  'ениями', 'ениях', 'остями', 'ствами', 'иями', 'ями', 'ами', 'ого', 'его', 'ому', 'ему', 'ыми', 'ими', 'ешь', 'ете',
  'ите', 'ают', 'яют', 'ует', 'ует', 'ться', 'тся', 'ась', 'ось', 'ись', 'ыся', 'вши', 'ший', 'щий', 'ние', 'ния',
  'нию', 'ием', 'иях', 'ой', 'ей', 'ий', 'ый', 'ая', 'яя', 'ое', 'ее', 'ую', 'юю', 'ом', 'ем', 'ах', 'ях', 'ов',
  'ев', 'ам', 'ям', 'ть', 'ти', 'ет', 'ит', 'ут', 'ют', 'ат', 'ят', 'ил', 'ел', 'ла', 'ли', 'ло', 'ся', 'сь',
  'ы', 'и', 'а', 'я', 'о', 'е', 'у', 'ю', 'ь', 'й',
];

String normalizeWord(String w) => w.toLowerCase().replaceAll('ё', 'е');

String stem(String word) {
  final w = normalizeWord(word);
  for (final e in _endings) {
    if (w.length - e.length >= 3 && w.endsWith(e)) return w.substring(0, w.length - e.length);
  }
  return w;
}

final _marks = RegExp('[̀́҃-҉]');

/// Ключ для словаря: без ударений и титл, дореформенные буквы — в современные (для ЦСЯ, Макария).
/// Нормализации Unicode в Dart нет; для кириллицы она и не нужна — знаки убираем напрямую.
String dictKey(String word) => normalizeWord(word)
    .replaceAll(_marks, '')
    .replaceAll('ѣ', 'е')
    .replaceAll(RegExp('[іѵ]'), 'и')
    .replaceAll('ѳ', 'ф')
    .replaceAll(RegExp('ъ\$'), '');

const _lemmaEndings = ['', 'ь', 'а', 'я', 'о', 'е', 'й', 'ий', 'ый', 'ой', 'ть', 'ти', 'ться', 'ие', 'ия'];
const _verbEndings = ['ить', 'еть', 'ать', 'ять', 'ть', 'ти', 'ться', 'иться'];
// Похоже на глагол («любил», «говорит», «сказали») — начальную форму ищем сначала среди глагольных
final _verbal = RegExp(r'(ил|ел|ал|ял|ла|ли|ло|ет|ит|ут|ют|ат|ят|ешь|ишь|ете|ите|ем|им|вши|ться|тся|лся|лась|лись)$');
final _vowels = RegExp('[аеёиоуыэюяй]');

List<String> _lemmaGuesses(String st, bool verbal) {
  final out = <String>[
    for (final e in verbal ? [..._verbEndings, ..._lemmaEndings] : [..._lemmaEndings, ..._verbEndings]) st + e,
  ];
  if (st.length >= 3) {
    final last = st.substring(st.length - 1);
    final prev = st.substring(st.length - 2, st.length - 1);
    // беглая гласная: «агнц» → агнец
    if (!_vowels.hasMatch(last) && prev.isNotEmpty && !_vowels.hasMatch(prev)) {
      for (final v in ['е', 'о']) {
        for (final e in ['', 'ь']) {
          out.add(st.substring(0, st.length - 1) + v + last + e);
        }
      }
    }
  }
  return out;
}

const _prefixes = ['пред', 'пере', 'воз', 'вос', 'раз', 'рас', 'при', 'про', 'под', 'пре', 'вы', 'из', 'ис', 'на', 'за', 'от', 'об', 'до', 'со', 'по', 'у', 'с', 'о'];

/// Найденная статья: ключ, статья и как найдена (exact/approx/none — по номеру; form/lemma/root/stem — по слову)
class Found {
  Found(this.key, this.entry, this.match);
  final String key;
  final Map<String, dynamic> entry;
  final String match;
  String get label => (entry['lemma'] ?? entry['word'] ?? '').toString();
}

class ModResult {
  ModResult(this.module, this.found);
  final InstalledModule module;
  final List<Found> found;
}

class Mapping {
  Mapping(this.mode, this.strongs, {this.morph = const [], this.weights = const {}});
  final String mode; // exact | approx | none
  final List<String> strongs;
  final List<String> morph;
  final Map<String, double> weights;
}

class LookupResult {
  LookupResult(this.word, this.mapping, this.results, this.dictionaryCount);
  final String word;
  final Mapping mapping;
  final List<ModResult> results;
  final int dictionaryCount;
}

String strongKey(String s) {
  final m = RegExp(r'^([HG])0*(\d+)([a-z]?)$', caseSensitive: false).firstMatch(s);
  return m == null ? s : '${m.group(1)!.toUpperCase()}${m.group(2)}${m.group(3) ?? ''}';
}

List<Found> _findWord(String moduleId, String text) {
  final key = dictKey(text);
  final exact = StudyData.dictGetMany(moduleId, [key, text.toLowerCase()]);
  if (exact.isNotEmpty) return [Found(exact.first.$1, exact.first.$2, 'form')];

  List<String> byLemma(String w) {
    final st = stem(w);
    final guesses = _lemmaGuesses(st, _verbal.hasMatch(w)).toSet().where((k) => k != w).toList();
    return [for (final (k, _) in StudyData.dictGetMany(moduleId, guesses)) k];
  }

  List<Found> make(List<String> keys, int n, String match) {
    final got = {for (final (k, e) in StudyData.dictGetMany(moduleId, keys.take(n).toList())) k: e};
    return [for (final k in keys.take(n)) if (got[k] != null) Found(k, got[k]!, match)];
  }

  // Начальная форма слова
  var hits = byLemma(key);
  if (hits.isNotEmpty) return make(hits, 3, 'lemma');
  // Без приставки: «возлюбил» → «любить»
  for (final pre in _prefixes) {
    if (!key.startsWith(pre) || key.length - pre.length < 4) continue;
    final rest = key.substring(pre.length);
    hits = StudyData.dictGetMany(moduleId, [rest]).isNotEmpty ? [rest] : byLemma(rest);
    if (hits.isNotEmpty) return make(hits, 2, 'root');
  }
  // Ближайшие слова с той же основой: сначала с той же основой целиком, потом по близости длины
  final st = stem(key);
  final near = StudyData.dictPrefix(moduleId, st, 50);
  final order = {for (final (i, k) in near.indexed) k: i};
  near.sort((a, b) {
    final c = (stem(a) == st ? 0 : 1) - (stem(b) == st ? 0 : 1);
    if (c != 0) return c;
    final d = (a.length - key.length).abs() - (b.length - key.length).abs();
    return d != 0 ? d : order[a]!.compareTo(order[b]!); // сортировка в Dart не стабильна
  });
  return make(near, 4, 'stem');
}

// Последние запросы помним: окно статьи открывается уже с готовым ответом
final _recent = <String, LookupResult>{};

/// Статьи для слова. [strongs] и [morph] — из разметки перевода (пусто — приблизительно по симфонии)
LookupResult lookupWord({required String text, required List<String> strongs, required List<String> morph, required String book, required int chapter, required int verse}) {
  final key = '$text|${strongs.join(',')}|${morph.join(',')}|$book.$chapter.$verse';
  final hit = _recent.remove(key);
  if (hit != null) return _recent[key] = hit;
  final r = _lookupNow(text, strongs, morph, book);
  _recent[key] = r;
  if (_recent.length > 12) _recent.remove(_recent.keys.first);
  return r;
}

LookupResult _lookupNow(String text, List<String> tokenStrongs, List<String> morph, String book) {
  final modules = StudyData.dictionaries().where(_ruStrongs).toList();
  final prefix = isNt(book) ? 'G' : 'H';
  final lower = text.toLowerCase();
  final norm = normalizeWord(text);

  Mapping mapping;
  if (tokenStrongs.isNotEmpty) {
    mapping = Mapping('exact', tokenStrongs.map(strongKey).toList(), morph: morph);
  } else {
    final candidates = <String, int>{};
    for (final m in modules) {
      var idx = StudyData.windex(m.id, lower);
      if (idx.isEmpty) idx = StudyData.windex(m.id, norm);
      for (final (s, n) in idx) {
        if (!s.startsWith(prefix)) continue;
        candidates[strongKey(s)] = (candidates[strongKey(s)] ?? 0) + n;
      }
    }
    final order = {for (final (i, e) in candidates.entries.indexed) e.key: i};
    final list = (candidates.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : order[a.key]!.compareTo(order[b.key]!))).take(4).toList();
    final total = list.fold<int>(0, (n, e) => n + e.value);
    mapping = list.isEmpty ? Mapping('none', const []) : Mapping('approx', [for (final e in list) e.key], weights: {for (final e in list) e.key: e.value / total});
  }

  final results = <ModResult>[];
  for (final m in modules) {
    final found = <Found>[];
    if (StudyData.dictKind(m) == 'strongs') {
      for (final s in mapping.strongs) {
        var e = StudyData.dictGet(m.id, s);
        e ??= StudyData.dictGet(m.id, s.replaceFirstMapped(RegExp(r'^([HG])(\d+)$'), (x) => x.group(1)! + x.group(2)!.padLeft(4, '0')));
        if (e != null) found.add(Found(s, e, mapping.mode));
      }
    } else {
      found.addAll(_findWord(m.id, text));
    }
    if (found.isNotEmpty) results.add(ModResult(m, found));
  }
  return LookupResult(text, mapping, results, modules.length);
}

/// Статья по номеру Стронга (переход по ссылке «от H24» внутри статьи)
/// Статьи Стронга — только русские словари (английские Стронг, Abbott-Smith, BDB в статьях не показываем)
bool _ruStrongs(InstalledModule m) => StudyData.dictKind(m) != 'strongs' || m.language == 'ru';

List<ModResult> lookupStrong(String num) {
  final out = <ModResult>[];
  for (final m in StudyData.dictionaries(strongsOnly: true).where(_ruStrongs)) {
    final e = StudyData.dictGet(m.id, num);
    if (e != null) out.add(ModResult(m, [Found(num, e, 'exact')]));
  }
  return out;
}

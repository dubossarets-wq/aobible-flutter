// Приблизительное чтение слов оригинала русскими буквами (для подстрочника): порт src/core/translit.js.
// Греческий — по эразмову произношению; еврейский — по огласовкам (никуд).
import 'greek_nfd.dart';

const _gr = {
  'α': 'а', 'β': 'б', 'γ': 'г', 'δ': 'д', 'ε': 'е', 'ζ': 'дз', 'η': 'э', 'θ': 'т', 'ι': 'и', 'κ': 'к', 'λ': 'л', 'μ': 'м',
  'ν': 'н', 'ξ': 'кс', 'ο': 'о', 'π': 'п', 'ρ': 'р', 'σ': 'с', 'ς': 'с', 'τ': 'т', 'υ': 'ю', 'φ': 'ф', 'χ': 'х', 'ψ': 'пс', 'ω': 'о',
};
const _grPairs = [
  ['αυ', 'ау'], ['ευ', 'эу'], ['ηυ', 'эу'], ['ου', 'у'], ['υι', 'юи'],
  ['γγ', 'нг'], ['γκ', 'нк'], ['γξ', 'нкс'], ['γχ', 'нх'],
];

final _combining = RegExp('[̀-ͯ]');

/// NFD для греческих букв (таблица greek_nfd.dart)
String _nfd(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(greekNfd[ch] ?? ch);
  }
  return b.toString();
}

String greekToRu(String word) {
  final d = _nfd(word);
  // густое придыхание (U+0314) в начале слова или ῥ
  final rough = RegExp('^[^̀-ͯ]*[̀-ͯ]*̔').hasMatch(d) || word.startsWith('ῥ');
  final s = d.replaceAll(_combining, '').toLowerCase();
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final pair = _grPairs.where((p) => s.startsWith(p[0], i)).firstOrNull;
    if (pair != null) {
      out.write(pair[1]);
      i += 2;
      continue;
    }
    final ch = s[i];
    out.write(_gr[ch] ?? (RegExp('[a-zа-я]', caseSensitive: false).hasMatch(ch) ? ch : ''));
    i++;
  }
  final o = out.toString();
  return (rough && !o.startsWith('р') ? 'х' : '') + o;
}

// Еврейский: согласные + огласовки. Дагеш в בכפ — взрывные (б, к, п), без него — в, х, ф.
const _he = {
  'א': '', 'ב': 'в', 'ג': 'г', 'ד': 'д', 'ה': 'х', 'ו': 'в', 'ז': 'з', 'ח': 'х', 'ט': 'т', 'י': 'й', 'כ': 'х', 'ך': 'х', 'ל': 'л',
  'מ': 'м', 'ם': 'м', 'נ': 'н', 'ן': 'н', 'ס': 'с', 'ע': '', 'פ': 'ф', 'ף': 'ф', 'צ': 'ц', 'ץ': 'ц', 'ק': 'к', 'ר': 'р', 'ש': 'ш', 'ת': 'т',
};
const _hard = {'ב': 'б', 'כ': 'к', 'ך': 'к', 'פ': 'п', 'ף': 'п'};
const _vow = {
  'ְ': 'е', 'ֱ': 'е', 'ֲ': 'а', 'ֳ': 'о', 'ִ': 'и', 'ֵ': 'е', 'ֶ': 'е', 'ַ': 'а',
  'ָ': 'а', 'ֹ': 'о', 'ֺ': 'о', 'ֻ': 'у', 'ׇ': 'о',
};
const _dagesh = 'ּ', _holam = 'ֹ', _sin = 'ׂ', _shva = 'ְ';

final _cantillation = RegExp('[֑-ֽ֯׀׃־]');
final _notHeLetter = RegExp('[^א-ת]');
final _shvaBlock = RegExp('[ֱ-ׇֻ]');

String hebrewToRu(String word) {
  final s = word.replaceAll(_cantillation, ''); // кантилляция, метег, макаф
  // Имя Божье (огласовано гласными «Адонай») — традиционное «Иегова», с приставкой (ла-, ва-, ми-…)
  final bare = s.replaceAll(_notHeLetter, '');
  if (bare.endsWith('יהוה')) {
    final chars = s.split('');
    var cut = -1;
    for (var i = 0; i < chars.length; i++) {
      if (chars[i] == 'י' && chars.sublist(i).join().replaceAll(_notHeLetter, '') == 'יהוה') {
        cut = i;
        break;
      }
    }
    return (cut > 0 ? hebrewToRu(chars.sublist(0, cut).join()) : '') + (cut > 0 ? 'иегова' : 'Иегова');
  }
  final letters = <(String, StringBuffer)>[];
  for (final ch in s.split('')) {
    if (_he.containsKey(ch)) {
      letters.add((ch, StringBuffer()));
    } else if (letters.isNotEmpty) {
      letters.last.$2.write(ch);
    }
  }
  final out = StringBuffer();
  for (var i = 0; i < letters.length; i++) {
    final c = letters[i].$1;
    final marks = letters[i].$2.toString();
    final dagesh = marks.contains(_dagesh);
    final vowels = [for (final m in marks.split('')) if (_vow[m] != null) _vow[m]!];
    final last = i == letters.length - 1;
    final soFar = out.toString();
    if (c == 'ו' && vowels.isEmpty && dagesh) {
      out.write('у'); // шурук
      continue;
    }
    if (c == 'ו' && marks.contains(_holam) && i > 0) {
      out.write('о'); // холам-мале
      continue;
    }
    var cons = dagesh && _hard[c] != null ? _hard[c]! : _he[c]!;
    if (c == 'ש' && marks.contains(_sin)) cons = 'с'; // син
    if (c == 'ה' && last && !dagesh) cons = ''; // немая хе в конце
    if (c == 'י' && vowels.isEmpty && i > 0 && RegExp('[иеэ]\$').hasMatch(soFar)) cons = ''; // йуд как знак долготы
    final v = vowels.where((x) => x != 'е' || !marks.contains(_shva) || !last).firstOrNull ?? '';
    final shva = marks.contains(_shva) && !_shvaBlock.hasMatch(marks);
    out.write(cons + (shva ? (i == 0 ? 'е' : '') : v));
  }
  return out.toString();
}

String translit(String word) {
  if (RegExp('[֐-׿]').hasMatch(word)) return hebrewToRu(word);
  if (RegExp('[Ͱ-Ͽἀ-῿]').hasMatch(word)) return greekToRu(word);
  return '';
}

// Разметка стиха (формат aob-module, docs/MODULE_SCHEMA.md веб-версии):
//   {текст|H7225}            — слово с номером Стронга
//   {текст|H1254 H853|TH8804} — несколько номеров и морфология
//   ‹текст›                  — слова, добавленные переводчиками (курсив)
// Разбор — один проход регулярным выражением; результат кэшируется на уровне главы (см. bible_db.dart).

class Token {
  const Token(this.text, {this.strongs = const [], this.morph = const [], this.italic = false});
  final String text;
  final List<String> strongs;
  final List<String> morph;
  final bool italic;
  bool get tagged => strongs.isNotEmpty;
}

final _re = RegExp(r'\{([^|}]*)\|([^|}]*)(?:\|([^}]*))?\}|‹([^›]*)›');

List<Token> parseVerse(String raw) {
  final out = <Token>[];
  var pos = 0;
  for (final m in _re.allMatches(raw)) {
    if (m.start > pos) out.add(Token(raw.substring(pos, m.start)));
    if (m.group(4) != null) {
      out.add(Token(m.group(4)!, italic: true));
    } else {
      out.add(Token(
        m.group(1)!,
        strongs: m.group(2)!.split(' ').where((s) => s.isNotEmpty).toList(),
        morph: (m.group(3) ?? '').split(' ').where((s) => s.isNotEmpty).toList(),
      ));
    }
    pos = m.end;
  }
  if (pos < raw.length) out.add(Token(raw.substring(pos)));
  return out;
}

/// Текст без разметки — для поиска, копирования и «Поделиться»
String plainText(String raw) => raw.replaceAllMapped(_re, (m) => m.group(4) ?? m.group(1)!);

/// Слово стиха — то, на что можно нажать (tokenize/wordAt в веб-версии): слово с номером Стронга — целиком,
/// в обычном тексте — каждое слово отдельно. start/end — границы внутри текста фрагмента token.
class Word {
  const Word(this.token, this.start, this.end);
  final int token; // номер фрагмента в parseVerse()
  final int start;
  final int end;
}

final _wordRe = RegExp(r"[\p{L}\p{M}]+(?:[-’'][\p{L}\p{M}]+)*", unicode: true);

/// Слова стиха по порядку; индекс в списке — номер слова (data-i в веб-версии), по нему «Часть стиха» и любимые части
List<Word> wordsOf(List<Token> tokens) {
  final out = <Word>[];
  for (var i = 0; i < tokens.length; i++) {
    final tk = tokens[i];
    if (tk.tagged) {
      out.add(Word(i, 0, tk.text.length));
    } else {
      for (final m in _wordRe.allMatches(tk.text)) {
        out.add(Word(i, m.start, m.end));
      }
    }
  }
  return out;
}

/// Текст части стиха: от первого до последнего выбранного слова (знаки между ними сохраняются), пробелы сжаты
String partText(List<Token> tokens, List<Word> words, int from, int to) {
  if (words.isEmpty) return '';
  final a = words[from.clamp(0, words.length - 1)], z = words[to.clamp(0, words.length - 1)];
  final first = a.token < z.token || (a.token == z.token && a.start <= z.start) ? a : z;
  final last = identical(first, a) ? z : a;
  final b = StringBuffer();
  for (var i = first.token; i <= last.token; i++) {
    final t = tokens[i].text;
    b.write(t.substring(i == first.token ? first.start : 0, i == last.token ? last.end : t.length));
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

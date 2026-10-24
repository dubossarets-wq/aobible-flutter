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

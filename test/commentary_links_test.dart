// Ссылки в толкованиях: места целиком (римские главы — арабскими), «ст. N», номера Стронга, слова оригинала.
import 'package:flutter_test/flutter_test.dart';

import 'package:kolos/core/books.dart';
import 'package:kolos/features/study/commentary_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Books.load());

  List<(String, bool)> parts(String s) => [
        for (final (t, f) in commentaryParts(s, book: 'Rut', chapter: 1, onVerse: (_, _) {}, onStrong: (_) {}, onWord: (_) {})) (t, f != null),
      ];

  test('римская глава — арабской, ссылка на всё место', () {
    final p = parts('(ср. Иер II:27); (Исх XXXIV:16; Втор VII:3)');
    final links = [for (final (t, l) in p) if (l) t];
    expect(links, ['Иер 2:27', 'Исх 34:16', 'Втор 7:3']);
  });

  test('«ст. 14» и «IV:10» — целиком', () {
    final links = [for (final (t, l) in parts('на Руфи (IV:10), (ст. 14, ср.') ) if (l) t];
    expect(links, ['4:10', 'ст. 14']);
  });

  test('список стихов: первое место целиком, остальные — числами', () {
    final links = [for (final (t, l) in parts('Втор XXV:6, 9') ) if (l) t];
    expect(links, ['Втор 25:6', '9']);
  });

  test('текст вне ссылок не теряется', () {
    final s = 'Смотри Быт XXXVIII:7-11; далее';
    expect([for (final (t, _) in parts(s)) t].join(), 'Смотри Быт 38:7-11; далее');
  });

  test('греческое слово и номер Стронга', () {
    final links = [for (final (t, l) in parts('LXX: αγχιστευς, G26') ) if (l) t];
    expect(links, ['αγχιστευς', 'G26']);
  });
}

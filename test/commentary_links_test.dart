// Ссылки в толкованиях: места целиком (римские главы — арабскими), «ст. N», номера Стронга, слова оригинала.
import 'package:flutter_test/flutter_test.dart';

import 'package:kolos/core/bible.dart';
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

  test('место, приклеенное к слову, получает пробел', () {
    final s = 'раба: Я есмь путьИн 14:6. И первенец из мертвыхОткр 1:5 проложил';
    expect([for (final (t, _) in parts(s)) t].join(), 'раба: Я есмь путь Ин 14:6. И первенец из мертвых Откр 1:5 проложил');
    expect([for (final (t, l) in parts(s)) if (l) t], ['Ин 14:6', 'Откр 1:5']);
  });

  test('диапазон стихов с любым тире — одной ссылкой', () {
    for (final dash in ['-', '‐', '‑', '‒', '–', '—', '−']) {
      final links = [for (final (t, l) in parts('(См. Флп 2:6${dash}7)')) if (l) t];
      expect(links, ['Флп 2:6${dash}7'], reason: 'тире U+${dash.codeUnitAt(0).toRadixString(16)}');
    }
  });

  test('словарь: римская глава через запятую, римский номер книги', () {
    List<String> links(String s) => [for (final (t, l) in parts(s)) if (l) t];
    expect(links('а) (Быт. XXXVIII, 6, 11, 13, 24) невестка'), ['Быт. 38:6', '11', '13', '24']);
    expect(links('Христа (Мф. I, 3).'), ['Мф. 1:3']);
    expect(links('б) (II Цар. XIII, 1) дочь'), ['2 Цар. 13:1']);
    expect(links('см. (II Цар. XIII).'), ['2 Цар. 13']);
    expect(links('По Иосифу Флавию (Древ. VII, 8, 1), матерью'), <String>[]);
    expect(links('Быт 1, 2 и далее'), <String>[]);
  });

  test('«ст. N» — к последнему названному месту', () {
    VerseRef? got;
    final p = commentaryParts('(Быт. XXXVIII, 6) не угодил Господу (ст. 7).', book: 'Rut', chapter: 1, onVerse: (r, _) => got = r, onStrong: (_) {}, onWord: (_) {});
    final st = p.firstWhere((x) => x.$1 == 'ст. 7');
    st.$2!();
    expect(got, VerseRef('Gen', 38, 7));
  });
}

import 'package:aobible/core/books.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Books.load());

  String? id(String q) => Books.instance.parseHuman(q)?.book;

  test('Фессалоникийцам: фс, фес, фесс, с номером и без', () {
    for (final q in ['фс 1 4', '1 фс 4', '1фс 4', '1 фес 4', '1-е фес 4', '1 фесс 4', 'фессал 2 1', '1 Фессалоникийцам 4']) {
      expect(id(q), '1Thess', reason: q);
    }
    for (final q in ['2 фс 1', '2фес 1', '2 фесс 3']) {
      expect(id(q), '2Thess', reason: q);
    }
    expect(Books.instance.parseHuman('фс 1 4')!.chapter, 1);
    expect(Books.instance.parseHuman('фс 1 4')!.verse, 4);
  });

  test('сокращения по согласным и началам — для всех книг', () {
    final cases = {
      'флп 2': 'Phil', 'фил 2': 'Phil', 'флм 1': 'Phlm', 'филим 1': 'Phlm', '1 тм 3': '1Tim', '2 тим 2': '2Tim', 'тт 1': 'Titus',
      '1 пт 1': '1Pet', '2 пет 1': '2Pet', '1 кр 13': '1Cor', '2 кор 5': '2Cor', 'рм 8': 'Rom', 'гл 5': 'Gal', 'еф 6': 'Eph',
      'кл 3': 'Col', 'евр 11': 'Heb', 'иак 1': 'Jas', 'иуд 1': 'Jude', 'откр 21': 'Rev', 'отк 21': 'Rev', 'апок 1': 'Rev',
      'мф 5': 'Matt', 'матф 5': 'Matt', 'мк 1': 'Mark', 'лк 2': 'Luke', 'ин 3': 'John', 'иоан 3': 'John', 'деян 2': 'Acts',
      'быт 1': 'Gen', 'бт 1': 'Gen', 'исх 20': 'Exod', 'лев 19': 'Lev', 'чис 6': 'Num', 'втор 6': 'Deut', 'нав 1': 'Josh',
      'суд 6': 'Judg', 'руф 1': 'Ruth', '1 цар 17': '1Sam', '3 цар 18': '1Kgs', '4 цар 2': '2Kgs', '1 пар 1': '1Chr',
      'езд 1': 'Ezra', 'неем 1': 'Neh', 'есф 4': 'Esth', 'иов 1': 'Job', 'пс 22': 'Ps', 'псал 22': 'Ps', 'притч 3': 'Prov',
      'пр 3': 'Prov', 'еккл 3': 'Eccl', 'песн 2': 'Song', 'ис 53': 'Isa', 'иер 29': 'Jer', 'плач 3': 'Lam', 'иез 37': 'Ezek',
      'дан 9': 'Dan', 'ос 6': 'Hos', 'иоил 2': 'Joel', 'ам 5': 'Amos', 'авд 1': 'Obad', 'ион 1': 'Jonah', 'мих 6': 'Mic',
      'наум 1': 'Nah', 'авв 2': 'Hab', 'соф 3': 'Zeph', 'агг 1': 'Hag', 'зах 9': 'Zech', 'мал 3': 'Mal',
    };
    cases.forEach((q, b) => expect(id(q), b, reason: q));
  });

  test('у каждой книги работают начала названия от двух-трёх букв', () {
    for (final b in Books.instance.all) {
      final name = b.name.toLowerCase().replaceAll(RegExp(r'^[1-4](-?[а-я]{1,2})?\s*'), '').replaceAll(RegExp(r'[\s.-]'), '');
      final num = RegExp(r'^([1-4])').firstMatch(b.name)?.group(1) ?? '';
      final q = '$num ${name.substring(0, name.length < 5 ? name.length : 5)} 1';
      expect(id(q), b.id, reason: '$q → ${b.name}');
    }
  });
}

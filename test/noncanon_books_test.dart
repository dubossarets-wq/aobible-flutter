// Неканонические книги в справочнике: свои ссылки распознаются, канонические сокращения не перехвачены,
// в планах «Вся Библия» и «Ветхий Завет» их нет
import 'package:aobible/core/books.dart';
import 'package:aobible/features/plans/plan_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Books.load);

  test('ссылки: неканонические книги и прежние сокращения', () {
    final b = Books.instance;
    String? id(String s) => b.parseHuman(s)?.book;
    expect(id('Енох 1:9'), '1En');
    expect(id('Юбил 3:1'), 'Jub');
    expect(id('Сус 1:5'), 'Sus');
    expect(id('Зав.Рув. 1:2'), 'TReu');
    // канонические остаются за своими книгами
    expect(id('Пс 151:1'), 'Ps');
    expect(id('Дан 3:24'), 'Dan');
    expect(id('Зах 1:1'), 'Zech');
    expect(id('Суд 1:1'), 'Judg');
    expect(id('Втор 1:1'), 'Deut');
    expect(id('1 Ин 3:16'), '1John');
    expect(id('Ин 3:16'), 'John');
    expect(id('Иуд 1:1'), 'Jude');
    expect(id('Вар 1:1'), 'Bar');
  });

  test('планы: без неканонических книг', () {
    final all = planScopes.firstWhere((s) => s.id == 'all').books();
    final ot = planScopes.firstWhere((s) => s.id == 'ot').books();
    expect(all.length, 66);
    expect(ot.length, 39);
    expect(all.contains('Tob') || all.contains('1En'), false);
    expect(Books.instance.meta('1En').dc, true);
    expect(Books.instance.meta('Gen').dc, false);
  });
}

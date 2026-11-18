// Поиск: слова в любом порядке и с пропусками; по желанию — в заданном порядке; фраза в кавычках — подряд.
import 'package:flutter_test/flutter_test.dart';
import 'package:kolos/core/bible.dart';

void main() {
  test('слова запроса: каждое отдельно, фраза в кавычках — одной', () {
    expect(queryTokens('бог любовь'), ['бог', 'любовь']);
    expect(queryTokens('"бог есть" любовь'), ['бог есть', 'любовь']);
    expect(queryTokens('«свет миру»'), ['свет миру']);
  });

  test('любой порядок и пропуски слов', () {
    final m = QueryMatcher('любовь бог');
    expect(m.matches('Бог есть любовь'), true);
    expect(m.matches('И любил Бог мир, и была любовь'), true);
    expect(m.matches('Только любовь'), false);
  });

  test('заданный порядок: слова друг за другом, но с пропусками', () {
    final m = QueryMatcher('бог любовь', ordered: true);
    expect(m.matches('Бог, который есть любовь'), true);
    expect(m.matches('Любовь от Бога'), false);
    expect(QueryMatcher('любовь бог', ordered: true).matches('Любовь от Бога'), true);
  });

  test('только целые слова и фраза в кавычках', () {
    expect(QueryMatcher('бог', wholeWord: true).matches('богатый человек'), false);
    expect(QueryMatcher('бог', wholeWord: true).matches('и Бог сказал'), true);
    expect(QueryMatcher('"бог есть" любовь').matches('любовь: Бог есть свет'), true);
    expect(QueryMatcher('"есть бог" любовь').matches('Бог есть любовь'), false);
    expect(QueryMatcher('ёлка').matches('зелёная ЕЛКА'), true); // ё = е
  });
}

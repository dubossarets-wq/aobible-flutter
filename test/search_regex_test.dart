import 'package:aobible/core/bible.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('часть слова, ё = е, ударение не мешает', () {
    final re = queryRegex('свет')!;
    expect(re.hasMatch('рассвет'), isTrue);
    expect(re.hasMatch('Светильник'), isTrue);
    expect(queryRegex('еще')!.hasMatch('ещё'), isTrue);
    expect(queryRegex('возлюбил')!.hasMatch('возлюби́л'), isTrue);
  });
  test('целые слова и фраза', () {
    expect(queryRegex('свет', wholeWord: true)!.hasMatch('светильник'), isFalse);
    expect(queryRegex('свет', wholeWord: true)!.hasMatch('да будет свет.'), isTrue);
    expect(queryRegex('бог любовь')!.hasMatch('Бог, любовь'), isTrue);
    expect(queryRegex('бог любовь')!.hasMatch('любовь Бог'), isFalse);
  });
}

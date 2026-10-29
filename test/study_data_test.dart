// Проверка «изучения» на настоящих данных: установка модулей с aobible.app, статьи Стронга, симфония,
// слова по основе, параллельные места, комментарии, иллюстрации, статистика слова, подстрочник.
import 'dart:io';

import 'package:aobible/core/books.dart';
import 'package:aobible/core/modules.dart';
import 'package:aobible/features/study/interlinear.dart';
import 'package:aobible/features/study/lexicon.dart';
import 'package:aobible/features/study/morph.dart';
import 'package:aobible/features/study/study_data.dart';
import 'package:aobible/features/study/translit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('изучение: словари, ссылки, комментарии, иллюстрации, подстрочник', () async {
    await Books.load();
    final store = await ModuleStore.initAt(Directory('${Directory.systemTemp.path}/aob_test_modules_study'));
    final cat = await store.catalog();
    for (final id in ['rst-plus', 'strongs-ru-hebrew', 'strongs-ru-greek', 'rst-symphony', 'nikifor', 'xrefs-rst', 'lopukhin', 'bible-illustrations', 'oshb', 'byz-rp2018', 'vin-interlinear']) {
      if (store.get(id) == null) {
        final sw = Stopwatch()..start();
        await store.install(cat.firstWhere((e) => e.id == id));
        // ignore: avoid_print
        print('установка $id: ${sw.elapsedMilliseconds} мс');
      }
    }
    await StudyData.ensure();

    // Точная привязка: «сотворил» Быт 1:1 — H1254
    final r = lookupWord(text: 'сотворил', strongs: ['H1254', 'H853'], morph: ['TH8804'], book: 'Gen', chapter: 1, verse: 1);
    expect(r.mapping.mode, 'exact');
    final ru = r.results.firstWhere((x) => x.module.id == 'strongs-ru-hebrew');
    expect(ru.found.first.key, 'H1254');
    // симфония — внутри статьи Стронга, отдельным словарём не показывается
    expect(r.results.any((x) => x.module.id == 'rst-symphony'), false);
    expect(describeMorph('TH8804'), isNotNull);
    // ignore: avoid_print
    print('морфология TH8804: ${describeMorph('TH8804')}; V-PAI-1S: ${describeMorph('V-PAI-1S')}; HVqp3ms: ${describeMorph('HVqp3ms')}');

    // Без разметки: приблизительно по симфонии, словарь по словам — по основе
    var sw = Stopwatch()..start();
    final a = lookupWord(text: 'благодати', strongs: [], morph: [], book: 'Rom', chapter: 1, verse: 7);
    // ignore: avoid_print
    print('«благодати»: ${a.mapping.mode} ${a.mapping.strongs}, ${a.results.map((x) => '${x.module.name}:${x.found.map((f) => f.key).join(",")}').join(" | ")} (${sw.elapsedMilliseconds} мс)');
    expect(a.mapping.mode, 'approx');
    final b = lookupWord(text: 'Аарона', strongs: [], morph: [], book: 'Exod', chapter: 4, verse: 14);
    expect(b.results.any((x) => x.module.id == 'nikifor' && x.found.first.key == 'аарон'), true);

    // Статистика слова
    sw = Stopwatch()..start();
    final st = (await StudyData.strongStats('H1254'))!;
    // ignore: avoid_print
    print('H1254: ${st.total} раз в ${st.verses} стихах, ${st.byBook.length} книгах (${sw.elapsedMilliseconds} мс)');
    expect(st.total, greaterThan(40));

    // Параллельные места, комментарии, иллюстрации
    final refs = StudyData.refsForVerse('rst-plus', const VerseRef('Gen', 1, 1));
    expect(refs.length, greaterThan(5));
    final tx = StudyData.textForRef('rst-plus', refs.firstWhere((x) => x.osis == 'John.1.1-3').ref);
    expect(tx.$1.length, 3);
    expect(StudyData.xrefCounts('rst-plus', 'Gen')[1001], greaterThan(5));
    expect(StudyData.commentaryIndex('Gen')[1002], isNotNull);
    expect(StudyData.commentaryFor(const VerseRef('Gen', 1, 2)).first.items.first.text, isNotEmpty);
    expect(StudyData.illustrationsFor(const VerseRef('Gen', 1, 3)).first['img'], isNotNull);

    // Подстрочник
    sw = Stopwatch()..start();
    final ot = origInterlinear(const VerseRef('Gen', 1, 1))!;
    // ignore: avoid_print
    print('Быт 1:1 (${sw.elapsedMilliseconds} мс): ${ot.map((w) => '${w.text}/${translit(w.text)}/${w.gloss}/${w.num}').join("  ")}');
    expect(ot.length, 7);
    expect(ot.first.gloss, isNotEmpty);
    final nt = origInterlinear(const VerseRef('John', 3, 16))!;
    // ignore: avoid_print
    print('Ин 3:16: ${nt.map((w) => '${w.text}/${translit(w.text)}/${w.gloss}/${w.num}').join("  ")}');
    expect(nt.first.gloss, isNotEmpty);
    final vin = (await vinInterlinear(const VerseRef('John', 3, 16)))!;
    expect(vin, isNotEmpty);
    final ruw = ruInterlinear(const VerseRef('John', 3, 16))!;
    expect(ruw.any((w) => w.orig.isNotEmpty), true);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

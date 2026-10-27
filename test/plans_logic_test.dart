// Планы чтения: стих дня, дни плана, отметки, учёт прочитанного, напоминания, множественное число.
import 'package:aobible/core/books.dart';
import 'package:aobible/core/settings.dart';
import 'package:aobible/features/plans/loc.dart';
import 'package:aobible/features/plans/plan_logic.dart';
import 'package:aobible/features/plans/reminders.dart';
import 'package:aobible/features/plans/verse_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Plan plan({bool calendar = false, String start = '2026-10-20', int days = 5}) => {
      'uid': 'p1',
      'planId': 'x',
      'name': 'Тест',
      'calendar': calendar,
      'start': start,
      'readings': [
        for (var i = 0; i < days; i++) i == 1 ? ['Ps.119-120', 'John.3'] : ['Gen.${i + 1}'],
      ],
      'done': <String, dynamic>{},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('стих дня: 366 ссылок, выбор по дате постоянный, за год без повторов', () {
    expect(verseList.length, 366);
    expect(verseOfDayKey(DateTime(2026, 10, 24)), verseOfDayKey(DateTime(2026, 10, 24, 23, 59)));
    final seen = <String>{};
    for (var d = DateTime(2026, 1, 1); d.year == 2026; d = DateTime(d.year, d.month, d.day + 1)) {
      seen.add(verseOfDayKey(d));
    }
    expect(seen.length, 365);
    expect(verseList.every((k) => RegExp(r'^\w+\.\d+\.\d+$').hasMatch(k)), true);
    expect(dayOfYear(DateTime(2026, 1, 1)), 0);
    expect(dayOfYear(DateTime(2028, 12, 31)), 365);
  });

  test('календарный индекс: 29 февраля пропускается, максимум 364', () {
    expect(calendarIndex(DateTime(2027, 3, 1)), 59);
    expect(calendarIndex(DateTime(2028, 2, 28)), 58);
    expect(calendarIndex(DateTime(2028, 2, 29)), 58);
    expect(calendarIndex(DateTime(2028, 3, 1)), 59);
    expect(calendarIndex(DateTime(2028, 12, 31)), 364);
  });

  test('отрывки: главы, диапазон глав, стихи', () {
    expect(readingUnits('Gen.1').single.key, 'Gen.1');
    expect(readingUnits('Ps.119-120').map((u) => u.key), ['Ps.119', 'Ps.120']);
    final v = readingUnits('Ps.9.1-21').single;
    expect((v.chapter, v.from, v.to, v.key), (9, 1, 21, 'Ps.9.1-21'));
    expect(readingUnits('Zech.13.1').single.to, 1);
  });

  test('день плана: сегодня, пропущенные, завершение', () {
    final p = plan(start: '2026-10-20');
    final now = DateTime(2026, 10, 22, 10);
    expect(planToday(p, now), 2);
    expect(behindDays(p, now), [0, 1]);
    // день 1 — три главы из двух отрывков: отмечаем по частям
    var r = markUnitsIn([p], 'p1', 1, ['Ps.119']);
    expect(r.finished, false);
    r = markUnitsIn(r.plans, 'p1', 1, ['Ps.120']);
    expect(r.finished, false);
    r = markUnitsIn(r.plans, 'p1', 1, ['John.3']);
    expect(r.finished, true);
    expect(dayDone(r.plans.single, 1), true);
    expect(behindDays(r.plans.single, now), [0]);
    expect(readingDone(r.plans.single, 1, 'Ps.119-120'), true);
  });

  test('глава в обычном чтении засчитывается в сегодняшний день, потом в пропущенные', () {
    final p = plan(start: '2026-10-20');
    final now = DateTime(2026, 10, 22);
    var r = creditChapterIn([p], 'Gen', 3, now); // сегодня (день 2) = Gen.3
    expect(r.credited, ['Тест']);
    expect(r.finished, ['Тест']);
    r = creditChapterIn(r.plans, 'Gen', 1, now); // пропущенный день 0
    expect(dayDone(r.plans.single, 0), true);
    r = creditChapterIn(r.plans, 'Matt', 1, now); // не из плана
    expect(r.credited, isEmpty);
  });

  test('календарный план в новом году начинается заново', () {
    final p = plan(calendar: true, start: '2025-01-01')
      ..['done'] = {'0': 1, '1': 1}
      ..['year'] = 2025;
    final out = applyNewYear([p], 2026).single;
    expect(out['year'], 2026);
    expect(out['start'], '2026-01-01');
    expect((out['done'] as Map), isEmpty);
    expect((out['history'] as Map)['2025'], 2);
    // тот же год — список не меняется
    final same = [plan(calendar: true)..['year'] = 2026];
    expect(identical(applyNewYear(same, 2026), same), true);
  });

  test('prefs «plans»: сохранение и загрузка', () {
    savePlans([plan()]);
    expect(loadPlans().single['uid'], 'p1');
  });

  test('учёт прочитанного: запись, серия дней, неделя', () {
    final now = DateTime(2026, 10, 24, 12);
    expect(logChapter('Gen', 1, now), true);
    expect(logChapter('Gen', 1, now), false); // в тот же день — второй раз не пишется
    logChapter('Gen', 2, DateTime(2026, 10, 23));
    logChapter('Gen', 1, DateTime(2026, 10, 22));
    logChapter('Matt', 1, DateTime(2026, 10, 20)); // 21-го перерыв в серии
    final st = readStatsOf(readLogData(), now);
    expect(st.today, 1);
    expect(st.streak, 3);
    expect(st.total, 3); // Gen.1, Gen.2, Matt.1
    expect(st.week, 4);
    expect(st.days7.length, 7);
    expect(st.days7.last.n, 1);
    // сегодня ещё не читал — серия не обрывается
    expect(readStatsOf(readLogData(), DateTime(2026, 10, 25, 8)).streak, 3);
    expect(minSeconds(1), 8);
    expect(minSeconds(100), 120);
  });

  test('свой план: главы делятся по дням поровну', () {
    final days = splitChapters([for (var i = 1; i <= 10; i++) (ref: 'Ps.$i', n: 10)], 5);
    expect(days.length, 5);
    expect(days.every((d) => d.length == 2), true);
    expect(days.expand((d) => d).length, 10);
    // глав меньше, чем дней — дней столько, сколько глав
    expect(splitChapters([(ref: 'Ps.1', n: 10), (ref: 'Ps.2', n: 10)], 30).length, 2);
  });

  test('напоминания: по дням плана, без завершённых и не начатых, текст отрывков', () async {
    await Books.load();
    final p = plan(start: '2026-10-24');
    final now = DateTime(2026, 10, 24, 7, 0);
    List<ReminderItem> at(String time) => [ReminderItem(id: 'r1', time: time)];
    final s = reminderSchedule([p], at('08:00'), now);
    expect(s.length, 5); // в плане 5 дней
    expect(s.first.at, DateTime(2026, 10, 24, 8));
    expect(s.first.body, contains('Тест: Быт 1'));
    expect(s[1].body, contains('Пс 119–120, Ин 3'));
    // время уже прошло — сегодняшний день пропускается
    expect(reminderSchedule([p], at('06:00'), now).length, 4);
    // день отмечен — напоминания о нём нет
    final done = markUnitsIn([p], 'p1', 0, ['Gen.1']).plans.single;
    expect(reminderSchedule([done], at('08:00'), now).length, 4);
    // план ещё не начался
    expect(reminderSchedule([plan(start: '2026-11-30')], at('08:00'), now), isEmpty);
    // несколько напоминаний и промежуток: 08:00 и с 12:00 до 16:00 каждые 2 ч (одно время совпадает — без повтора)
    final many = reminderSchedule([p], [ReminderItem(id: 'a', time: '08:00'), const ReminderItem(id: 'b', time: '12:00', every: 120, until: '16:00'), ReminderItem(id: 'c', time: '14:00')], now);
    expect([for (final n in many.where((n) => n.at.day == 24)) n.at.hour], [8, 12, 14, 16]);
    expect(many.map((n) => n.id).toSet().length, many.length, reason: 'у каждого уведомления свой номер');
    // дни недели: 24.10.2026 — суббота (6); только по субботам — один день из пяти
    expect(reminderSchedule([p], [const ReminderItem(id: 'a', time: '08:00', days: [6])], now).length, 1);
    expect(readingLabel('Ps.9.1-21'), 'Пс 9:1–21');
  });

  test('множественное число и даты', () {
    String f(int n) => tx('день подряд|дня подряд|дней подряд', {'n': n});
    expect([f(1), f(2), f(5), f(11), f(21), f(0)], ['день подряд', 'дня подряд', 'дней подряд', 'дней подряд', 'день подряд', 'дней подряд']);
    expect(tx('История@@формат картинки'), 'История');
    expect(tx('{n} место|{n} места|{n} мест', {'n': 3}), '3 места');
    expect(pluralCategory('en', 1), 'one');
    expect(pluralCategory('pl', 3), 'few');
    expect(fmtDay(DateTime(2026, 10, 5)), '5 окт.');
    expect(fmtDay(DateTime(2026, 10, 5), full: true, year: true), '5 октября 2026');
  });

  group('параллельный план', () {
    // Число глав в книгах (как в русском каноне): ВЗ — 929, НЗ — 260, из них Псалтирь — 150
    const counts = {
      'Gen': 50, 'Exod': 40, 'Lev': 27, 'Num': 36, 'Deut': 34, 'Josh': 24, 'Judg': 21, 'Ruth': 4, '1Sam': 31, '2Sam': 24, '1Kgs': 22, '2Kgs': 25,
      '1Chr': 29, '2Chr': 36, 'Ezra': 10, 'Neh': 13, 'Esth': 10, 'Job': 42, 'Ps': 150, 'Prov': 31, 'Eccl': 12, 'Song': 8, 'Isa': 66, 'Jer': 52,
      'Lam': 5, 'Ezek': 48, 'Dan': 12, 'Hos': 14, 'Joel': 3, 'Amos': 9, 'Obad': 1, 'Jonah': 4, 'Mic': 7, 'Nah': 3, 'Hab': 3, 'Zeph': 3, 'Hag': 2,
      'Zech': 14, 'Mal': 4, 'Matt': 28, 'Mark': 16, 'Luke': 24, 'John': 21, 'Acts': 28, 'Rom': 16, '1Cor': 16, '2Cor': 13, 'Gal': 6, 'Eph': 6,
      'Phil': 4, 'Col': 4, '1Thess': 5, '2Thess': 3, '1Tim': 6, '2Tim': 4, 'Titus': 3, 'Phlm': 1, 'Heb': 13, 'Jas': 5, '1Pet': 5, '2Pet': 3,
      '1John': 5, '2John': 1, '3John': 1, 'Jude': 1, 'Rev': 22,
    };
    List<({String ref, int n})> chapters(List<String> books) => [
          for (final b in books)
            for (var c = 1; c <= (counts[b] ?? 0); c++) (ref: '$b.$c', n: 10),
        ];

    setUp(() async => Books.load());

    test('книги узких разделов не повторяются в ВЗ и НЗ; порядок — библейский', () {
      final l = streamList({'ot': 1, 'nt': 1, 'ps': 1, 'gospels': 1, 'own': 1}, ['Isa', 'Acts']);
      // по первой книге: ВЗ (Быт), Псалтирь, свои (Ис), Евангелия (Мф), НЗ (Рим — Евангелия и Деяния ушли в свои разделы)
      expect(l.map((x) => x.key), ['ot', 'ps', 'own', 'gospels', 'nt']);
      expect(l[0].books, isNot(contains('Ps')));
      expect(l[0].books, isNot(contains('Isa')));
      expect(l[0].books.first, 'Gen');
      expect(l[4].books, isNot(contains('John')));
      expect(l[4].books, isNot(contains('Acts')));
      expect(l[1].books, ['Ps']);
      expect(l[2].books, ['Isa', 'Acts']);
      // в своих книгах нет тех, что уже читаются в Псалтири и Притчах
      expect(streamList({'ps': 1, 'prov': 1, 'own': 1}, ['Job', 'Ps', 'Prov']).map((x) => x.books), [['Job'], ['Ps'], ['Prov']]);
      // без узких разделов ВЗ и НЗ целиком
      final w = streamList({'ot': 1, 'nt': 1}, const []);
      expect(w[0].books, contains('Ps'));
      expect(w[1].books, contains('John'));
    });

    test('ВЗ + НЗ + Псалтирь по 1 главе — 779 дней, первый день Быт 1, Пс 1, Мф 1', () {
      final list = streamList({'ot': 1, 'nt': 1, 'ps': 1}, const []);
      final plan = makeParallelPlan(list, chapters);
      expect(plan.length, 779);
      expect(parallelDays(list, chapters), 779);
      expect(plan.first, ['Gen.1', 'Ps.1', 'Matt.1']);
      // Псалтирь (150) идёт по кругу, НЗ (260) — один раз: после него в дне только ВЗ и Псалтирь
      expect(plan[150][1], 'Ps.1');
      expect(plan[259][2], 'Rev.22');
      expect(plan[260].length, 2);
      expect(plan[260][1], startsWith('Ps.'));
      expect(plan.expand((d) => d).where((r) => r == 'Matt.1').length, 1);
    });

    test('несколько глав в день; пустой выбор — пустой план', () {
      final plan = makeParallelPlan(streamList({'nt': 3}, const []), chapters);
      expect(plan.length, 87);
      expect(plan.first, ['Matt.1', 'Matt.2', 'Matt.3']);
      expect(makeParallelPlan(streamList({'own': 1}, const []), chapters), isEmpty);
      expect(parallelDays(streamList({'own': 1}, const []), chapters), 0);
    });

    test('«За срок»: ВЗ + НЗ + Псалтирь за 365 дней — ровно 365 дней, все разделы кончаются в последний день, без повторов', () {
      final list = streamList({'ot': 1, 'nt': 1, 'ps': 1}, const []);
      final plan = makeParallelPlan(list, chapters, period: 365);
      expect(plan.length, 365);
      final all = [for (final d in plan) ...d];
      expect(all.toSet().length, all.length, reason: 'главы не повторяются');
      // каждая глава каждого раздела прочитана ровно один раз
      final want = {for (final x in list) ...chapters(x.books).map((c) => c.ref)};
      expect(all.toSet(), want);
      // последние главы разделов — в последних днях (деление по середине главы), самые длинные — в последнем
      final tail = [for (final d in plan.skip(363)) ...d];
      expect(tail, containsAll(['Rev.22', 'Ps.150', 'Mal.4']));
      expect(plan.last, contains('Mal.4'));
      // первый день начинается с первых глав разделов
      expect(plan.first, containsAll(['Gen.1', 'Matt.1']));
      // порядок разделов в дне: ВЗ, НЗ, Псалтирь
      final d1 = plan[1];
      expect(plan.first.indexOf('Gen.1') < plan.first.indexOf('Matt.1'), true);
      expect(d1.indexOf('Matt.2') < d1.indexOf('Ps.1'), true);
    });

    test('«За срок»: короткий раздел не повторяется, пустые дни убираются; пустой выбор — пустой план', () {
      final plan = makeParallelPlan(streamList({'ps': 1}, const []), chapters, period: 300);
      expect(plan.length, 150); // глав меньше дней
      expect(plan.first, ['Ps.1']);
      expect(plan.last, ['Ps.150']);
      expect(makeParallelPlan(streamList({'own': 1}, const []), chapters, period: 30), isEmpty);
      // шаги «глав в день» на «За срок» не влияют
      expect(makeParallelPlan(streamList({'nt': 5}, const []), chapters, period: 30), makeParallelPlan(streamList({'nt': 1}, const []), chapters, period: 30));
    });
  });
}

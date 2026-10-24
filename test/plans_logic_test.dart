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
    final s = reminderSchedule([p], '08:00', now);
    expect(s.length, 5); // в плане 5 дней
    expect(s.first.at, DateTime(2026, 10, 24, 8));
    expect(s.first.body, contains('Тест: Быт 1'));
    expect(s[1].body, contains('Пс 119–120, Ин 3'));
    // время уже прошло — сегодняшний день пропускается
    expect(reminderSchedule([p], '06:00', now).length, 4);
    // день отмечен — напоминания о нём нет
    final done = markUnitsIn([p], 'p1', 0, ['Gen.1']).plans.single;
    expect(reminderSchedule([done], '08:00', now).length, 4);
    // план ещё не начался
    expect(reminderSchedule([plan(start: '2026-11-30')], '08:00', now), isEmpty);
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
}

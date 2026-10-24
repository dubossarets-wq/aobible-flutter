// Планы чтения: формат и правила — как в веб-версии (src/core/plans.js, planStore.js, readLog.js).
// План — Map (JSON в prefs «plans»): { uid, planId, name, readings: [[«Gen.1», …], …], calendar, start, year, done: {день: ts},
// parts: {день: {отрывок: ts}}, history }. Отрывок: «Gen.1» — глава, «Ps.119-120» — главы, «Ps.9.1-21» — стихи главы.
// Здесь только чистая логика (без интерфейса) — её проверяют тесты test/plans_*_test.dart.
import 'dart:convert';
import 'dart:math' as math;

import '../../core/books.dart';
import '../../core/settings.dart';

typedef Plan = Map<String, dynamic>;

/// Дата по местному времени «2026-10-15»
String localDate([DateTime? d]) {
  final x = d ?? DateTime.now();
  return '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
}

DateTime _day0(Object? d) {
  if (d is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) {
    final p = d.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }
  final x = d is num ? DateTime.fromMillisecondsSinceEpoch(d.toInt()) : (DateTime.tryParse('$d') ?? DateTime.now());
  return DateTime(x.year, x.month, x.day);
}

/// Разница в днях по календарю (переход на летнее время не сбивает счёт)
int _daysBetween(DateTime a, DateTime b) => (b.difference(a).inHours / 24).round();

/// Календарный план (М'Чейн): день плана = день года, 29 февраля чтений нет (берём 28-е)
int calendarIndex([DateTime? date]) {
  final d = date ?? DateTime.now();
  var i = _daysBetween(DateTime(d.year, 1, 1), DateTime(d.year, d.month, d.day));
  final leap = DateTime(d.year, 2, 29).month == 2;
  if (leap && i >= 59) i -= 1; // после 28 февраля
  return math.min(364, i);
}

int todayIndex(Object? start, int days, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return math.max(0, math.min(days - 1, _daysBetween(_day0(start), DateTime(n.year, n.month, n.day))));
}

List<List<String>> readingsOf(Plan p) => [
      for (final d in (p['readings'] as List? ?? const [])) [for (final r in (d as List)) '$r'],
    ];

int planToday(Plan p, [DateTime? now]) =>
    p['calendar'] == true ? calendarIndex(now) : todayIndex(p['start'], readingsOf(p).length, now);

bool _has(Object? m, Object k) => m is Map && m['$k'] != null;

bool dayDone(Plan p, int day) => _has(p['done'], day);

/// Пропущенные дни до сегодняшнего (с начала плана)
List<int> behindDays(Plan p, [DateTime? now]) {
  final today = planToday(p, now);
  final from = p['calendar'] == true ? math.min(today, calendarIndex(_day0(p['start']))) : 0;
  return [for (var i = from; i < today; i++) if (!dayDone(p, i)) i];
}

class ReadingUnit {
  const ReadingUnit(this.book, this.chapter, this.from, this.to, this.key);
  final String book;
  final int chapter, from;
  final int? to; // null — до конца главы
  final String key; // по нему отмечаются прочитанные отрывки дня
}

/// Отрывки чтения: «Ps.119-120» — две главы, «Ps.9.1-21» — часть главы
List<ReadingUnit> readingUnits(String r) {
  final p = r.split('.');
  final book = p[0];
  if (p.length > 2 && p[2].isNotEmpty) {
    final v = p[2].split('-').map((s) => int.tryParse(s) ?? 0).toList();
    return [ReadingUnit(book, int.parse(p[1]), v[0], v.length > 1 && v[1] > 0 ? v[1] : v[0], r)];
  }
  final c = (p.length > 1 && p[1].isNotEmpty ? p[1] : '1').split('-').map((s) => int.tryParse(s) ?? 1).toList();
  final a = c[0], b = c.length > 1 ? c[1] : a;
  return [for (var i = 0; i <= b - a; i++) ReadingUnit(book, a + i, 1, null, '$book.${a + i}')];
}

List<ReadingUnit> dayUnits(Plan p, int day) {
  final rs = readingsOf(p);
  return day >= 0 && day < rs.length ? [for (final r in rs[day]) ...readingUnits(r)] : const [];
}

bool unitDone(Plan p, int day, String key) => _has(p['done'], day) || _has((p['parts'] as Map?)?['$day'], key);
bool readingDone(Plan p, int day, String r) => readingUnits(r).every((u) => unitDone(p, day, u.key));

/// Подпись отрывка: «Быт 1», «Пс 9:1–21», «Пс 119–120»
String readingLabel(String r) {
  final p = r.split('.');
  final name = Books.instance.meta(p[0]).short.replaceFirst(RegExp(r'\.$'), '');
  if (p.length > 2 && p[2].isNotEmpty) return '$name ${p[1]}:${p[2].replaceAll('-', '–')}';
  return '$name ${(p.length > 1 && p[1].isNotEmpty ? p[1] : '1').replaceAll('-', '–')}';
}

/// Куда перейти при нажатии на отрывок
VerseRef readingTarget(String r) {
  final u = readingUnits(r).first;
  return VerseRef(u.book, u.chapter, u.from);
}

// --- Хранение: prefs «plans» ---------------------------------------------------------------------

/// Календарный план в новом году начинается заново: отметки прошлого года не считаются прочитанными в этом
List<Plan> applyNewYear(List<Plan> list, [int? year]) {
  final y = year ?? DateTime.now().year;
  var changed = false;
  final out = <Plan>[];
  for (final p in list) {
    if (p['calendar'] != true) {
      out.add(p);
      continue;
    }
    final py = (p['year'] as num?)?.toInt() ?? int.tryParse('${p['start'] ?? ''}'.padRight(4).substring(0, 4)) ?? y;
    if (py == y) {
      if (p['year'] != null) {
        out.add(p);
      } else {
        changed = true;
        out.add({...p, 'year': y});
      }
      continue;
    }
    changed = true;
    final hist = Map<String, dynamic>.from((p['history'] as Map?) ?? const {});
    hist['$py'] = ((p['done'] as Map?) ?? const {}).length;
    out.add({...p, 'year': y, 'start': '$y-01-01', 'done': <String, dynamic>{}, 'parts': <String, dynamic>{}, 'history': hist});
  }
  return changed ? out : list;
}

List<Plan> loadPlans() {
  try {
    final raw = prefs.getString('plans');
    if (raw == null) return [];
    final v = jsonDecode(raw);
    if (v is! List) return [];
    final list = [for (final p in v) if (p is Map) Plan.from(p)];
    final fixed = applyNewYear(list);
    if (!identical(fixed, list)) savePlans(fixed);
    return fixed;
  } catch (_) {
    return [];
  }
}

void savePlans(List<Plan> plans) => prefs.setString('plans', jsonEncode(plans));

/// Отметить отрывки дня прочитанными. Возвращает новый список и признак «день завершён этим».
({List<Plan> plans, bool finished}) markUnitsIn(List<Plan> plans, String uid, int day, List<String> keys, [int? now]) {
  var finished = false;
  final out = [
    for (final p in plans)
      if (p['uid'] != uid || dayDone(p, day))
        p
      else
        () {
          final parts = Map<String, dynamic>.from((p['parts'] as Map?) ?? const {});
          final have = Map<String, dynamic>.from((parts['$day'] as Map?) ?? const {});
          final add = keys.where((k) => have[k] == null).toList();
          if (add.isEmpty) return p;
          final ts = now ?? DateTime.now().millisecondsSinceEpoch;
          for (final k in add) {
            have[k] = ts;
          }
          parts['$day'] = have;
          final all = dayUnits(p, day).every((u) => have[u.key] != null);
          finished = all;
          final done = Map<String, dynamic>.from((p['done'] as Map?) ?? const {});
          if (all) done['$day'] = ts;
          return {...p, 'parts': parts, 'done': done};
        }(),
  ];
  return (plans: out, finished: finished);
}

/// Глава дочитана в обычном чтении: засчитываем её в планы — сначала в сегодняшний день, потом в пропущенные
({List<Plan> plans, List<String> credited, List<String> finished}) creditChapterIn(List<Plan> plans, String book, int chapter, [DateTime? now]) {
  var cur = plans;
  final credited = <String>[], finished = <String>[];
  for (final p0 in plans) {
    final uid = p0['uid'];
    final p = cur.firstWhere((x) => x['uid'] == uid);
    for (final d in [planToday(p, now), ...behindDays(p, now)]) {
      if (dayDone(p, d)) continue;
      final keys = [
        for (final u in dayUnits(p, d))
          if (u.book == book && u.chapter == chapter && !_has((p['parts'] as Map?)?['$d'], u.key)) u.key,
      ];
      if (keys.isEmpty) continue;
      credited.add('${p['name']}');
      final r = markUnitsIn(cur, '$uid', d, keys);
      cur = r.plans;
      if (r.finished) finished.add('${p['name']}');
      break;
    }
  }
  return (plans: cur, credited: credited, finished: finished);
}

// --- Учёт прочитанного (prefs «readLog»: { days: { '2026-10-15': ['Gen.1', …] } }) ----------------

/// Сколько секунд нужно провести на отрывке из n стихов (быстрое чтение, с запасом)
double minSeconds(int n) => math.max(8, math.min(120, n * 2.5));

Map<String, dynamic> readLogData() {
  try {
    final raw = prefs.getString('readLog');
    if (raw != null) {
      final v = jsonDecode(raw);
      if (v is Map && v['days'] is Map) return Map<String, dynamic>.from(v);
    }
  } catch (_) {}
  return {'days': <String, dynamic>{}};
}

/// Записать дочитанную главу. true — сегодня она записана впервые.
bool logChapter(String book, int chapter, [DateTime? now]) {
  final log = readLogData();
  final days = Map<String, dynamic>.from(log['days'] as Map);
  final day = localDate(now);
  final key = '$book.$chapter';
  final list = [for (final x in (days[day] as List? ?? const [])) '$x'];
  if (list.contains(key)) return false;
  days[day] = [...list, key];
  prefs.setString('readLog', jsonEncode({...log, 'days': days}));
  return true;
}

class ReadStats {
  const ReadStats({required this.today, required this.week, required this.total, required this.recent, required this.days7, required this.streak});
  final int today, week, total, streak;
  final List<({String key, String day})> recent;
  final List<({String day, int n})> days7;
}

ReadStats readStatsOf(Map<String, dynamic> log, [DateTime? now]) {
  final days = (log['days'] as Map?) ?? const {};
  final n = now ?? DateTime.now();
  DateTime ago(int i) => DateTime(n.year, n.month, n.day - i);
  final weekAgo = localDate(ago(6));
  final all = <String>{};
  var week = 0;
  final recent = <({String key, String day})>[];
  for (final d in (days.keys.map((k) => '$k').toList()..sort())) {
    for (final k in (days[d] as List)) {
      all.add('$k');
      if (d.compareTo(weekAgo) >= 0) week++;
      recent.add((key: '$k', day: d));
    }
  }
  int cnt(int i) => ((days[localDate(ago(i))] as List?) ?? const []).length;
  final days7 = [for (final i in [6, 5, 4, 3, 2, 1, 0]) (day: localDate(ago(i)), n: cnt(i))];
  var streak = 0;
  for (var i = cnt(0) > 0 ? 0 : 1; cnt(i) > 0; i++) {
    streak++;
  }
  return ReadStats(today: cnt(0), week: week, total: all.length, recent: recent.reversed.take(30).toList(), days7: days7, streak: streak);
}

ReadStats readStats() => readStatsOf(readLogData());

// --- Свой план: главы поровну по дням (по числу стихов) --------------------------------------------

/// chapters — [(«Книга.Глава», число стихов)] по порядку
List<List<String>> splitChapters(List<({String ref, int n})> chapters, int days) {
  final total = chapters.fold<int>(0, (a, c) => a + c.n);
  if (total == 0 || days < 1) return [];
  final per = total / days;
  final readings = List.generate(days, (_) => <String>[]);
  var acc = 0;
  for (final c in chapters) {
    final day = math.min(days - 1, ((acc + c.n / 2) / per).floor());
    readings[day].add(c.ref);
    acc += c.n;
  }
  return readings.where((r) => r.isNotEmpty).toList();
}

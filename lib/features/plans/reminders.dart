// Напоминания о плане чтения (src/core/reminders.js): локальные уведомления, без сервера. Напоминаний сколько угодно:
// каждое — в своё время или промежутком («с 8:00 до 20:00 каждые 2 ч»), в выбранные дни недели. На 14 дней вперёд
// (не больше _max уведомлений) — с отрывками дня («Вся Библия за 70 дн.: Суд 7–21»); при каждом запуске и изменении
// планов расписание пересобирается. Нажатие на уведомление открывает планы.
// Хранится тем же форматом, что в веб-версии: { on, time, list: [{ id, time, every, until, days }] }; every — минуты
// (0 — один раз), days — дни недели 1…7 (пн…вс; пусто — каждый день); time — время первого (для прежних версий).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'plan_logic.dart';

/// Уведомления есть только в приложении (телефон)
bool get remindersSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

const _key = 'planReminder';
const _baseId = 7000;
const _days = 14;
const _max = 200; // будильников у приложения в Android не больше 500 — с запасом

/// Повтор: минуты; 0 — один раз
const reminderRepeats = [0, 30, 60, 120, 180, 240, 360];

/// «Каждые 2 ч», «Каждый час», «Один раз»
String repeatLabel(int n) => n == 0
    ? t('Один раз')
    : n < 60
        ? t('Каждые {n} мин', {'n': '$n'})
        : n == 60
            ? t('Каждый час')
            : t('Каждые {n} ч', {'n': '${n ~/ 60}'});

/// Одно напоминание: время (или промежуток time…until с шагом every минут) и дни недели (пусто — каждый день)
class ReminderItem {
  const ReminderItem({required this.id, this.time = '08:00', this.every = 0, this.until = '20:00', this.days = const []});
  final String id, time, until;
  final int every;
  final List<int> days;

  factory ReminderItem.fresh(String time) => ReminderItem(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), time: time);
  factory ReminderItem.fromJson(Map j) => ReminderItem(
        id: '${j['id'] ?? 'r1'}',
        time: (j['time'] as String?) ?? '08:00',
        every: (j['every'] as num?)?.toInt() ?? 0,
        until: (j['until'] as String?) ?? '20:00',
        days: [for (final d in (j['days'] as List? ?? const [])) (d as num).toInt()],
      );
  Map<String, dynamic> toJson() => {'id': id, 'time': time, 'every': every, 'until': until, 'days': days};
  ReminderItem copyWith({String? time, int? every, String? until, List<int>? days}) =>
      ReminderItem(id: id, time: time ?? this.time, every: every ?? this.every, until: until ?? this.until, days: days ?? this.days);

  static int _mins(String hm) {
    final p = hm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  /// Минуты дня, когда звенит: одно время или промежуток с шагом
  List<int> get times {
    final a = _mins(time);
    if (every <= 0) return [a];
    final z = _mins(until);
    return [for (var m = a; m <= (z > a ? z : a) && (m - a) ~/ every < 48; m += every) m];
  }
}

class Reminder {
  const Reminder({this.on = false, this.list = const [ReminderItem(id: 'r1')]});
  final bool on;
  final List<ReminderItem> list;
  String get time => list.isEmpty ? '08:00' : list.first.time;
}

/// Прежний формат ({ on, time }) — одно напоминание в это время
Reminder getReminder() {
  try {
    final raw = prefs.getString(_key);
    if (raw != null) {
      final j = jsonDecode(raw) as Map;
      final list = [for (final x in (j['list'] as List? ?? const [])) ReminderItem.fromJson(x as Map)];
      return Reminder(on: j['on'] == true, list: list.isNotEmpty ? list : [ReminderItem(id: 'r1', time: (j['time'] as String?) ?? '08:00')]);
    }
  } catch (_) {}
  return const Reminder();
}

void _saveReminder(Reminder r) => prefs.setString(_key, jsonEncode({'on': r.on, 'time': r.time, 'list': [for (final x in r.list) x.toJson()]}));

/// День плана на дату; null — план ещё не начался или уже кончился
int? planDayOn(Plan p, DateTime date) {
  final total = readingsOf(p).length;
  final int i;
  if (p['calendar'] == true) {
    i = calendarIndex(date);
  } else {
    final s = '${p['start'] ?? ''}';
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    final start = m != null ? DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)) : (DateTime.tryParse(s) ?? DateTime.now());
    i = (DateTime(date.year, date.month, date.day).difference(DateTime(start.year, start.month, start.day)).inHours / 24).round();
  }
  return i >= 0 && i < total ? i : null;
}

/// Что и когда показать: [(номер, время, текст)] на ближайшие 14 дней — все моменты всех напоминаний по порядку
List<({int id, DateTime at, String body})> reminderSchedule(List<Plan> plans, List<ReminderItem> items, DateTime now) {
  final out = <({int id, DateTime at, String body})>[];
  for (var k = 0; k < _days && out.length < _max; k++) {
    final day = DateTime(now.year, now.month, now.day + k);
    final times = {for (final x in items) if (x.days.isEmpty || x.days.contains(day.weekday)) ...x.times}.toList()..sort();
    final ats = [for (final m in times) DateTime(day.year, day.month, day.day, m ~/ 60, m % 60)].where((at) => at.millisecondsSinceEpoch >= now.millisecondsSinceEpoch + 60000).toList();
    if (ats.isEmpty) continue;
    final lines = <String>[];
    for (final p in plans) {
      final d = planDayOn(p, day);
      if (d == null || dayDone(p, d)) continue;
      final labels = [for (final r in readingsOf(p)[d]) readingLabel(r)];
      if (labels.isNotEmpty) lines.add('${t('${p['name']}')}: ${labels.join(', ')}');
    }
    if (lines.isEmpty) continue;
    for (final at in ats) {
      if (out.length >= _max) break;
      out.add((id: _baseId + out.length, at: at, body: lines.join('\n')));
    }
  }
  return out;
}

final _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;
Future<void> _busy = Future.value();
void Function()? _open;

Future<void> _init() async {
  if (_ready) return;
  await _plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_aob'), iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)),
    onDidReceiveNotificationResponse: (r) {
      if (r.payload == 'plans') _open?.call();
    },
  );
  _ready = true;
}

/// Пересобрать расписание (вызывать при запуске и после любого изменения планов или настроек напоминания)
Future<void> scheduleReminders() {
  if (!remindersSupported) return Future.value();
  return _busy = _busy.then((_) => _schedule(), onError: (_) => _schedule());
}

Future<void> _schedule() async {
  try {
    await _init();
    for (var k = 0; k < _max; k++) {
      await _plugin.cancel(id: _baseId + k);
    }
    final r = getReminder();
    final plans = loadPlans();
    if (!r.on || plans.isEmpty) return;
    final title = t('Чтение на сегодня');
    for (final n in reminderSchedule(plans, r.list, DateTime.now())) {
      await _plugin.zonedSchedule(
        id: n.id,
        // Одноразовые уведомления на точный момент: UTC-представление того же мгновения, пояс устройства не нужен
        scheduledDate: tz.TZDateTime.from(n.at, tz.UTC),
        title: title,
        body: n.body,
        payload: 'plans',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails('plan_reminder', t('Напоминание о чтении'), importance: Importance.defaultImportance, priority: Priority.defaultPriority, icon: 'ic_stat_aob', styleInformation: BigTextStyleInformation(n.body)),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    }
  } catch (e) {
    debugPrint('Напоминания: $e');
  }
}

/// Включить или выключить; при включении спрашиваем разрешение (Android 13+). false — разрешения не дали
Future<bool> setReminder({bool? on, List<ReminderItem>? list}) async {
  final cur = getReminder();
  final next = Reminder(on: on ?? cur.on, list: list ?? cur.list);
  if (next.on && remindersSupported) {
    try {
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final ok = android != null ? await android.requestNotificationsPermission() : await ios?.requestPermissions(alert: true, badge: true, sound: true);
      if (ok != true) return false;
    } catch (_) {
      return false;
    }
  }
  _saveReminder(next);
  await scheduleReminders();
  return true;
}

/// Запуск приложения: пересобрать расписание и слушать нажатия на уведомление (openPlans открывает окно планов)
Future<void> startReminders(void Function() openPlans) async {
  if (!remindersSupported) return;
  _open = openPlans;
  try {
    await _init();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch?.notificationResponse?.payload == 'plans') openPlans();
  } catch (_) {}
  await scheduleReminders();
}

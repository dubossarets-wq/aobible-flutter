// Напоминание о плане чтения (src/core/reminders.js): локальные уведомления в выбранное время, без сервера.
// На 14 дней вперёд — с отрывками дня («Вся Библия за 70 дн.: Суд 7–21»); при каждом запуске и изменении планов
// расписание пересобирается. Нажатие на уведомление открывает планы.
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

class Reminder {
  const Reminder({this.on = false, this.time = '08:00'});
  final bool on;
  final String time;
}

Reminder getReminder() {
  try {
    final raw = prefs.getString(_key);
    if (raw != null) {
      final j = jsonDecode(raw) as Map;
      return Reminder(on: j['on'] == true, time: (j['time'] as String?) ?? '08:00');
    }
  } catch (_) {}
  return const Reminder();
}

void _saveReminder(Reminder r) => prefs.setString(_key, jsonEncode({'on': r.on, 'time': r.time}));

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

/// Что и когда показать: [(номер, время, текст)] на ближайшие 14 дней
List<({int id, DateTime at, String body})> reminderSchedule(List<Plan> plans, String time, DateTime now) {
  final hm = time.split(':').map((s) => int.tryParse(s) ?? 0).toList();
  final out = <({int id, DateTime at, String body})>[];
  for (var k = 0; k < _days; k++) {
    final at = DateTime(now.year, now.month, now.day + k, hm[0], hm.length > 1 ? hm[1] : 0);
    if (at.millisecondsSinceEpoch < now.millisecondsSinceEpoch + 60000) continue;
    final lines = <String>[];
    for (final p in plans) {
      final d = planDayOn(p, at);
      if (d == null || dayDone(p, d)) continue;
      final labels = [for (final r in readingsOf(p)[d]) readingLabel(r)];
      if (labels.isNotEmpty) lines.add('${t('${p['name']}')}: ${labels.join(', ')}');
    }
    if (lines.isNotEmpty) out.add((id: _baseId + k, at: at, body: lines.join('\n')));
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
    for (var k = 0; k < _days; k++) {
      await _plugin.cancel(id: _baseId + k);
    }
    final r = getReminder();
    final plans = loadPlans();
    if (!r.on || plans.isEmpty) return;
    final title = t('Чтение на сегодня');
    for (final n in reminderSchedule(plans, r.time, DateTime.now())) {
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
Future<bool> setReminder({bool? on, String? time}) async {
  final cur = getReminder();
  final next = Reminder(on: on ?? cur.on, time: time ?? cur.time);
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

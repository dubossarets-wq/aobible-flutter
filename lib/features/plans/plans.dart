// Функция «Планы»: вкладка «Планы» (Hub.openPlans), «Стих дня», учёт прочитанного, напоминание, виджет на главный экран.
// Подключение к оболочке — только через Hub (см. lib/features/hub.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'loc.dart';
import 'plan_logic.dart';
import 'plan_mode.dart';
import 'plan_store.dart';
import 'plan_view.dart';
import 'plans_sheet.dart';
import 'reminders.dart';
import 'ui_kit.dart';
import 'verse_image.dart';
import 'verse_widget.dart';

void register() {
  Hub.onChapterRead = planChapterRead;
  Hub.openPlans = (context, ref, pane) => showPage(context, (_) => PlansSheet(pane: pane), tab: 'plans');
  Hub.openVerseImage = (context, ref, refs, moduleId) => showPage(context, (_) => VerseImageSheet(refs: refs, moduleId: moduleId));
  Hub.planView = (context, ref, pane) => PlanHost(pane: pane);
  Hub.afterStart.add(_afterStart);
}

Future<void> _afterStart(WidgetRef ref) async {
  watchPlanLeaving(ProviderScope.containerOf(ref.context, listen: false));
  await ensureDict();
  // Напоминание: пересобрать расписание; нажатие на уведомление открывает планы
  await startReminders(() {
    final c = ref.context;
    if (c.mounted) Hub.openPlans?.call(c, ref, 0);
  });
  final panes = ref.read(panesProvider);
  await updateWidget(panes.isEmpty ? null : panes.first.moduleId, ref.read(settingsProvider).get<String>('primaryModule'));
}

/// Обработчик «глава дочитана». Читалка вызывает его, когда последний стих главы показан и на главе проведено
/// не меньше minSeconds(число стихов) секунд (так делает ChapterView.jsx веб-версии). Глава пишется в историю
/// чтения и засчитывается в активные планы; человеку показывается сообщение.
void planChapterRead(BuildContext context, WidgetRef ref, String book, int chapter) {
  logChapter(book, chapter);
  final r = ref.read(plansProvider.notifier).creditChapter(book, chapter);
  if (r.credited.isEmpty) return;
  scheduleReminders(); // сегодняшний день мог закрыться — напоминание на него не нужно
  if (!context.mounted) return;
  if (r.finished.isNotEmpty) {
    toast(context, t('План «{plan}»: на сегодня всё ✓', {'plan': t(r.finished.first)}));
  } else {
    toast(context, t('Засчитано в план «{plan}»: {ref}', {'plan': t(r.credited.first), 'ref': Books.instance.formatRef(book, chapter, 1).replaceFirst(RegExp(r':1$'), '')}));
  }
}

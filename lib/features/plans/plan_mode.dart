// Режим «план на день» в панели (App.jsx: openPlanDay, exitPlan, returnToPlan, leavePlan, dismissPlanReturn).
// Сам факт режима хранит ядро (planMode / setPlanMode в panes.dart); здесь — куда прокрутить при открытии,
// «Вернуться к плану» после чтения вне плана и выход из плана при любом переходе в панели.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/panes.dart';

/// План, из которого человек ушёл читать дальше: к чему вернуться (at — номер отрывка, ref — стих)
class LastPlan {
  const LastPlan(this.uid, this.day, {this.at, this.ref});
  final String uid;
  final int day;
  final int? at;
  final VerseRef? ref;
}

/// Кнопка «К плану · N из M» (по панелям)
final lastPlans = ValueNotifier<Map<int, LastPlan>>({});

/// Где открыть страницу плана: отрывок at (0 — с начала) или стих ref; null/null — на последнем месте чтения
final planStart = <int, ({int? at, VerseRef? ref})>{};

/// Номер открытия страницы плана (новое открытие — новое состояние страницы и прокрутка к месту)
final planOpenStamp = <int, int>{};

/// Переход «вне плана» с возвратом к отрывку at
final planReturnAt = <int, int>{};

void _setLast(int pane, LastPlan? v) {
  final m = {...lastPlans.value};
  if (v == null) {
    m.remove(pane);
  } else {
    m[pane] = v;
  }
  lastPlans.value = m;
}

/// Открыть день плана одной страницей; at — номер отрывка, к которому прокрутить
void openPlanDay(int pane, String uid, int day, {int at = 0}) {
  planStart[pane] = (at: at, ref: null);
  planOpenStamp[pane] = (planOpenStamp[pane] ?? 0) + 1;
  _setLast(pane, null);
  setPlanMode(pane, (uid: uid, day: day));
}

/// Выйти из плана: остаёмся на том же месте в обычном чтении
void exitPlan(int pane) {
  _setLast(pane, null);
  setPlanMode(pane, null);
}

void returnToPlan(int pane) {
  final lp = lastPlans.value[pane];
  if (lp == null) return;
  planStart[pane] = (at: lp.at, ref: lp.ref);
  planOpenStamp[pane] = (planOpenStamp[pane] ?? 0) + 1;
  _setLast(pane, null);
  setPlanMode(pane, (uid: lp.uid, day: lp.day));
}

void dismissPlanReturn(int pane) => _setLast(pane, null);

ProviderContainer? _watched;

/// Любой переход в панели (поиск, «Перейти», закладка, история) выводит из плана; план запоминается для возврата.
/// Смена перевода из плана не выводит — страница просто показывает тот же день другим переводом.
void watchPlanLeaving(ProviderContainer c) {
  if (identical(_watched, c)) return;
  _watched = c;
  c.listen(panesProvider, (prev, next) {
    if (prev == null) return;
    for (final pane in planMode.value.keys.toList()) {
      if (pane >= next.length || pane >= prev.length) continue;
      final p = prev[pane], n = next[pane];
      if (n.nav == p.nav || n.moduleId != p.moduleId) continue;
      final mode = planMode.value[pane]!;
      final at = planReturnAt.remove(pane);
      _setLast(pane, LastPlan(mode.uid, mode.day, at: at, ref: at == null ? p.ref : null));
      setPlanMode(pane, null);
    }
  });
}

// Кнопка «К плану · N из M» (PlanReturn в BibleReader.jsx): человек ушёл из плана читать дальше — она возвращает на страницу плана.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import 'plan_logic.dart';
import 'plan_mode.dart';
import 'plan_store.dart';
import 'ui_kit.dart';

class PlanReturnPill extends ConsumerWidget {
  const PlanReturnPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final plans = ref.watch(plansProvider);
    return ValueListenableBuilder<Map<int, LastPlan>>(
      valueListenable: lastPlans,
      builder: (context, m, _) {
        final items = <Widget>[];
        for (final e in m.entries) {
          final plan = plans.where((p) => p['uid'] == e.value.uid).firstOrNull;
          if (plan == null || dayDone(plan, e.value.day)) continue;
          final all = readingsOf(plan);
          final rs = e.value.day < all.length ? all[e.value.day] : <String>[];
          final done = rs.where((r) => readingDone(plan, e.value.day, r)).length;
          items.add(Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: pal.accent,
              shape: const StadiumBorder(),
              elevation: 6,
              clipBehavior: Clip.antiAlias,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  onTap: () => returnToPlan(e.key),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.cornerUpLeft, size: 16, color: pal.onAccent),
                      const SizedBox(width: 7),
                      Text(t('К плану · {done} из {total}', {'done': '$done', 'total': '${rs.length}'}), style: TextStyle(fontSize: 14.7, fontWeight: FontWeight.w600, color: pal.onAccent)),
                    ]),
                  ),
                ),
                Tooltip(
                  message: t('Скрыть кнопку возврата к плану'),
                  child: InkWell(
                    onTap: () => dismissPlanReturn(e.key),
                    child: Padding(padding: const EdgeInsets.fromLTRB(6, 10, 12, 10), child: Icon(LucideIcons.x, size: 15, color: pal.onAccent.withValues(alpha: 0.8))),
                  ),
                ),
              ]),
            ),
          ));
        }
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(mainAxisSize: MainAxisSize.min, children: items);
      },
    );
  }
}

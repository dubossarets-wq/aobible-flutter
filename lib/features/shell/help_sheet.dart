// Инструкция (HelpSheet.jsx): список уроков с поиском. В веб-версии урок подсвечивает нужные места на экране;
// здесь урок открывается списком шагов (подсветка элементов — отдельная работа).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'colors.dart';
import 'help_data.dart';
import 'plural.dart';
import 'sheet.dart';

Future<void> openHelp(BuildContext context) => showAppSheet(context, (_) => const HelpSheet());

class HelpSheet extends ConsumerStatefulWidget {
  const HelpSheet({super.key});
  @override
  ConsumerState<HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends ConsumerState<HelpSheet> {
  String _q = '';
  Tour? _tour;

  @override
  Widget build(BuildContext context) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    final tour = _tour;
    if (tour != null) {
      return AppSheet(
        title: t(tour.title),
        full: true,
        onBack: () => setState(() => _tour = null),
        children: [
          for (var i = 0; i < tour.steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 13, backgroundColor: pal.accent, child: Text('${i + 1}', style: TextStyle(color: pal.onAccent, fontWeight: FontWeight.w800, fontSize: 13))),
                const SizedBox(width: 12),
                Expanded(child: Text(t(tour.steps[i]), style: const TextStyle(fontSize: 16, height: 1.4))),
              ]),
            ),
        ],
      );
    }
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? tours : tours.where((x) => ('${t(x.title)} ${x.steps.map(t).join(' ')}').toLowerCase().contains(q)).toList();
    final groups = {for (final x in list) x.group};
    return AppSheet(
      title: t('Инструкция'),
      full: true,
      fixed: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('Например: проповедь, слушать, шрифт'), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
      children: [
        Padding(padding: const EdgeInsets.all(6), child: Row(children: [Icon(Icons.touch_app_outlined, size: 18, color: pal.muted), const SizedBox(width: 8), Expanded(child: Text(t('Выберите тему — покажем, куда нажимать.'), style: TextStyle(color: pal.muted)))])),
        for (final g in groups) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 2), child: Text(t(g), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.muted))),
          for (final x in list.where((x) => x.group == g))
            PrefRow(icon: x.icon, title: t(x.title), sub: plural('{n} шаг|{n} шага|{n} шагов', x.steps.length), onTap: () => setState(() => _tour = x)),
        ],
        if (list.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(t('Ничего не нашлось. Попробуйте другое слово.'), style: TextStyle(color: pal.muted))),
      ],
    );
  }
}

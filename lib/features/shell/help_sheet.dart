// Инструкция (HelpSheet.jsx): список уроков с поиском. В веб-версии урок подсвечивает нужные места на экране;
// здесь урок открывается списком шагов (подсветка элементов — отдельная работа).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
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
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    final tour = _tour;
    if (tour != null) {
      return AppSheet(
        title: t(tour.title),
        onBack: () => setState(() => _tour = null),
        gap: 0,
        children: [
          for (var i = 0; i < tour.steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
                  child: Text('${i + 1}', style: TextStyle(color: pal.onAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(t(tour.steps[i]), style: TextStyle(fontSize: 15, height: 1.45, color: pal.text)))),
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
      children: [
        // .help-intro: значок руки цвета акцента и подсказка
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.hand, size: 18, color: pal.accent)),
          const SizedBox(width: 8),
          Expanded(child: Text(t('Выберите тему — покажем, куда нажимать.'), style: TextStyle(fontSize: 14.25, height: 1.45, color: pal.text))),
        ]),
        AobInput(controller: _search, icon: null, hint: t('Например: проповедь, слушать, шрифт'), onChanged: (v) => setState(() => _q = v)),
        // .nav-group: заголовок h4 (бледный) и список строк-переходов
        for (final g in groups)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text(t(g), style: TextStyle(fontSize: 13.76, fontWeight: FontWeight.w600, color: pal.muted))),
            for (final (i, x) in list.where((x) => x.group == g).indexed.toList())
              PrefRow(icon: x.icon, title: t(x.title), sub: plural('{n} шаг|{n} шага|{n} шагов', x.steps.length), onTap: () => setState(() => _tour = x), last: i == list.where((y) => y.group == g).length - 1),
          ]),
        if (list.isEmpty) Text(t('Ничего не нашлось. Попробуйте другое слово.'), style: TextStyle(fontSize: 14.7, height: 1.5, color: pal.muted)),
      ],
    );
  }
}

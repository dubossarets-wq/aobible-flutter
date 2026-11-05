// Инструкция (HelpSheet.jsx): список уроков с поиском. Нажатие на урок закрывает окно и показывает прямо в приложении,
// куда нажимать: нужное место подсвечено, остальной экран затемнён, внизу — шаги (tour.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'colors.dart';
import 'plural.dart';
import 'sheet.dart';
import 'tour.dart';
import '../../ui/ios_style.dart';

Future<void> openHelp(BuildContext context) => showAppSheet(context, (_) => const HelpSheet());

class HelpSheet extends ConsumerStatefulWidget {
  const HelpSheet({super.key});
  @override
  ConsumerState<HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends ConsumerState<HelpSheet> {
  String _q = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _start(String id) {
    Navigator.of(context).maybePop();
    Timer(const Duration(milliseconds: 200), () => startTour(id));
  }

  @override
  Widget build(BuildContext context) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    final phone = phoneLayout();
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? tourDefs : tourDefs.where((x) => ('${t(x.title)} ${x.steps(phone).map((s) => t(s.text)).join(' ')}').toLowerCase().contains(q)).toList();
    final groups = {for (final x in list) x.group};
    return AppSheet(
      title: t('Инструкция'),
      children: [
        // .help-intro: значок руки цвета акцента и подсказка
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(ico(LucideIcons.hand), size: 18, color: pal.accent)),
          const SizedBox(width: 8),
          Expanded(child: Text(t('Выберите тему — покажем, куда нажимать.'), style: TextStyle(fontSize: 14.25, height: 1.45, color: pal.text))),
        ]),
        AobInput(controller: _search, icon: null, hint: t('Например: проповедь, слушать, шрифт'), onChanged: (v) => setState(() => _q = v)),
        // стиль iPhone: группа — системный заголовок и строки одной карточкой (как «Настройки» iPhone)
        if (iosUiNow)
          for (final g in groups) ...[
            GroupTitle(t(g)),
            for (final (i, x) in list.where((x) => x.group == g).indexed.toList())
              PrefRow(
                icon: x.icon,
                title: t(x.title),
                sub: plural('{n} шаг|{n} шага|{n} шагов', x.steps(phone).length),
                onTap: () => _start(x.id),
                last: i == list.where((y) => y.group == g).length - 1,
              ),
            const IosBreak(),
          ]
        else
        // .nav-group: заголовок h4 (бледный) и список строк-переходов
        for (final g in groups)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text(t(g), style: TextStyle(fontSize: 13.76, fontWeight: FontWeight.w600, color: pal.muted))),
            for (final (i, x) in list.where((x) => x.group == g).indexed.toList())
              PrefRow(
                icon: x.icon,
                title: t(x.title),
                sub: plural('{n} шаг|{n} шага|{n} шагов', x.steps(phone).length),
                onTap: () => _start(x.id),
                last: i == list.where((y) => y.group == g).length - 1,
              ),
          ]),
        if (list.isEmpty) Text(t('Ничего не нашлось. Попробуйте другое слово.'), style: TextStyle(fontSize: 14.7, height: 1.5, color: pal.muted)),
      ],
    );
  }
}

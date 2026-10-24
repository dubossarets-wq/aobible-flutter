// Меню «Ещё» (MoreSheet.jsx, moreItems.jsx): пункты других функций (Hub.moreItems — закладка, проповеди, «Слушать»…)
// плюс свои: переключатели из меню, Оформление, Настройки, Инструкция, Сообщить о проблеме, Что нового, О приложении.
// Действие закрывает лист; переключатели («Режим чтения» и т. п.) — нет. Окна оболочки открываются поверх «Ещё»,
// крестик возвращает обратно.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'about_sheet.dart';
import 'appearance_sheet.dart';
import 'colors.dart';
import 'fonts.dart';
import 'help_sheet.dart';
import 'news_sheet.dart';
import 'prefs_sheet.dart';
import 'report.dart';
import 'sheet.dart';

void openMore(BuildContext context, WidgetRef ref, int pane) => showAppSheet(context, (_) => MoreSheet(opener: context, pane: pane));

class _Entry {
  const _Entry({required this.icon, required this.label, required this.run, this.extra, this.keep = false, this.order = 100});
  final IconData icon;
  final String label;
  final String? extra;
  final bool keep; // лист не закрывается
  final int order;
  final void Function(BuildContext sheet, WidgetRef ref) run;
}

class MoreSheet extends ConsumerWidget {
  const MoreSheet({super.key, required this.opener, required this.pane});
  final BuildContext opener; // откуда открыли: после закрытия листа действия других функций идут от него
  final int pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final pal = effectivePalette(s);
    final split = ref.watch(panesProvider.select((l) => l.length > 1));
    String onOff(bool v) => v ? t('вкл') : t('выкл');
    final rows = s.get<String>('splitLayout') == 'rows';

    final entries = <_Entry>[
      // Пункты других функций
      for (final it in Hub.moreItems)
        if (it.visible == null || it.visible!(ref))
          _Entry(
            icon: it.icon,
            label: it.label,
            order: it.order,
            run: (sheet, r) {
              Navigator.of(sheet).pop();
              it.run(opener, r, pane);
            },
          ),
      // Переключатели, которые человек сам вынес в меню (Настройки → «Меню «Ещё»»)
      if (menuFlag(s, 'focus'))
        _Entry(icon: s.get<bool>('focusMode') ? Icons.visibility_off_outlined : Icons.visibility_outlined, label: t('Режим чтения'), extra: onOff(s.get<bool>('focusMode')), keep: true, order: 500, run: (_, r) => r.read(settingsProvider.notifier).set({'focusMode': !s.get<bool>('focusMode')})),
      if (menuFlag(s, 'book'))
        _Entry(icon: Icons.auto_stories_outlined, label: t('Как книга'), extra: onOff(s.get<bool>('bookMode')), keep: true, order: 510, run: (_, r) => r.read(settingsProvider.notifier).set({'bookMode': !s.get<bool>('bookMode'), 'continuousVerses': false})),
      if (menuFlag(s, 'split') && split) ...[
        _Entry(icon: Icons.link, label: t('Синхронная прокрутка'), extra: onOff(s.get<bool>('syncScroll')), keep: true, order: 520, run: (_, r) => r.read(settingsProvider.notifier).set({'syncScroll': !s.get<bool>('syncScroll')})),
        _Entry(icon: rows ? Icons.view_column_outlined : Icons.view_agenda_outlined, label: rows ? t('Панели рядом') : t('Панели друг над другом'), keep: true, order: 530, run: (_, r) => r.read(settingsProvider.notifier).set({'splitLayout': rows ? 'columns' : 'rows'})),
      ],
      // Свои пункты — после остальных, отдельной группой
      _Entry(icon: Icons.palette_outlined, label: t('Оформление'), keep: true, order: 900, run: (c, r) => openAppearance(c)),
      _Entry(icon: Icons.settings_outlined, label: t('Настройки'), keep: true, order: 910, run: (c, r) => openPrefs(c)),
      if (menuFlag(s, 'help')) _Entry(icon: Icons.menu_book_outlined, label: t('Инструкция'), keep: true, order: 920, run: (c, r) => openHelp(c)),
      // Письмо разработчику: версия, устройство и последние ошибки — человек видит текст и отправляет сам
      if (menuFlag(s, 'help')) _Entry(icon: Icons.report_gmailerrorred_outlined, label: t('Сообщить о проблеме'), keep: true, order: 930, run: (c, r) => reportProblem(c)),
      _Entry(icon: Icons.auto_awesome_outlined, label: t('Что нового'), keep: true, order: 940, run: (c, r) => openNews(c)),
      _Entry(icon: Icons.info_outline, label: t('О приложении'), keep: true, order: 950, run: (c, r) => openAbout(c)),
    ];
    // Равные порядки — как добавлены (sort в Dart не гарантирует устойчивость, поэтому сравниваем и номер)
    final sorted = [for (var i = 0; i < entries.length; i++) (i, entries[i])]..sort((a, b) => a.$2.order != b.$2.order ? a.$2.order.compareTo(b.$2.order) : a.$1.compareTo(b.$1));

    final children = <Widget>[];
    var sep = false;
    for (final (_, e) in sorted) {
      if (!sep && e.order >= 900 && children.isNotEmpty) {
        children.add(Divider(height: 14, color: pal.line));
        sep = true;
      }
      children.add(PrefRow(
        icon: e.icon,
        title: e.label,
        chevron: false,
        extra: e.extra == null ? null : Text(e.extra!, style: TextStyle(color: pal.muted, fontSize: 14)),
        onTap: () => e.run(context, ref),
      ));
    }
    return AppSheet(title: t('Ещё'), children: children);
  }
}

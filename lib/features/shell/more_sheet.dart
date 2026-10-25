// Меню «Ещё» (MoreSheet.jsx, moreItems.jsx): пункты других функций (Hub.moreItems — закладка, проповеди, «Слушать»…)
// плюс свои: переключатели из меню, Оформление, Настройки, Инструкция, Сообщить о проблеме, Что нового, О приложении.
// Действие закрывает лист; переключатели («Режим чтения» и т. п.) — нет. Окна оболочки открываются поверх «Ещё»,
// крестик возвращает обратно.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
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
            // «Ещё» остаётся под открытым окном: в нём стрелка «назад» вернёт сюда. Пункт ничего не открыл
            // (переключатель, карта во второй половине) — «Ещё» закрывается само
            run: (sheet, r) {
              final route = ModalRoute.of(sheet);
              it.run(sheet, r, pane);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (route != null && route.isCurrent) Navigator.of(sheet).pop();
              });
            },
          ),
      // Переключатели, которые человек сам вынес в меню (Настройки → «Меню «Ещё»»)
      if (menuFlag(s, 'focus'))
        _Entry(icon: s.get<bool>('focusMode') ? LucideIcons.eyeOff : LucideIcons.eye, label: t('Режим чтения'), extra: onOff(s.get<bool>('focusMode')), keep: true, order: 500, run: (_, r) => r.read(settingsProvider.notifier).set({'focusMode': !s.get<bool>('focusMode')})),
      if (menuFlag(s, 'book'))
        _Entry(icon: LucideIcons.bookOpenText, label: t('Как книга'), extra: onOff(s.get<bool>('bookMode')), keep: true, order: 510, run: (_, r) => r.read(settingsProvider.notifier).set({'bookMode': !s.get<bool>('bookMode'), 'continuousVerses': false})),
      if (menuFlag(s, 'split') && split) ...[
        _Entry(icon: LucideIcons.link, label: t('Синхронная прокрутка'), extra: onOff(s.get<bool>('syncScroll')), keep: true, order: 520, run: (_, r) => r.read(settingsProvider.notifier).set({'syncScroll': !s.get<bool>('syncScroll')})),
        _Entry(icon: rows ? LucideIcons.columns2 : LucideIcons.rows2, label: rows ? t('Панели рядом') : t('Панели друг над другом'), keep: true, order: 530, run: (_, r) => r.read(settingsProvider.notifier).set({'splitLayout': rows ? 'columns' : 'rows'})),
      ],
      // Свои пункты — после остальных, отдельной группой
      _Entry(icon: LucideIcons.palette, label: t('Оформление'), keep: true, order: 900, run: (c, r) => openAppearance(c)),
      _Entry(icon: LucideIcons.settings, label: t('Настройки'), keep: true, order: 910, run: (c, r) => openPrefs(c)),
      if (menuFlag(s, 'help')) _Entry(icon: LucideIcons.bookOpenCheck, label: t('Инструкция'), keep: true, order: 920, run: (c, r) => openHelp(c)),
      // Письмо разработчику: версия, устройство и последние ошибки — человек видит текст и отправляет сам
      if (menuFlag(s, 'help')) _Entry(icon: LucideIcons.messageSquareWarning, label: t('Сообщить о проблеме'), keep: true, order: 930, run: (c, r) => reportProblem(c)),
      _Entry(icon: LucideIcons.sparkles, label: t('Что нового'), keep: true, order: 940, run: (c, r) => openNews(c)),
      _Entry(icon: LucideIcons.info, label: t('О приложении'), keep: true, order: 950, run: (c, r) => openAbout(c)),
    ];
    // Равные порядки — как добавлены (sort в Dart не гарантирует устойчивость, поэтому сравниваем и номер)
    final sorted = [for (var i = 0; i < entries.length; i++) (i, entries[i])]..sort((a, b) => a.$2.order != b.$2.order ? a.$2.order.compareTo(b.$2.order) : a.$1.compareTo(b.$1));

    final children = <Widget>[];
    var sepOther = false, sepOwn = false;
    for (final (_, e) in sorted) {
      // Линии между группами (как menu-sep в moreItems.jsx): перед переключателями и перед своими пунктами
      if (!sepOther && e.keep && e.order >= 500 && e.order < 900 && children.isNotEmpty) {
        children.add(const MenuSep());
        sepOther = true;
      }
      if (!sepOwn && e.order >= 900 && children.isNotEmpty) {
        children.add(const MenuSep());
        sepOwn = true;
      }
      // .more-list .menu-item: отступы 12 сверху и снизу (в MenuRow — 10, остальное добавляет Padding)
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MenuRow(
          icon: e.icon,
          label: e.label,
          extra: e.extra == null ? null : Text(e.extra!, style: TextStyle(color: pal.muted, fontSize: 13.4)),
          onTap: () => e.run(context, ref),
        ),
      ));
    }
    // .more-list: поля -4 / -6, поэтому значки стоят ближе к краю, чем заголовок
    return AppSheet(title: t('Ещё'), padding: const EdgeInsets.fromLTRB(10, 8, 10, 20), gap: 0, children: children);
  }
}

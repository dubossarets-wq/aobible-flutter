// Меню «Ещё» (MoreSheet.jsx, moreItems.jsx): пункты других функций (Hub.moreItems — закладка, проповеди, «Слушать»…)
// плюс свои: переключатели из меню, Оформление, Настройки, Инструкция, Сообщить о проблеме, Что нового, О приложении.
// Действие закрывает лист; переключатели («Режим чтения» и т. п.) — нет. Окна оболочки открываются поверх «Ещё»,
// крестик возвращает обратно.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart' show verseAt;
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/ios_style.dart';
import '../../ui/kit.dart';
import '../bookmarks/marks.dart' show marksProvider;
import '../hub.dart';
import 'about_sheet.dart';
import 'appearance_sheet.dart';
import 'colors.dart';
import 'fonts.dart';
import 'help_sheet.dart';
import 'library_sheet.dart' show openLibrary;
import 'news_sheet.dart';
import 'prefs_sheet.dart';
import 'report.dart';
import 'sheet.dart';

void openMore(BuildContext context, WidgetRef ref, int pane) => showAppSheet(context, (_) => MoreSheet(opener: context, pane: pane));

class _Entry {
  const _Entry({required this.icon, required this.label, required this.run, this.extra, this.sub, this.keep = false, this.order = 100});
  final IconData icon;
  final String label;
  final String? sub; // вторая строка под названием (menu-item-2)
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
    // На широком экране это выпадающее меню ⋮: «Закладки и заметки» и «Планы чтения» нет на вкладках, поэтому они здесь
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final panes = ref.watch(panesProvider);
    final idx = pane < panes.length ? pane : 0;
    final here = livePositions[idx]?.value ?? panes[idx].ref;
    final moduleId = panes[idx].moduleId;
    final marks = ref.watch(marksProvider);
    final marked = marks.isBookmarked(here);
    final last = marks.bookmarks.firstOrNull; // самая новая закладка — первая в списке
    final hasMaps = ModuleStore.instance.installed.any((m) => m.type == 'maps');
    // Что в веб-версии не входит в «Ещё» (они в «Настройках»): «Мои данные» и «Аудио»
    const notInMenu = {'mydata', 'audio'};
    // Действие закрывает «Ещё», если ничего не открыло поверх (как у пунктов других функций)
    void Function(BuildContext, WidgetRef) act(void Function(BuildContext, WidgetRef) f) => (sheet, r) {
          final route = ModalRoute.of(sheet);
          f(sheet, r);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (route != null && route.isCurrent) Navigator.of(sheet).pop();
          });
        };

    final entries = <_Entry>[
      _Entry(
        icon: marked ? LucideIcons.bookmarkCheck : LucideIcons.bookmark,
        label: marked ? t('Убрать закладку') : t('Закладка на это место'),
        order: 1,
        run: act((_, r) {
          final text = verseAt(moduleId, here) ?? '';
          r.read(marksProvider.notifier).toggleBookmark(here, marked ? '' : (text.length > 160 ? text.substring(0, 160) : text));
        }),
      ),
      if (menuFlag(s, 'lastBookmark') && last != null)
        _Entry(
          icon: LucideIcons.circlePlay,
          label: t('К последней закладке'),
          sub: '${Books.instance.meta('${last['book']}').short} ${last['chapter']}:${last['verse']}${'${last['text'] ?? ''}'.isNotEmpty ? ' · ${last['text']}' : ''}',
          order: 2,
          run: act((_, r) => r.read(panesProvider.notifier).navigate(idx, VerseRef('${last['book']}', last['chapter'] as int, last['verse'] as int))),
        ),
      if (wide && Hub.openBookmarks != null) _Entry(icon: LucideIcons.heart, label: t('Закладки и заметки'), order: 3, run: act((c, r) => Hub.openBookmarks!(opener, r, idx))),
      if (wide && menuFlag(s, 'plans') && Hub.openPlans != null) _Entry(icon: LucideIcons.calendarCheck, label: t('Планы чтения'), order: 30, run: act((c, r) => Hub.openPlans!(opener, r, idx))),
      if (menuFlag(s, 'listen') && Hub.listenFrom != null) _Entry(icon: LucideIcons.headphones, label: t('Слушать с этого места'), order: 40, run: act((c, r) => Hub.listenFrom!(opener, r, idx, here))),
      // Пункты других функций
      for (final it in Hub.moreItems)
        if (!notInMenu.contains(it.id) &&
            (it.id != 'sermons' || menuFlag(s, 'sermons')) &&
            (it.id != 'plans' || menuFlag(s, 'plans')) &&
            (it.id != 'maps' || (menuFlag(s, 'maps') && hasMaps)) &&
            (it.visible == null || it.visible!(ref)))
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
      // модули — сразу из «Ещё» (по просьбе владельца), а не только через «Настройки»
      _Entry(icon: LucideIcons.library, label: t('Библиотека модулей'), keep: true, order: 890, run: (c, r) => openLibrary(c)),
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
    // перед каким пунктом начинается новая группа — у пункта перед ним (последнего в группе) нет линии снизу
    bool startsGroup(_Entry e, bool other, bool own) => (!other && e.keep && e.order >= 500 && e.order < 900) || (!own && e.order >= 900);
    final list = [for (final (_, e) in sorted) e];
    for (final (k, e) in list.indexed) {
      final o = sepOther || (e.keep && e.order >= 500 && e.order < 900);
      final w = sepOwn || e.order >= 900;
      final lastInGroup = k == list.length - 1 || startsGroup(list[k + 1], o, w);
      // Линии между группами (как menu-sep в moreItems.jsx): перед переключателями и перед своими пунктами
      if (!sepOther && e.keep && e.order >= 500 && e.order < 900 && children.isNotEmpty) {
        children.add(const MenuSep(full: true));
        sepOther = true;
      }
      if (!sepOwn && e.order >= 900 && children.isNotEmpty) {
        children.add(const MenuSep(full: true));
        sepOwn = true;
      }
      // .more-list .menu-item: отступы 12 сверху и снизу (в MenuRow — 10, остальное добавляет Padding)
      // стиль iPhone: строки вплотную, между ними — тонкая линия (её рисует MenuRow)
      children.add(Padding(
        padding: EdgeInsets.symmetric(vertical: iosStyleOf(ref) ? 0 : 2),
        child: e.sub == null
            ? MenuRow(
                flat: true,
                last: lastInGroup,
                icon: e.icon,
                label: e.label,
                extra: e.extra == null ? null : Text(e.extra!, style: TextStyle(color: pal.muted, fontSize: 13.4)),
                onTap: () => e.run(context, ref),
              )
            : _Row2(entry: e, onTap: () => e.run(context, ref)),
      ));
    }
    // строки — от края до края окна (подсветка и линии), отступы — у содержимого строки
    return AppSheet(title: t('Ещё'), padding: const EdgeInsets.fromLTRB(0, 8, 0, 20), gap: 0, children: children);
  }
}

/// Пункт с подписью под названием (.menu-item-2): «К последней закладке» и место закладки
class _Row2 extends ConsumerWidget implements IosGroupRow {
  const _Row2({required this.entry, required this.onTap});
  final _Entry entry;
  final VoidCallback onTap;
  @override
  double get iosIndent => 60;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    final ios = iosStyleOf(ref);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: ios ? const EdgeInsets.fromLTRB(16, 9, 14, 9) : const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(children: [
            if (ios) IosIconSquare(entry.icon) else Icon(entry.icon, size: 20, color: pal.accent),
            if (ios) const SizedBox(width: 2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.label, style: TextStyle(fontSize: 15.7, color: pal.text)),
                const SizedBox(height: 1),
                Text(entry.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.1, color: pal.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

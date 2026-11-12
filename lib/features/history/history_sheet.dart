// «Ещё» → «История»: все места, где человек читал (core/reading_history.dart), по дням — «Сегодня», «Вчера», дальше
// по датам; у каждой записи время и начало стиха. Сверху выбор: всё / один день / один месяц; стрелками — соседний
// день или месяц, где что-то читалось, по названию — календарь или список месяцев. Нажатие открывает место,
// смахивание удаляет (с «Отменить»), корзина в шапке очищает показанное (с подтверждением).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart' show verseAt;
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/reading_history.dart';
import '../../ui/ios_style.dart';
import '../../ui/kit.dart';
import '../bookmarks/ui.dart' show AobListRow, EmptyState, undoToast, two;
import '../plans/loc.dart' show fmtDay, weekdayShort;
import '../plans/ui_kit.dart' show showPage;

void openHistory(BuildContext context, int pane) => showPage(context, (_) => HistorySheet(pane: pane), page: true, tab: 'more');

enum _Mode { all, day, month }

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);
DateTime _at(HistoryEntry e) => DateTime.fromMillisecondsSinceEpoch(e.time);

const _monthsRu = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const _monthsUk = ['Січень', 'Лютий', 'Березень', 'Квітень', 'Травень', 'Червень', 'Липень', 'Серпень', 'Вересень', 'Жовтень', 'Листопад', 'Грудень'];
const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _monthTitle(DateTime m) {
  final names = switch (currentLang) { 'ru' => _monthsRu, 'uk' => _monthsUk, 'en' => _monthsEn, _ => null };
  return names == null ? '${two(m.month)}.${m.year}' : '${names[m.month - 1]} ${m.year}';
}

String _dayTitle(DateTime d) {
  final today = _dayOf(DateTime.now());
  if (d == today) return t('Сегодня');
  if (d == today.subtract(const Duration(days: 1))) return t('Вчера');
  return '${weekdayShort(d.weekday)}, ${fmtDay(d, full: true, year: d.year != today.year)}';
}

class HistorySheet extends ConsumerStatefulWidget {
  const HistorySheet({super.key, required this.pane});
  final int pane;
  @override
  ConsumerState<HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends ConsumerState<HistorySheet> {
  final _log = ReadingHistory.instance;
  var _mode = _Mode.all;
  var _day = _dayOf(DateTime.now());
  var _month = _monthOf(DateTime.now());
  BuildContext? _inner; // под своим ScaffoldMessenger — для «Отменить»

  @override
  void initState() {
    super.initState();
    _log.addListener(_changed);
    final items = _log.items;
    if (items.isNotEmpty) {
      _day = _dayOf(_at(items.last));
      _month = _monthOf(_at(items.last));
    }
  }

  @override
  void dispose() {
    _log.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  int get _paneIndex {
    final n = ref.read(panesProvider).length;
    return widget.pane < n ? widget.pane : 0;
  }

  String _title(HistoryEntry e) => e.verse > 0 ? Books.instance.formatRef(e.book, e.chapter, e.verse, full: true) : '${Books.instance.meta(e.book).name} ${e.chapter}';

  String? _preview(HistoryEntry e) {
    try {
      final s = verseAt(ref.read(panesProvider)[_paneIndex].moduleId, e.ref);
      return s == null || s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  void _open(HistoryEntry e) {
    ref.read(panesProvider.notifier).navigate(_paneIndex, e.ref);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _drop(List<HistoryEntry> gone, String text) {
    if (gone.isEmpty) return;
    _log.remove(gone);
    final c = _inner;
    if (c != null && c.mounted) undoToast(c, text, () => _log.restore(gone));
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final ios = iosStyleOf(ref);
    final all = _log.items.reversed.toList(); // новые сверху
    final days = <DateTime>[];
    final months = <DateTime>[];
    for (final e in all) {
      final d = _dayOf(_at(e));
      final m = _monthOf(d);
      if (days.isEmpty || days.last != d) days.add(d);
      if (months.isEmpty || months.last != m) months.add(m);
    }
    final shown = switch (_mode) {
      _Mode.all => all,
      _Mode.day => [for (final e in all) if (_dayOf(_at(e)) == _day) e],
      _Mode.month => [for (final e in all) if (_monthOf(_at(e)) == _month) e],
    };
    // строки списка: заголовок дня (DateTime) или запись с местом в карточке дня
    final items = <Object>[];
    for (var i = 0; i < shown.length; i++) {
      final d = _dayOf(_at(shown[i]));
      final first = i == 0 || _dayOf(_at(shown[i - 1])) != d;
      final last = i == shown.length - 1 || _dayOf(_at(shown[i + 1])) != d;
      if (first) items.add(d);
      items.add((shown[i], first, last));
    }

    final prevDay = days.where((d) => d.isBefore(_day)).firstOrNull;
    final nextDay = days.where((d) => d.isAfter(_day)).lastOrNull;
    final mi = months.indexOf(_month);
    final prevMonth = mi >= 0 && mi + 1 < months.length ? months[mi + 1] : null;
    final nextMonth = mi > 0 ? months[mi - 1] : null;

    Widget stepper({required String label, DateTime? prev, DateTime? next, required ValueChanged<DateTime> go, required Widget Function(Widget) pick}) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            IconBtn(icon: LucideIcons.chevronLeft, tooltip: t('Назад'), onTap: prev == null ? null : () => go(prev)),
            Expanded(
              child: Center(
                child: pick(Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text))),
                  const SizedBox(width: 4),
                  AIcon(ico(LucideIcons.chevronDown), size: 14, color: pal.muted),
                ])),
              ),
            ),
            IconBtn(icon: LucideIcons.chevronRight, tooltip: t('Вперёд'), onTap: next == null ? null : () => go(next)),
          ]),
        );

    Future<void> pickDay() async {
      if (days.isEmpty) return;
      final set = days.toSet();
      final d = await showDatePicker(
        context: context,
        initialDate: set.contains(_day) ? _day : days.first,
        firstDate: days.last,
        lastDate: days.first,
        selectableDayPredicate: (x) => set.contains(_dayOf(x)),
      );
      if (d != null && mounted) setState(() => _day = _dayOf(d));
    }

    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Segmented<_Mode>(
          options: [(_Mode.all, t('Всё')), (_Mode.day, t('День')), (_Mode.month, t('Месяц'))],
          value: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        if (_mode == _Mode.day)
          stepper(
            label: _dayTitle(_day),
            prev: prevDay,
            next: nextDay,
            go: (d) => setState(() => _day = d),
            pick: (child) => InkWell(borderRadius: BorderRadius.circular(10), onTap: pickDay, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: child)),
          ),
        if (_mode == _Mode.month)
          stepper(
            label: _monthTitle(_month),
            prev: prevMonth,
            next: nextMonth,
            go: (m) => setState(() => _month = m),
            pick: (child) => PopupMenuButton<DateTime>(
              initialValue: _month,
              enabled: months.isNotEmpty,
              onSelected: (m) => setState(() => _month = m),
              itemBuilder: (_) => [for (final m in months) PopupMenuItem(value: m, child: Text(_monthTitle(m)))],
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: child),
            ),
          ),
      ]),
    );

    final question = switch (_mode) {
      _Mode.all => t('Очистить всю историю?'),
      _Mode.day => t('Удалить историю за {when}?', {'when': _dayTitle(_day).toLowerCase()}),
      _Mode.month => t('Удалить историю за {when}?', {'when': _monthTitle(_month).toLowerCase()}),
    };
    final headLeft = ios ? (iosEdge - 16).clamp(0.0, iosEdge) + iosHeaderLeft : 4.0;

    // Свой ScaffoldMessenger/Scaffold: уведомление «Отменить» видно поверх окна, а не под ним
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Builder(builder: (inner) {
          _inner = inner;
          return AobSheet(
            title: t('История'),
            scroll: false,
            padding: EdgeInsets.zero,
            actions: [
              if (shown.isNotEmpty)
                IconBtn(
                  icon: LucideIcons.trash2,
                  tooltip: t('Очистить историю'),
                  onTap: () => iosConfirm(
                    context,
                    action: _mode == _Mode.all ? t('Очистить историю') : t('Удалить'),
                    message: question,
                    onConfirm: () => _drop(shown, t('Удалено записей: {n}', {'n': '${shown.length}'})),
                  ),
                ),
            ],
            child: Column(children: [
              controls,
              Expanded(
                child: items.isEmpty
                    ? ListView(padding: padTabs(context, const EdgeInsets.fromLTRB(16, 12, 16, 20)), children: [
                        EmptyState(icon: LucideIcons.history, title: t('История пуста'), text: _mode == _Mode.all ? t('Здесь появятся места, которые вы читали.') : t('В этот период вы не читали.')),
                      ])
                    : ListView.builder(
                        padding: padTabs(context, const EdgeInsets.fromLTRB(16, 4, 16, 20)),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];
                          if (it is DateTime) {
                            return Padding(padding: EdgeInsets.only(left: headLeft, top: i == 0 ? 8 : 22, bottom: 6), child: GroupTitle(_dayTitle(it)));
                          }
                          final (e, first, last) = it as (HistoryEntry, bool, bool);
                          final d = _at(e);
                          return AobListRow(
                            key: ValueKey('h${e.start}|${e.book}|${e.chapter}'),
                            id: 'h${e.start}|${e.book}|${e.chapter}',
                            first: first,
                            last: last,
                            title: Text(_title(e), maxLines: 1, overflow: TextOverflow.ellipsis),
                            meta: '${two(d.hour)}:${two(d.minute)}',
                            metaRight: true,
                            text: _preview(e),
                            deleteLabel: t('Удалить'),
                            onTap: () => _open(e),
                            onDelete: () => _drop([e], t('Запись удалена')),
                          );
                        },
                      ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

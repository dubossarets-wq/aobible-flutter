// Общие кирпичики окон «Ещё», «Настройки», «Оформление», «Библиотека»…: нижний лист с заголовком и стрелкой
// «назад», строка-переход, переключатель, ползунок со ступенями, выбор из нескольких. Вид — как в веб-версии
// (BottomSheet.jsx, ui.jsx), цвета — из палитры, размер шрифта меню — настройка uiFontSize.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'colors.dart';

/// Контекст под MaterialApp (с Navigator и ScaffoldMessenger): нужен, когда окно или уведомление
/// показывают из фоновой работы, где есть только WidgetRef от корня приложения.
BuildContext? appContext() {
  NavigatorState? nav;
  void visit(Element e) {
    if (nav != null) return;
    if (e is StatefulElement && e.state is NavigatorState) {
      nav = e.state as NavigatorState;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return nav?.overlay?.context;
}

void toast(BuildContext? context, String text) {
  if (context == null) return Hub.toast(text);
  final m = ScaffoldMessenger.maybeOf(context);
  m == null ? Hub.toast(text) : m.showSnackBar(SnackBar(content: Text(text)));
}

/// Открыть нижний лист. full — почти на весь экран (настройки, библиотека), иначе по высоте содержимого
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: builder,
  );
}

/// Каркас окна: ручка, заголовок (+ подзаголовок), стрелка «‹» или крестик, прокручиваемое содержимое
class AppSheet extends ConsumerWidget {
  const AppSheet({super.key, required this.title, required this.children, this.subtitle, this.onBack, this.full = false, this.footer, this.fixed});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool full;
  final List<Widget> children;
  final Widget? footer;
  final Widget? fixed; // закреплено под заголовком (поиск, вкладки)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final pal = effectivePalette(s);
    final scale = s.d('uiFontSize') / 15;
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.92;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: pal.text),
        child: Container(
          height: full ? maxH : null,
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(color: pal.panel, borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
          child: Column(mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min, children: [
            Center(child: Container(margin: const EdgeInsets.only(top: 8, bottom: 2), width: 40, height: 4, decoration: BoxDecoration(color: pal.line, borderRadius: BorderRadius.circular(2)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
              child: Row(children: [
                if (onBack != null) IconButton(icon: Icon(Icons.chevron_left, color: pal.text), tooltip: t('Назад'), onPressed: onBack),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: onBack == null ? 12 : 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: pal.text)),
                      if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.muted)),
                    ]),
                  ),
                ),
                IconButton(icon: Icon(Icons.close, color: pal.muted), tooltip: t('Закрыть'), onPressed: () => Navigator.of(context).maybePop()),
              ]),
            ),
            if (fixed != null) fixed!,
            Flexible(
              fit: full ? FlexFit.tight : FlexFit.loose,
              child: ListView(shrinkWrap: !full, padding: EdgeInsets.fromLTRB(14, 4, 14, 16 + mq.padding.bottom), children: children),
            ),
            if (footer != null) Padding(padding: EdgeInsets.fromLTRB(14, 6, 14, 12 + mq.padding.bottom), child: footer),
          ]),
        ),
      ),
    );
  }
}

/// Строка-переход: значок, название, пояснение мелко, стрелка (как .pref-row)
class PrefRow extends ConsumerWidget {
  const PrefRow({super.key, required this.icon, required this.title, this.sub, this.onTap, this.extra, this.leading, this.chevron = true});
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final Widget? extra;
  final bool chevron;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(children: [
          SizedBox(width: 30, child: leading ?? Icon(icon, size: 21, color: onTap == null ? pal.muted : pal.accent)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: TextStyle(fontSize: 13, color: pal.muted))),
            ]),
          ),
          if (extra != null) extra!,
          if (chevron && onTap != null) Icon(Icons.chevron_right, size: 20, color: pal.muted),
        ]),
      ),
    );
  }
}

class SwitchRow extends ConsumerWidget {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
              if (hint != null) Text(hint!, style: TextStyle(fontSize: 13, color: pal.muted)),
            ]),
          ),
          Switch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// Выбор из нескольких (Segmented): подпись сверху, кнопки в ряд
class SegRow<T> extends ConsumerWidget {
  const SegRow({super.key, required this.label, required this.value, required this.options, required this.onChanged, this.valueText, this.labelStyle});
  final TextStyle? Function(T)? labelStyle; // свой вид подписи кнопки (например, толщина букв)
  final String label;
  final String? valueText;
  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text))),
          if (valueText != null) Text(valueText!, style: TextStyle(fontSize: 14, color: pal.muted)),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [for (final o in options) ButtonSegment<T>(value: o.$1, label: Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle?.call(o.$1)), icon: o.$3 == null ? null : Icon(o.$3, size: 17))],
            selected: {value},
            onSelectionChanged: (v) => onChanged(v.first),
          ),
        ),
      ]),
    );
  }
}

/// Ползунок с кнопками «меньше / больше» по краям и понятным значением словами.
/// Пока ползунок тянут, значение двигается сразу, а в настройки уходит не чаще раза в 180 мс и при отпускании:
/// каждое изменение перекладывает весь текст под окном.
class RangeRow extends ConsumerStatefulWidget {
  const RangeRow({super.key, required this.label, required this.value, required this.min, required this.max, required this.step, required this.onChanged, required this.word, this.big = false, this.hint});
  final String label;
  final String? hint;
  final double value, min, max, step;
  final ValueChanged<double> onChanged;
  final String Function(double) word;
  final bool big; // кнопки «А» вместо «−/+»

  @override
  ConsumerState<RangeRow> createState() => _RangeRowState();
}

class _RangeRowState extends ConsumerState<RangeRow> {
  late double _v = widget.value;
  Timer? _timer;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(RangeRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double _fix(double x) => (x.clamp(widget.min, widget.max) / widget.step).round() * widget.step;

  void _change(double x, {bool now = false}) {
    final v = double.parse(_fix(x).toStringAsFixed(3));
    setState(() => _v = v);
    _timer?.cancel();
    final wait = now ? Duration.zero : Duration(milliseconds: (180 - DateTime.now().difference(_last).inMilliseconds).clamp(0, 180));
    _timer = Timer(wait, () {
      _last = DateTime.now();
      widget.onChanged(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    final w = widget;
    Widget step(IconData icon, String small, double delta, bool enabled) => IconButton(
          onPressed: enabled ? () => _change(_v + delta, now: true) : null,
          icon: w.big ? Text('A', style: TextStyle(fontSize: delta < 0 ? 14 : 22, fontWeight: FontWeight.w800, color: enabled ? pal.text : pal.muted)) : Icon(icon, size: 20),
          tooltip: small,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(w.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text))),
          Text(w.word(_v), style: TextStyle(fontSize: 14, color: pal.muted)),
        ]),
        if (w.hint != null) Text(w.hint!, style: TextStyle(fontSize: 13, color: pal.muted)),
        Row(children: [
          step(Icons.remove, t('{label}: меньше', {'label': w.label}), -w.step, _v > w.min),
          Expanded(
            child: Slider(
              value: _v.clamp(w.min, w.max),
              min: w.min,
              max: w.max,
              divisions: ((w.max - w.min) / w.step).round(),
              onChanged: (x) => _change(x),
              onChangeEnd: (x) => _change(x, now: true),
            ),
          ),
          step(Icons.add, t('{label}: больше', {'label': w.label}), w.step, _v < w.max),
        ]),
      ]),
    );
  }
}

/// Карточка группы настроек
class Card2 extends ConsumerWidget {
  const Card2({super.key, required this.children, this.title});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null) Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 4), child: Text(title!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.muted))),
        ...children,
      ]),
    );
  }
}

/// Подтверждение удаления и т. п.
Future<bool> confirm(BuildContext context, String text, String ok) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Отмена'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

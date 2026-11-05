// Общие кирпичики окон «Ещё», «Настройки», «Оформление», «Библиотека»…: окно (поверх AobSheet из kit.dart), поле-
// переключатель с пояснением, ползунок со ступенями, выбор из нескольких, карточка группы, подтверждение на месте.
// Вид — как в веб-версии (BottomSheet.jsx, ui.jsx, styles.css); цвета — из палитры, размер шрифта меню — настройка uiFontSize.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons, CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/ios_style.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import '../plans/net_cache.dart' show siteJson;

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

/// Открыть нижнее окно (как BottomSheet с initial={2} в веб-версии — почти на весь экран)
// окна оболочки (настройки, библиотека, о приложении, что нового, инструкция, оформление) — вкладка «Ещё», как в вебе
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) => showAobSheet<T>(context, builder: builder, tab: 'more');

/// Каркас окна: полоска, заголовок (+ подзаголовок), стрелка «‹» или крестик, линия под шапкой — это AobSheet;
/// здесь добавлены закреплённая часть под шапкой (fixed), прокручиваемое содержимое со зазором 12 между блоками
/// (.sheet-body) и нижняя панель (footer, .sheet-foot).
class AppSheet extends ConsumerWidget {
  const AppSheet({super.key, required this.title, required this.children, this.subtitle, this.onBack, this.footer, this.fixed, this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 20), this.gap = 12});
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> children;
  final Widget? footer;
  final Widget? fixed; // закреплено под заголовком (образец, поиск, вкладки)
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final scale = ref.watch(settingsProvider.select((s) => s.d('uiFontSize'))) / 15;
    final mq = MediaQuery.of(context);
    // стиль iPhone: подряд идущие строки — в общие скруглённые карточки, как в «Настройках» iPhone
    final children = iosStyleOf(ref) ? iosGroup(this.children, pal, padding.left, gap: gap) : this.children;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
      child: AobSheet(
        title: title,
        subtitle: subtitle,
        onBack: onBack,
        scroll: false,
        padding: EdgeInsets.zero,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 15, color: pal.text),
          child: Column(children: [
            ?fixed,
            Expanded(
              child: Builder(builder: (bc) => ListView.separated(
                key: ValueKey(title), // другая страница окна («Меню «Ещё»», подраздел «Оформления») — с самого верха, а не с прежнего места прокрутки
                padding: padding.copyWith(bottom: padding.bottom + MediaQuery.paddingOf(bc).bottom),
                itemCount: children.length,
                separatorBuilder: (_, _) => SizedBox(height: gap),
                itemBuilder: (_, i) => children[i],
              )),
            ),
            if (footer != null)
              // подвал — над вкладками: нижний отступ берём внутри окна (там к системному уже прибавлена высота вкладок)
              Builder(
                builder: (bc) => Container(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(bc).bottom),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
                  child: footer,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Закреплённая под шапкой часть окна: поля шириной окна с отступами 16
class SheetFixed extends StatelessWidget {
  const SheetFixed({super.key, required this.child, this.bottom = 4});
  final Widget child;
  final double bottom;
  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, bottom), child: child);
}

/// Подпись поля (.field-label): w500, в «Оформлении» — w600
TextStyle fieldLabel(Palette pal, {bool bold = false}) =>
    iosUiNow ? TextStyle(fontSize: 17, color: pal.text) : TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w600 : FontWeight.w500, color: pal.text);

/// Значок ⓘ с подсказкой (Hint в ui.jsx): нажатие раскрывает плашку цвета верхней панели
class HintDot extends ConsumerWidget {
  const HintDot({super.key, required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 28, height: 24, child: Icon(ico(LucideIcons.info), size: 16, color: on ? pal.accent : pal.muted)),
    );
  }
}

/// Плашка подсказки: цвета верхней панели, скругление 9.6, текст 13.4
class HintBubble extends ConsumerWidget {
  const HintBubble(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: pal.bar, borderRadius: BorderRadius.circular(kRadius * 0.8), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))]),
      child: Text(text, style: TextStyle(fontSize: 13.4, height: 1.45, color: pal.barText)),
    );
  }
}

/// Переключатель с подписью (.switch-field + Switch из ui.jsx): пояснение — значком ⓘ, как в веб-версии
class SwitchField extends ConsumerStatefulWidget {
  const SwitchField({super.key, required this.label, required this.value, required this.onChanged, this.hint, this.bold = false, this.big = false});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool bold; // в «Оформлении» подписи w600
  final bool big; // первая строка карточки (.ap-card.lead): крупнее
  @override
  ConsumerState<SwitchField> createState() => _SwitchFieldState();
}

class _SwitchFieldState extends ConsumerState<SwitchField> {
  bool _hint = false;
  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final base = fieldLabel(pal, bold: widget.bold);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => widget.onChanged(!widget.value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: widget.label, style: widget.big && !iosUiNow ? base.copyWith(fontSize: 16.3, fontWeight: FontWeight.w700) : base),
                  if (widget.hint != null) WidgetSpan(alignment: PlaceholderAlignment.middle, child: HintDot(on: _hint, onTap: () => setState(() => _hint = !_hint))),
                ])),
              ),
              const SizedBox(width: 12),
              AobSwitch(value: widget.value, onChanged: widget.onChanged),
            ]),
          ),
        ),
      ),
      if (widget.hint != null) Reveal(open: _hint, child: Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: HintBubble(widget.hint!))),
    ]);
  }
}

/// Выбор из нескольких (.segmented): подложка, выбранный — белая «таблетка»; если не помещаются в строку — переносятся
/// на следующую, каждая строка растягивается на всю ширину (flex: 1 1 auto). Подпись — любой виджет (значок + текст).
class SegBar<T> extends ConsumerWidget {
  const SegBar({super.key, required this.options, required this.value, required this.onChanged, this.minHeight = 0});
  final List<(T, Widget, String)> options; // значение, подпись, текст для замера ширины
  final T value;
  final ValueChanged<T> onChanged;
  final double minHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return LayoutBuilder(builder: (context, box) {
      final scaler = MediaQuery.textScalerOf(context);
      // ширины считаем один раз за построение; TextPainter освобождаем
      double natural(String text) {
        final tp = TextPainter(text: TextSpan(text: text, style: const TextStyle(fontSize: 13.2, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
        final w = tp.width + 16 + 22; // поля по 8 и запас на значок
        tp.dispose();
        return w;
      }

      final widths = [for (final o in options) natural(o.$3)];

      final inner = box.maxWidth - 6;
      final lines = <List<int>>[[]];
      var used = 0.0;
      for (var i = 0; i < options.length; i++) {
        final w = widths[i];
        if (lines.last.isNotEmpty && used + w + 2 > inner) {
          lines.add([]);
          used = 0;
        }
        lines.last.add(i);
        used += w + 2;
      }
      Widget cell(int i) {
        final on = options[i].$1 == value;
        return Expanded(
          flex: widths[i].round(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(options[i].$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic, // с «пружиной» тень уходит в отрицательный размер
              constraints: BoxConstraints(minHeight: minHeight),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: on ? pal.panel : Colors.transparent,
                borderRadius: BorderRadius.circular(kRadius * 0.6),
                boxShadow: on ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))] : null,
              ),
              alignment: Alignment.center,
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13.2, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? pal.accent : pal.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: IconTheme.merge(data: IconThemeData(color: on ? pal.accent : pal.text, size: 17), child: options[i].$2),
              ),
            ),
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(kRadius * 0.75)),
        child: Column(children: [
          for (var l = 0; l < lines.length; l++)
            Padding(
              padding: EdgeInsets.only(top: l == 0 ? 0 : 2),
              child: Row(children: [
                for (var k = 0; k < lines[l].length; k++) ...[if (k > 0) const SizedBox(width: 2), cell(lines[l][k])],
              ]),
            ),
        ]),
      );
    });
  }
}

/// Выбор из нескольких с подписью сверху (поле .field + Segmented). Простые подписи — kit.Segmented,
/// со значком или своим видом букв — SegBar.
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
    final pal = paletteOf(ref);
    final plain = labelStyle == null && options.every((o) => o.$3 == null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(label, style: fieldLabel(pal, bold: true))),
        if (valueText != null) Text(valueText!, style: TextStyle(fontSize: 14.7, color: pal.muted)),
      ]),
      const SizedBox(height: 6),
      if (plain)
        Segmented<T>(options: [for (final o in options) (o.$1, o.$2)], value: value, onChanged: onChanged)
      else
        SegBar<T>(
          minHeight: 40,
          value: value,
          onChanged: onChanged,
          options: [
            for (final o in options)
              (
                o.$1,
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (o.$3 != null) ...[Icon(o.$3, size: 17), const SizedBox(width: 6)],
                  Flexible(child: Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle?.call(o.$1))),
                ]),
                o.$2,
              ),
          ],
        ),
    ]);
  }
}

/// Ползунок с кнопками «меньше / больше» по краям и понятным значением словами (.ap-range).
/// Пока ползунок тянут, значение двигается сразу, а в настройки уходит не чаще раза в 180 мс и при отпускании:
/// каждое изменение перекладывает весь текст под окном.
class RangeRow extends ConsumerStatefulWidget implements IosGroupBlock {
  const RangeRow({super.key, required this.label, required this.value, required this.min, required this.max, required this.step, required this.onChanged, required this.word, this.big = false, this.hint, this.buttons = true});
  final String label;
  final String? hint;
  final double value, min, max, step;
  final ValueChanged<double> onChanged;
  final String Function(double) word;
  final bool big; // кнопки «А» вместо «−/+»
  final bool buttons; // кнопки «меньше / больше» по краям (в приветствии их нет)

  @override
  double get iosIndent => iosRowIconLeft;

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
    final pal = paletteOf(ref);
    final w = widget;
    // .ap-step: круг 44 с рамкой, фон страницы; «A» — маленькая и большая буквы
    Widget step(IconData icon, String tip, double delta, bool enabled) => iosStyleOf(ref)
        ? Semantics(
            label: tip,
            button: true,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 44),
              onPressed: enabled ? () => _change(_v + delta, now: true) : null,
              child: w.big
                  ? Text('A', style: TextStyle(fontSize: delta < 0 ? 13 : 22, color: pal.text))
                  : Icon(delta < 0 ? CupertinoIcons.minus : CupertinoIcons.plus, size: 18, color: pal.muted),
            ),
          )
        : Tooltip(
          message: tip,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Material(
              color: pal.bg,
              shape: CircleBorder(side: BorderSide(color: pal.line)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? () => _change(_v + delta, now: true) : null,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  // у заглавной «A» нет нижнего выносного элемента — без сдвига она садится ниже середины круга
                  child: Center(
                    child: w.big
                        ? Transform.translate(
                            offset: Offset(0, -(delta < 0 ? 13 : 23) * 0.08),
                            child: Text('A', style: TextStyle(fontSize: delta < 0 ? 13 : 23, fontWeight: FontWeight.w600, height: 1, leadingDistribution: TextLeadingDistribution.even, color: pal.text)),
                          )
                        : Icon(ico(icon), size: 18, color: pal.text),
                  ),
                ),
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(w.label, style: fieldLabel(pal, bold: true))),
        Text(w.word(_v), style: TextStyle(fontSize: 14.7, color: pal.muted)),
      ]),
      if (w.hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(w.hint!, style: TextStyle(fontSize: 13.1, color: pal.muted, height: 1.4))),
      const SizedBox(height: 4),
      Row(children: [
        if (w.buttons) ...[
          step(LucideIcons.minus, t('{label}: меньше', {'label': w.label}), -w.step, _v > w.min),
          const SizedBox(width: 8),
        ],
        if (iosStyleOf(ref))
          // стиль iPhone: системный ползунок iOS
          Expanded(
            child: SizedBox(
              height: 44,
              child: CupertinoSlider(
                value: _v.clamp(w.min, w.max),
                min: w.min,
                max: w.max,
                divisions: math.max(1, ((w.max - w.min) / w.step).round()),
                activeColor: pal.accent,
                onChanged: (x) => _change(x),
                onChangeEnd: (x) => _change(x, now: true),
              ),
            ),
          )
        else
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 5,
              activeTrackColor: pal.accent,
              inactiveTrackColor: pal.text.withValues(alpha: 0.16),
              thumbColor: pal.accent,
              overlayColor: pal.accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              trackShape: const RoundedRectSliderTrackShape(),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: SizedBox(
              height: 44,
              child: Slider(
                value: _v.clamp(w.min, w.max),
                min: w.min,
                max: w.max,
                divisions: math.max(1, ((w.max - w.min) / w.step).round()),
                onChanged: (x) => _change(x),
                onChangeEnd: (x) => _change(x, now: true),
              ),
            ),
          ),
        ),
        if (w.buttons) ...[
          const SizedBox(width: 8),
          step(LucideIcons.plus, t('{label}: больше', {'label': w.label}), w.step, _v < w.max),
        ],
      ]),
    ]);
  }
}

/// Карточка группы настроек (.ap-card): рамка, скругление 12, зазор 14, заголовок 1.02rem w700
class Card2 extends ConsumerWidget {
  const Card2({super.key, required this.children, this.title});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final ios = iosStyleOf(ref);
    final all = [if (title != null && !ios) Text(title!, style: TextStyle(fontSize: 16.3, fontWeight: FontWeight.w700, color: pal.text)), ...children];
    final card = Container(
      padding: ios ? const EdgeInsets.fromLTRB(iosRowIconLeft, 12, iosRowRight, 14) : const EdgeInsets.fromLTRB(14, 12, 14, 14),
      // стиль iPhone: карточка группы — системная заливка и скругление, без рамки
      decoration: ios
          ? BoxDecoration(color: iosCardAt(pal, IosElevated.of(context)), borderRadius: BorderRadius.circular(iosRadius))
          : BoxDecoration(color: cardFill(pal), border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // раскрывающийся блок (Reveal) сам несёт зазор сверху — свёрнутый не оставляет пустого места
        for (var i = 0; i < all.length; i++) ...[if (i > 0 && all[i] is! Reveal) const SizedBox(height: 14), all[i]],
      ]),
    );
    if (!ios || title == null) return card;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(left: iosRowIconLeft, bottom: 6), child: GroupTitle(title!)),
      card,
    ]);
  }
}

/// Подтверждение на месте (ConfirmButton в ui.jsx): нажали — вместо кнопки «Да» (красная) и «Отмена»
class ConfirmButton extends StatefulWidget {
  const ConfirmButton({super.key, required this.label, required this.confirmText, required this.onConfirm, this.icon, this.small = false, this.block = false});
  final bool block; // одиночная кнопка: на телефоне — на всю ширину, «Да» и «Отмена» — поровну
  final String label;
  final String confirmText;
  final IconData? icon;
  final bool small;
  final VoidCallback onConfirm;
  @override
  State<ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<ConfirmButton> {
  bool _armed = false;
  @override
  Widget build(BuildContext context) {
    // стиль iPhone: подтверждение — системным листом действий снизу, а не кнопками на месте
    final ios = ProviderScope.containerOf(context, listen: false).read(settingsProvider).get<bool>('iosStyle');
    if (!_armed) {
      return AobButton(
        label: widget.label,
        icon: widget.icon,
        small: widget.small,
        block: widget.block,
        onTap: ios ? () => iosConfirm(context, action: widget.confirmText, onConfirm: widget.onConfirm) : () => setState(() => _armed = true),
      );
    }
    if (widget.block && isPhone(context)) {
      return Row(children: [
        Expanded(
          child: AobButton(
            label: widget.confirmText,
            kind: BtnKind.danger,
            small: widget.small,
            wide: true,
            onTap: () {
              setState(() => _armed = false);
              widget.onConfirm();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: AobButton(label: t('Отмена'), small: widget.small, wide: true, onTap: () => setState(() => _armed = false))),
      ]);
    }
    // Wrap: при крупном шрифте «Отмена» уходит на вторую строку, а не за край окна
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      AobButton(
        label: widget.confirmText,
        kind: BtnKind.danger,
        small: widget.small,
        onTap: () {
          setState(() => _armed = false);
          widget.onConfirm();
        },
      ),
      AobButton(label: t('Отмена'), small: widget.small, onTap: () => setState(() => _armed = false)),
    ]);
  }
}

/// Крутящийся значок загрузки (Loader2 + .spin)
class Spin extends StatefulWidget {
  const Spin({super.key, this.size = 16, this.color});
  final double size;
  final Color? color;
  @override
  State<Spin> createState() => _SpinState();
}

class _SpinState extends State<Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: Icon(ico(LucideIcons.loaderCircle), size: widget.size, color: widget.color));
}

/// Надпись «Загрузка…» (.loading): по центру, бледная
class Loading extends ConsumerWidget {
  const Loading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Spin(size: 20, color: pal.muted), const SizedBox(width: 10), Text(text, style: TextStyle(fontSize: 14.25, color: pal.muted))]),
    );
  }
}

/// Сетевые источники окон «Библиотека» и «О приложении»: в тестах подменяются данными
Future<List<CatalogEntry>> Function() loadCatalog = () => ModuleStore.instance.catalog();
Future<Map<String, dynamic>?> Function(String path) loadSiteJson = siteJson;

// Общие элементы интерфейса — один в один с веб-версией (E:\AO Bible\src\styles.css, src/components/ui.jsx,
// BottomSheet.jsx). Значки — Lucide (как lucide-react в веб-версии): LucideIcons.<имя в camelCase>.
// Базовый размер шрифта интерфейса — 15 px (body в веб-версии), 1rem = 16 px.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import '../core/settings.dart';

export 'package:lucide_icons_flutter/lucide_icons.dart' show LucideIcons;

/// color-mix(in srgb, a p%, b): как в CSS — с учётом прозрачности (смесь с transparent не темнеет, а становится прозрачнее)
Color mix(Color a, double p, Color b) {
  final q = 1 - p;
  final alpha = a.a * p + b.a * q;
  if (alpha == 0) return const Color(0x00000000);
  double ch(double x, double y) => (x * a.a * p + y * b.a * q) / alpha;
  return Color.from(alpha: alpha, red: ch(a.r, b.r), green: ch(a.g, b.g), blue: ch(a.b, b.b));
}

const double kRadius = 12; // --radius

/// Палитра текущей темы (со своими цветами)
Palette paletteOf(WidgetRef ref) => ref.watch(settingsProvider.select((s) => s.palette));

// --- Нижнее окно (BottomSheet.jsx): скруглённый верх, полоска, заголовок, крестик ------------------------

/// Открыть окно: initial — доля высоты экрана (как initial={1|2} в веб-версии: 0.5 или 0.92).
/// Окно, открытое поверх другого окна (из «Ещё», из «Настроек»…), получает стрелку «назад» к нему,
/// а крестик закрывает все окна разом.
Future<T?> showAobSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context) builder,
  double initial = 0.92,
  bool page = false,
}) {
  final nested = topRoute(context) is PopupRoute;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: nested ? 0.12 : 0.32), // второе затемнение поверх первого — слабее
    enableDrag: !nested, // окно поверх окна — на весь экран, не сворачивается: «назад» и крестик
    // Окно поднимается над клавиатурой: поле ввода (заметка, поиск) не прячется под ней
    builder: (c) => _Nested(
      nested: nested,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: FractionallySizedBox(heightFactor: page || nested ? 1 : initial, child: builder(c)),
      ),
    ),
  );
}

/// Верхний маршрут навигатора (popUntil с «да» на первом же ничего не закрывает)
Route<dynamic>? topRoute(BuildContext context) {
  Route<dynamic>? top;
  Navigator.of(context).popUntil((r) {
    top = r;
    return true;
  });
  return top;
}

/// Закрыть все открытые окна (нижние окна, окна изучения, меню) — до экрана чтения
void closeAllSheets(BuildContext context) => Navigator.of(context).popUntil((r) => r is! PopupRoute);

class _Nested extends InheritedWidget {
  const _Nested({required this.nested, required super.child});
  final bool nested;
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Nested>()?.nested ?? false;
  @override
  bool updateShouldNotify(_Nested old) => old.nested != nested;
}

class AobSheet extends ConsumerWidget {
  const AobSheet({super.key, required this.title, this.subtitle, required this.child, this.onBack, this.actions = const [], this.onClose, this.scroll = true, this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 20)});
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final bool scroll; // false — child сам прокручивается (списки)
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final body = Padding(padding: padding, child: child);
    // своя «назад» (шаг внутри окна) — или к окну, поверх которого открыто это
    final back = onBack ?? (_Nested.of(context) ? () => Navigator.of(context).maybePop() : null);
    return Material(
      color: pal.panel,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadius + 6)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // полоска — только у окна, которое можно потянуть; у окна на весь экран — просто отступ сверху
        if (_Nested.of(context))
          const SizedBox(height: 14)
        else
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Container(width: 40, height: 5, decoration: BoxDecoration(color: mix(pal.muted, 0.45, pal.panel), borderRadius: BorderRadius.circular(3))),
          ),
        Container(
          padding: EdgeInsets.fromLTRB(back != null ? 6 : 16, 0, 10, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(children: [
            if (back != null) IconBtn(icon: LucideIcons.chevronLeft, tooltip: t('Назад'), onTap: back),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: 18.4, fontWeight: FontWeight.w700, color: pal.text)),
                if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.muted)),
              ]),
            ),
            ...actions,
            IconBtn(icon: LucideIcons.x, tooltip: t('Закрыть'), onTap: onClose ?? () => closeAllSheets(context)),
          ]),
        ),
        Expanded(child: scroll ? SingleChildScrollView(child: body) : body),
      ]),
    );
  }
}

// --- Кнопки ---------------------------------------------------------------------------------------------

/// .icon-btn: круглая 38×38 без фона; subtle — 32×32 серая; on — цвет акцента
class IconBtn extends ConsumerWidget {
  const IconBtn({super.key, required this.icon, required this.onTap, this.subtle = false, this.on = false, this.color, this.size, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final bool subtle;
  final bool on;
  final Color? color;
  final double? size;
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final d = subtle ? 32.0 : 38.0;
    final btn = SizedBox(
      width: d,
      height: d,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Icon(icon, size: size ?? (subtle ? 18 : 22), color: color ?? (on ? pal.accent : subtle ? pal.muted : pal.text))),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

enum BtnKind { normal, primary, danger, ghost }

/// .btn: скругление 9, рамка line, фон bg; primary — акцент; small — меньше; wide — во всю ширину
class AobButton extends ConsumerWidget {
  const AobButton({super.key, required this.label, this.icon, required this.onTap, this.kind = BtnKind.normal, this.small = false, this.wide = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool small;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (pal.accent, pal.onAccent, pal.accent),
      BtnKind.danger => (const Color(0xffc93a3a), Colors.white, const Color(0xffc93a3a)),
      BtnKind.ghost => (Colors.transparent, pal.text, Colors.transparent),
      BtnKind.normal => (pal.bg, pal.text, pal.line),
    };
    final content = Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[Icon(icon, size: small ? 14 : 16, color: fg), const SizedBox(width: 6)],
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 13.8 : 15.2, fontWeight: FontWeight.w500, color: fg))),
    ]);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: small ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6) : const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: content),
        ),
      ),
    );
  }
}

/// .chip: плашка-«таблетка»; on — цвет акцента; ghost — без фона
class AobChip extends ConsumerWidget {
  const AobChip({super.key, required this.label, this.onTap, this.on = false, this.icon, this.ghost = false, this.count});
  final String label;
  final VoidCallback? onTap;
  final bool on;
  final IconData? icon;
  final bool ghost;
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final fg = on ? pal.onAccent : ghost ? pal.muted : pal.text;
    return Material(
      color: on ? pal.accent : ghost ? Colors.transparent : pal.bg,
      shape: StadiumBorder(side: BorderSide(color: on ? pal.accent : pal.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
            Text(label, style: TextStyle(fontSize: 13.8, color: fg)),
            if (count != null) ...[const SizedBox(width: 5), Text('$count', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8)))],
          ]),
        ),
      ),
    );
  }
}

// --- Строки ---------------------------------------------------------------------------------------------

/// .pref-row: значок в цветном квадрате 38×38 (скругление 11), заголовок, подпись, стрелка; линия снизу
class PrefRow extends ConsumerWidget {
  const PrefRow({super.key, required this.icon, required this.title, this.sub, required this.onTap, this.trailing, this.last = false, this.leading});
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading; // вместо значка (флаг языка)
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: pal.line))),
        child: Row(children: [
          leading ??
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: mix(pal.accent, 0.12, pal.bg), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 20, color: pal.accent),
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: TextStyle(fontSize: 12.5, color: pal.muted))),
            ]),
          ),
          trailing ?? Icon(LucideIcons.chevronRight, size: 18, color: pal.muted),
        ]),
      ),
    );
  }
}

/// .menu-item: значок цвета акцента, подпись, справа — дополнение (вкл/выкл, «новая»)
class MenuRow extends ConsumerWidget {
  const MenuRow({super.key, required this.icon, required this.label, required this.onTap, this.extra, this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? extra;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(kRadius * 0.6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: color ?? pal.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 15.7, color: color ?? pal.text))),
            if (extra != null) extra!,
          ]),
        ),
      ),
    );
  }
}

class MenuSep extends ConsumerWidget {
  const MenuSep({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), color: paletteOf(ref).line);
}

/// Подзаголовок группы (h4 в окнах веб-версии)
class GroupTitle extends ConsumerWidget {
  const GroupTitle(this.text, {super.key, this.dot});
  final String text;
  final Color? dot; // цветная точка (разделы книг в «Перейти»)
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(children: [
        if (dot != null) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
        Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: pal.muted)),
      ]),
    );
  }
}

// --- Переключатель и сегменты ---------------------------------------------------------------------------

/// .switch: дорожка 44×26, белый бегунок 20 с тенью; пружинистое движение, как в веб-версии
class AobSwitch extends ConsumerWidget {
  const AobSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: value ? pal.accent : pal.muted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(13)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 380),
          curve: const Cubic(.3, 1.45, .5, 1),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
              BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Строка с подписью и переключателем (.switch-field)
class SwitchRow extends ConsumerWidget {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text))),
              if (hint != null) Hint(hint!),
            ]),
          ),
          AobSwitch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

/// .segmented: серая подложка, выбранный — белая «таблетка» с тенью и текстом цвета акцента
class Segmented<T> extends ConsumerWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  // Ширина вариантов — как flex: 1 1 auto в веб-версии: по тексту плюс поровну свободного места;
  // не помещаются в строку — переносятся (flex-wrap)
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final scale = MediaQuery.textScalerOf(context);
    TextStyle style(bool on) => TextStyle(fontSize: 14.08, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? pal.accent : pal.text);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(kRadius * 0.75)),
      child: LayoutBuilder(builder: (context, c) {
        // ширина по жирному начертанию — выбор варианта не сдвигает соседей
        final basis = [
          for (final (_, label) in options)
            (TextPainter(text: TextSpan(text: label, style: style(true)), textDirection: TextDirection.ltr, maxLines: 1, textScaler: scale)..layout()).width + 16.5,
        ];
        const gap = 2.0;
        final total = basis.fold<double>(0, (a, b) => a + b) + gap * (options.length - 1);
        final fits = total <= c.maxWidth;
        final extra = fits ? (c.maxWidth - total) / options.length - 0.01 : 0.0; // запас на округление, иначе Wrap перенесёт последний
        Widget item(int i) {
          final (v, label) = options[i];
          final on = v == value;
          return GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic, // у тени не может быть «перелёта» пружинной кривой
              width: fits ? basis[i] + extra : basis[i],
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: on ? pal.panel : Colors.transparent,
                borderRadius: BorderRadius.circular(kRadius * 0.6),
                boxShadow: on ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))] : null,
              ),
              alignment: Alignment.center,
              child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style(on)),
            ),
          );
        }

        return Wrap(spacing: gap, runSpacing: gap, children: [for (var i = 0; i < options.length; i++) item(i)]);
      }),
    );
  }
}

/// Поле ввода (.input-wrap): серый фон, скругление, значок слева, кнопка справа
class AobInput extends ConsumerWidget {
  const AobInput({super.key, required this.controller, this.hint, this.icon = LucideIcons.search, this.onSubmitted, this.onChanged, this.autofocus = false, this.trailing});
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: TextStyle(fontSize: 16, color: pal.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: pal.muted),
        prefixIcon: icon == null ? null : Icon(icon, size: 18, color: pal.muted),
        suffixIcon: trailing,
        isDense: true,
        filled: true,
        fillColor: pal.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide(color: pal.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide(color: pal.accent)),
      ),
    );
  }
}

/// Круглая кнопка поверх текста (стрелки глав, «Слушать»): 44×44, полупрозрачная панель, тень
class RoundFab extends ConsumerWidget {
  const RoundFab({super.key, required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Tooltip(
      message: tooltip ?? '',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: mix(pal.panel, 0.92, Colors.transparent),
          border: Border.all(color: pal.line),
          boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Material(type: MaterialType.transparency, shape: const CircleBorder(), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Icon(icon, size: 22, color: pal.text))),
      ),
    );
  }
}

// --- Подсказка, ход, загрузка ------------------------------------------------------------------------------

/// Пояснение к настройке (Hint в ui.jsx): «!» в кружке рядом с названием, текст — во всплывающем облачке цвета панели
/// инструментов; открывается нажатием, закрывается нажатием мимо
class Hint extends ConsumerWidget {
  const Hint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Tooltip(
      message: text,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      preferBelow: true,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: pal.bar,
        borderRadius: BorderRadius.circular(kRadius * 0.8),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      textStyle: TextStyle(fontSize: 13.4, height: 1.45, color: pal.barText),
      child: SizedBox(width: 26, height: 24, child: Icon(LucideIcons.circleAlert, size: 15, color: pal.muted)),
    );
  }
}

/// Полоска хода (.progress): дорожка 6 px, заполнение акцентом, подпись под ней
class AobProgress extends ConsumerWidget {
  const AobProgress({super.key, required this.value, this.label});
  final double value;
  final String? label;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 6,
          color: pal.muted.withValues(alpha: 0.2),
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 200),
            widthFactor: value.clamp(0.0, 1.0),
            heightFactor: 1,
            child: DecoratedBox(decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(3))),
          ),
        ),
      ),
      if (label != null) ...[
        const SizedBox(height: 6),
        Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.1, color: pal.muted, fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    ]);
  }
}

/// Вращающийся значок загрузки (Loader2 с классом spin в веб-версии)
class Spinner extends ConsumerStatefulWidget {
  const Spinner({super.key, this.size = 18, this.color});
  final double size;
  final Color? color;
  @override
  ConsumerState<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends ConsumerState<Spinner> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _c, child: Icon(LucideIcons.loaderCircle, size: widget.size, color: widget.color ?? paletteOf(ref).muted));
}

/// Уведомление (.toast): тёмная «таблетка» цвета панели инструментов над нижним краем; с действием — кнопка справа
SnackBar aobSnackBar(Palette pal, String text, {String? actionLabel, VoidCallback? action}) {
  final hasAction = actionLabel != null && action != null;
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    duration: Duration(milliseconds: hasAction ? 5000 : 2600),
    content: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: hasAction ? const EdgeInsets.fromLTRB(16, 6, 6, 6) : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: mix(pal.bar, 0.92, Colors.transparent),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(text, textAlign: hasAction ? TextAlign.left : TextAlign.center, style: TextStyle(fontSize: 14.4, color: pal.barText)),
            ),
            if (hasAction) ...[
              const SizedBox(width: 12),
              Material(
                color: pal.barText.withValues(alpha: 0.16),
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: action,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(actionLabel, style: TextStyle(fontSize: 14.4, fontWeight: FontWeight.w700, color: pal.barText)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    ),
  );
}

// --- Вкладки и ряд плашек -----------------------------------------------------------------------------------

/// Расширить на поля окна (16 с каждой стороны): линия вкладок и ряд плашек — от края до края
Widget _bleed(Widget child) => LayoutBuilder(
      // не внутри вертикального списка (там высота не ограничена): вкладки окна — в закреплённой части
      builder: (context, box) => OverflowBox(minWidth: box.maxWidth + 32, maxWidth: box.maxWidth + 32, child: child),
    );

/// Вкладки разделов (.tabs): на всю ширину, поровну; выбранная — цвета акцента с линией 2 px, число — мельче, серое.
/// Не помещаются — прокручиваются. bleed — вкладки стоят внутри полей окна, а линия должна идти от края до края.
class AobTabs<T> extends ConsumerWidget {
  const AobTabs({super.key, required this.tabs, required this.value, required this.onChanged, this.bleed = false});
  final List<(T, String, int?)> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final bool bleed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final scale = MediaQuery.textScalerOf(context);
    const label = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    Widget tab((T, String, int?) x, {bool expand = false}) {
      final on = x.$1 == value;
      final w = InkWell(
        onTap: () => onChanged(x.$1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: expand ? Alignment.center : null,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? pal.accent : Colors.transparent, width: 2))),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: x.$2),
              if (x.$3 != null) TextSpan(text: ' ${x.$3}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: pal.muted)),
            ]),
            maxLines: 1,
            softWrap: false,
            style: label.copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? pal.accent : pal.muted),
          ),
        ),
      );
      return expand ? Expanded(child: w) : w;
    }

    final bar = LayoutBuilder(builder: (context, box) {
      final need = tabs.fold<double>(0, (a, x) {
        final tp = TextPainter(text: TextSpan(text: '${x.$2}${x.$3 != null ? ' ${x.$3}' : ''}', style: label), textDirection: TextDirection.ltr, maxLines: 1, textScaler: scale)..layout();
        return a + tp.width + 24;
      });
      final inner = box.maxWidth - 32;
      return Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
        child: need <= inner
            ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [for (final x in tabs) tab(x, expand: true)]))
            : FadeRow(gap: 4, padding: const EdgeInsets.symmetric(horizontal: 16), children: [for (final x in tabs) tab(x)]),
      );
    });
    return bleed ? _bleed(bar) : bar;
  }
}

/// Ряд плашек с прокруткой вбок (фильтры, языки): у края, за которым есть ещё плашки, — плавное затухание вместо обрезки
class FadeRow extends StatefulWidget {
  const FadeRow({super.key, required this.children, this.gap = 6, this.padding = EdgeInsets.zero, this.bleed = false});
  final List<Widget> children;
  final double gap;
  final EdgeInsets padding;
  final bool bleed; // ряд внутри полей окна — прокрутка от края до края (поля — отступом внутри ряда)
  @override
  State<FadeRow> createState() => _FadeRowState();
}

class _FadeRowState extends State<FadeRow> {
  final _c = ScrollController();
  bool _left = false, _right = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_c.hasClients) return;
    final p = _c.position;
    final l = p.pixels > 1, r = p.pixels < p.maxScrollExtent - 1;
    if (l != _left || r != _right) {
      setState(() {
        _left = l;
        _right = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.bleed ? widget.padding.add(const EdgeInsets.symmetric(horizontal: 16)) : widget.padding;
    final row = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _update());
        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) {
          final f = r.width > 56 ? 28 / r.width : 0.0; // ширина затухания 28 px; у узкого (или ещё не измеренного) — без него
          return LinearGradient(
            colors: [_left && f > 0 ? Colors.transparent : Colors.black, Colors.black, Colors.black, _right && f > 0 ? Colors.transparent : Colors.black],
            stops: [0, f, 1 - f, 1],
          ).createShader(r);
        },
        child: SingleChildScrollView(
          controller: _c,
          scrollDirection: Axis.horizontal,
          padding: pad,
          child: Row(children: [
            for (final (i, c) in widget.children.indexed) ...[if (i > 0) SizedBox(width: widget.gap), c],
          ]),
        ),
      ),
    );
    return widget.bleed ? _bleed(row) : row;
  }
}

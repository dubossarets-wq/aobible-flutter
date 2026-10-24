// Общие элементы интерфейса — один в один с веб-версией (E:\AO Bible\src\styles.css, src/components/ui.jsx,
// BottomSheet.jsx). Значки — Lucide (как lucide-react в веб-версии): LucideIcons.<имя в camelCase>.
// Базовый размер шрифта интерфейса — 15 px (body в веб-версии), 1rem = 16 px.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/settings.dart';

export 'package:lucide_icons_flutter/lucide_icons.dart' show LucideIcons;

/// color-mix(in srgb, a p%, b)
Color mix(Color a, double p, Color b) => Color.lerp(b, a, p)!;

const double kRadius = 12; // --radius

/// Палитра текущей темы (со своими цветами)
Palette paletteOf(WidgetRef ref) => ref.watch(settingsProvider.select((s) => s.palette));

// --- Нижнее окно (BottomSheet.jsx): скруглённый верх, полоска, заголовок, крестик ------------------------

/// Открыть окно: initial — доля высоты экрана (как initial={1|2} в веб-версии: 0.5 или 0.92)
Future<T?> showAobSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context) builder,
  double initial = 0.92,
  bool page = false,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (c) => FractionallySizedBox(heightFactor: page ? 1 : initial, child: builder(c)),
    );

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
    return Material(
      color: pal.panel,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadius + 6)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Container(width: 40, height: 5, decoration: BoxDecoration(color: mix(pal.muted, 0.45, pal.panel), borderRadius: BorderRadius.circular(3))),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(onBack != null ? 6 : 16, 0, 10, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(children: [
            if (onBack != null) IconBtn(icon: LucideIcons.chevronLeft, onTap: onBack!),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: 18.4, fontWeight: FontWeight.w700, color: pal.text)),
                if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.muted)),
              ]),
            ),
            ...actions,
            IconBtn(icon: LucideIcons.x, onTap: onClose ?? () => Navigator.of(context).maybePop()),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 15, color: pal.text)),
              if (hint != null) Text(hint!, style: TextStyle(fontSize: 12.5, color: pal.muted)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(kRadius * 0.75)),
      child: Row(children: [
        for (final (v, label) in options)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: const Cubic(.3, 1.25, .5, 1),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: v == value ? pal.panel : Colors.transparent,
                  borderRadius: BorderRadius.circular(kRadius * 0.6),
                  boxShadow: v == value ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))] : null,
                ),
                alignment: Alignment.center,
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: v == value ? FontWeight.w600 : FontWeight.w400, color: v == value ? pal.accent : pal.text)),
              ),
            ),
          ),
      ]),
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

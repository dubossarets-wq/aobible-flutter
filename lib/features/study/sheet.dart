// Нижнее окно (как BottomSheet.jsx веб-версии) и общие мелкие элементы окон «изучения»: вкладки, чипы, подписи.
// Окно выезжает снизу, высота меняется перетаскиванием шапки (половина → до верхней панели → почти весь экран),
// закрывается свайпом вниз, крестиком или нажатием на фон. «Назад» — к окну, из которого открыли (оно лежит под этим).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../shell/fonts.dart' show readerTextStyle;
import '../../ui/kit.dart';
import 'study_data.dart';

const sheetRoute = 'study-sheet';

enum SheetSize { half, normal, tall, full }

/// Открыть окно. [child] обычно возвращает [SheetScaffold]
Future<void> showSheet(BuildContext context, Widget child, {SheetSize size = SheetSize.normal}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.black.withValues(alpha: 0.32), // как в showAobSheet
    routeSettings: const RouteSettings(name: sheetRoute),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, a, secondary, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn)),
      child: child,
    ),
    pageBuilder: (context, a, secondary) => _Frame(size: size, child: child),
  );
}

/// Закрыть все окна «изучения» (крестик, фон): подокно, открытое из другого, закрывается вместе с ним
// closeAllSheets — общий, из kit.dart: закрывает все окна, в том числе открытые не изучением

class _Frame extends StatefulWidget {
  const _Frame({required this.size, required this.child});
  final SheetSize size;
  final Widget child;
  @override
  State<_Frame> createState() => _FrameState();
}

class _FrameState extends State<_Frame> {
  late double _h = switch (widget.size) { SheetSize.half => 0.5, SheetSize.normal => 0.86, SheetSize.tall => 0.92, SheetSize.full => 1.0 };
  bool get _full => widget.size == SheetSize.full;
  double _h0 = 0;
  double _drag = 0;
  bool _dragging = false;

  static const _snaps = [0.5, 0.86, 0.92];

  void dragStart() {
    _h0 = _h;
    _drag = 0;
    setState(() => _dragging = true);
  }

  void dragUpdate(double dy, double vh) {
    _drag -= dy; // вверх — положительно
    setState(() => _h = (_h0 + _drag / vh).clamp(0.12, _full ? 1.0 : 0.96));
  }

  void dragEnd(double velocityY, BuildContext ctx) {
    final v = -velocityY / 1000; // пикселей в миллисекунду, вверх — положительно
    setState(() => _dragging = false);
    // Потянули вниз — окно закрывается полностью; вверх — раскрывается
    if (_drag < -60 || v < -0.4 || _h < 0.28) return closeAllSheets(ctx);
    if (_full) return setState(() => _h = 1.0);
    final cands = _snaps.where((x) => x >= _h0 - 0.001);
    setState(() => _h = v > 1 ? _snaps.last : cands.reduce((a, b) => (b - _h).abs() < (a - _h).abs() ? b : a));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final avail = mq.size.height - mq.padding.top - 6;
    final height = (_h * mq.size.height).clamp(0.0, avail);
    return Stack(children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => closeAllSheets(context))),
      Positioned(
        left: 0,
        right: 0,
        bottom: mq.viewInsets.bottom,
        child: AnimatedContainer(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: height,
          child: widget.child,
        ),
      ),
    ]);
  }
}

class SheetScaffold extends ConsumerWidget {
  const SheetScaffold({super.key, required this.title, this.subtitle, this.onBack, this.onClose, this.headerExtra = const [], required this.body, this.footer});
  final VoidCallback? onClose; // «×»: по умолчанию закрывает все окна; задан — своё (вернуться в окно, откуда открыли)
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> headerExtra;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final frame = context.findAncestorStateOfType<_FrameState>();
    final vh = MediaQuery.of(context).size.height;
    // Шапка — как у AobSheet из kit.dart (BottomSheet.jsx), но с перетаскиванием высоты и общим закрытием окон
    final drag = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => frame?.dragStart(),
      onVerticalDragUpdate: (d) => frame?.dragUpdate(d.delta.dy, vh),
      onVerticalDragEnd: (d) => frame?.dragEnd(d.velocity.pixelsPerSecond.dy, context),
      onVerticalDragCancel: () => frame?.dragEnd(0, context),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(top: 7, bottom: 1), // как у AobSheet: шапка ниже
          child: Container(width: 40, height: 5, decoration: BoxDecoration(color: mix(pal.muted, 0.45, pal.panel), borderRadius: BorderRadius.circular(3))),
        ),
        Container(
          // как шапка AobSheet: стрелка, заголовок и крестик на одной линии
          padding: EdgeInsets.fromLTRB(onBack != null ? 6 : 16, 2, 10, 6),
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(children: [
            if (onBack != null) IconBtn(icon: LucideIcons.chevronLeft, onTap: onBack, tooltip: t('Назад')),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                    style: TextStyle(fontSize: 18.4, height: 1.2, fontWeight: FontWeight.w700, color: pal.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                        style: TextStyle(fontSize: 13, height: 1.2, color: pal.muted)),
                  ),
              ]),
            ),
            ...headerExtra,
            IconBtn(icon: LucideIcons.x, onTap: onClose ?? () => closeAllSheets(context), tooltip: t('Закрыть')),
          ]),
        ),
      ]),
    );
    return Material(
      color: pal.panel,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadius + 6)),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: pal.text, fontSize: 15),
        child: Column(children: [
          drag,
          // вкладки лежат поверх окна: внизу тела (или под нижней панелью) — отступ под них
          Expanded(child: tabInsetBuilder(context, (inset) => footer != null ? body : MediaQuery(data: MediaQuery.of(context).copyWith(padding: MediaQuery.paddingOf(context).copyWith(bottom: MediaQuery.paddingOf(context).bottom + inset)), child: body))),
          if (footer != null) Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))), child: footer),
          if (footer != null) tabInsetBuilder(context, (inset) => SizedBox(height: inset)),
        ]),
      ),
    );
  }
}

/// Прокручиваемое тело окна с отступами как у .sheet-body
class SheetList extends StatelessWidget {
  const SheetList({super.key, required this.children, this.gap = 12, this.controller});
  final List<Widget> children;
  final double gap;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottom),
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
      ],
    );
  }
}

Palette _pal(WidgetRef ref) => ref.watch(settingsProvider.select((s) => s.palette));

Color tint(Color c, Color over, double a) => Color.alphaBlend(c.withValues(alpha: a), over);

// --- Мелкие элементы --------------------------------------------------------------------------

class Loading extends ConsumerWidget {
  const Loading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Spinner(size: 20, color: pal.muted),
        const SizedBox(width: 10),
        Flexible(child: Text(text, style: TextStyle(color: pal.muted, fontSize: 15.2))),
      ]),
    );
  }
}

class Empty extends ConsumerWidget {
  const Empty({super.key, required this.icon, required this.title, this.child});
  final IconData icon;
  final String title;
  final Widget? child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(children: [
        Icon(icon, size: 28, color: pal.muted),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
        if (child != null) ...[const SizedBox(height: 8), DefaultTextStyle.merge(textAlign: TextAlign.center, style: TextStyle(color: pal.muted, fontSize: 14.4, height: 1.45), child: child!)],
      ]),
    );
  }
}

/// Заголовок раздела внутри статьи (h4 веб-версии)
class H4 extends ConsumerWidget {
  const H4(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 13, color: pal.muted), const SizedBox(width: 6)],
        Expanded(child: Text(text, style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w600, color: pal.muted))),
      ]),
    );
  }
}

/// .chip — общий AobChip из kit.dart
class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, this.on = false, this.count, this.onTap, this.ghost = false});
  final String label;
  final bool on;
  final int? count;
  final VoidCallback? onTap;
  final bool ghost;
  @override
  Widget build(BuildContext context) => AobChip(label: label, on: on, count: count, onTap: onTap, ghost: ghost);
}

/// .chips.filter-chips: одна строка чипов с горизонтальной прокруткой, от края до края окна (margin 0 -16px)
class FilterChips extends StatelessWidget {
  const FilterChips(this.children, {super.key});
  final List<Widget> children;
  @override
  // от края до края окна; у края, за которым есть ещё плашки, — затухание (FadeRow из kit.dart)
  // Ряд стоит внутри вертикального списка (высота не ограничена): kit-овский bleed там ломается (OverflowBox
  // становится бесконечной высоты), поэтому расширяем сами — OverflowBox по размеру ребёнка
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => OverflowBox(
          fit: OverflowBoxFit.deferToChild,
          minWidth: box.maxWidth + 32,
          maxWidth: box.maxWidth + 32,
          child: FadeRow(padding: const EdgeInsets.fromLTRB(16, 0, 16, 2), children: children),
        ),
      );
}

class ChipWrap extends StatelessWidget {
  const ChipWrap(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: children);
}

/// Вкладки: подчёркнутые (словари) или «таблетки» (sub — статьи одного словаря)
class TabsRow extends ConsumerWidget {
  const TabsRow({super.key, required this.labels, required this.index, required this.onTap, this.sub = false});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;
  final bool sub;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: sub ? null : BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            sub
                ? Padding(
                    padding: const EdgeInsets.only(right: 4),
                    // выбор — плавно: фон, рамка и надпись перетекают
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: i == index ? 1.0 : 0.0),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.fastOutSlowIn,
                      builder: (context, v, _) => Material(
                        animationDuration: Duration.zero,
                        color: tint(pal.accent, pal.panel, 0.1).withValues(alpha: v),
                        shape: StadiumBorder(side: BorderSide(color: Color.lerp(pal.line, pal.accent, v)!)),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: () => onTap(i),
                          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5), child: Text(labels[i], style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w500, color: Color.lerp(pal.muted, pal.accent, v)))),
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 4),
                    child: InkWell(
                      onTap: () => onTap(i),
                      // смена вкладки — плавно: линия и цвет надписи перетекают
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: i == index ? 1.0 : 0.0),
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.fastOutSlowIn,
                        builder: (context, v, _) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.accent.withValues(alpha: v), width: 2))),
                          child: Text(labels[i], style: TextStyle(fontWeight: FontWeight.w500, color: Color.lerp(pal.muted, pal.accent, v))),
                        ),
                      ),
                    ),
                  ),
        ]),
      ),
    );
  }
}

class WarnBox extends ConsumerWidget {
  const WarnBox({super.key, required this.child, this.icon = true});
  final Widget child;
  final bool icon;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: tint(const Color(0xFFD99A2B), pal.panel, 0.15), borderRadius: BorderRadius.circular(kRadius * 0.75)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon) const Padding(padding: EdgeInsets.only(top: 2), child: Icon(LucideIcons.triangleAlert, size: 16, color: Color(0xFFC0841F))),
        if (icon) const SizedBox(width: 8),
        Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 14.1, height: 1.45), child: child)),
      ]),
    );
  }
}

class SourceNote extends ConsumerWidget {
  const SourceNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
      child: Text(text, style: TextStyle(color: pal.muted, fontSize: 12.8)),
    );
  }
}

/// .btn — общий AobButton из kit.dart
class BigButton extends StatelessWidget {
  const BigButton(this.label, {super.key, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => AobButton(label: label, icon: icon, onTap: onTap, wide: true);
}

/// .link-inline: кнопка-ссылка в тексте — цвет акцента, подчёркнута
class LinkButton extends ConsumerWidget {
  const LinkButton(this.label, this.onTap, {super.key});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(label, style: TextStyle(color: pal.accent, decoration: TextDecoration.underline, decorationColor: pal.accent)),
    );
  }
}

/// Текст со ссылками: фрагменты с onTap подчёркнуты цветом акцента
class LinkSpans extends ConsumerStatefulWidget {
  const LinkSpans({super.key, required this.parts, this.style});
  final List<(String, VoidCallback?)> parts;
  final TextStyle? style;
  @override
  ConsumerState<LinkSpans> createState() => _LinkSpansState();
}

class _LinkSpansState extends ConsumerState<LinkSpans> {
  final _rec = <TapGestureRecognizer>[];

  void _free() {
    for (final r in _rec) {
      r.dispose();
    }
    _rec.clear();
  }

  @override
  void dispose() {
    _free();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = _pal(ref);
    _free();
    return Text.rich(
      TextSpan(children: [
        for (final (text, tap) in widget.parts)
          if (tap == null)
            TextSpan(text: text)
          else
            TextSpan(
              text: text,
              style: TextStyle(color: pal.accent, decoration: TextDecoration.underline, decorationColor: pal.accent),
              recognizer: (TapGestureRecognizer()..onTap = tap).also(_rec.add),
            ),
      ]),
      style: widget.style,
    );
  }
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

final _refRe = RegExp(r'((?:[1-4]\s?)?[А-ЯЁA-Z][а-яёa-z]{1,14}\.?)\s?(\d{1,3})(?:\s?[:,]\s?(\d{1,3})(?:\s?[-–]\s?(\d{1,3}))?)?');
final _contRe = RegExp(r'^(\s*[;,]\s*)(\d{1,3})(?:\s?:\s?(\d{1,3}))(?:\s?[-–]\s?(\d{1,3}))?');

/// Ссылки на стихи в обычном тексте: «Ин 3:16», «1 Кор 13:4–7», «Быт. 23:19; 49:29–31» (во второй ссылке книга та же)
List<(String, VerseRef?)> splitRefs(String text) {
  final out = <(String, VerseRef?)>[];
  var last = 0;
  var from = 0;
  while (from <= text.length) {
    final m = _refRe.allMatches(text, from).firstOrNull;
    if (m == null) break;
    final b = m.group(1)!;
    final book = Books.instance.findBookId(b);
    // Ссылка на целую главу — только для сокращений («Пс 22», «Мф. 5»), не для обычных слов
    if (book == null || (m.group(3) == null && !b.endsWith('.') && b.replaceAll(RegExp(r'\s'), '').length > 5)) {
      from = m.end;
      continue;
    }
    if (m.start > last) out.add((text.substring(last, m.start), null));
    out.add((m.group(0)!, VerseRef(book, int.parse(m.group(2)!), m.group(3) != null ? int.parse(m.group(3)!) : 1)));
    last = m.end;
    // «; 49:29–31» — та же книга
    while (true) {
      final c = _contRe.firstMatch(text.substring(last));
      if (c == null) break;
      out.add((c.group(1)!, null));
      out.add((c.group(0)!.substring(c.group(1)!.length), VerseRef(book, int.parse(c.group(2)!), int.parse(c.group(3)!))));
      last += c.group(0)!.length;
    }
    from = last;
  }
  if (last < text.length) out.add((text.substring(last), null));
  return out;
}

/// Открыть место: во второй панели (из первой) или в самой панели (из второй)
typedef OpenRef = void Function(VerseRef r);

/// Текст, в котором ссылки на стихи — кнопки
class LinkedText extends StatelessWidget {
  const LinkedText({super.key, required this.text, required this.onOpen, this.style});
  final String text;
  final OpenRef onOpen;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => LinkSpans(parts: [for (final (s, r) in splitRefs(text)) (s, r == null ? null : () => onOpen(r))], style: style);
}

String refLabel(VerseRef r) => fmtRef(r);

/// Цитата стиха над списком (blockquote.xref-source веб-версии)
class QuoteBox extends ConsumerWidget {
  const QuoteBox(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = _pal(ref);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: tint(pal.accent, pal.panel, 0.06), border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius * 0.6)),
      // .xref-source / .guide-card: шрифт читалки (--font-text)
      child: Text(text, style: readerTextStyle(ref.watch(settingsProvider), size: 15, weight: 400).copyWith(height: 1.5)),
    );
  }
}

/// Панель, в которой открыт перевод с таким модулем (окна из Hub не получают номер панели)
int paneOf(List<dynamic> panes, String moduleId) {
  final i = panes.indexWhere((p) => p.moduleId == moduleId);
  return i < 0 ? 0 : i;
}

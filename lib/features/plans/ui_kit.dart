// Кирпичики окон планов и проповедей, которых нет в lib/ui/kit.dart: кольцо прогресса, плашка с отметкой «прочитано»,
// «корзина с подтверждением», сообщения (.toast) и поле ввода. Всё остальное — из kit.dart (AobSheet, AobButton, AobChip…).
// Размеры и цвета — по styles.css веб-версии; значки — Lucide.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';

export '../../ui/kit.dart';

const kOk = Color(0xFF2F9A5F); // .plan-ok, .chip.done svg
const kOkSoft = Color(0xFF3AA66B); // фон и рамка отмеченной плашки
const kDangerLink = Color(0xFFC0392B); // .link-btn.danger

/// Окно почти на весь экран (initial=2 в веб-версии); page — отдельная страница (variant="page").
/// Свой ScaffoldMessenger: сообщения («Отменить», «Засчитано…») показываются внутри окна, а не под ним.
Future<T?> showPage<T>(BuildContext context, WidgetBuilder builder, {double height = 0.92, bool page = false, String? tab}) => showAobSheet<T>(
      context,
      initial: height,
      page: page,
      tab: tab,
      builder: (_) => ScaffoldMessenger(child: Scaffold(backgroundColor: Colors.transparent, body: Builder(builder: builder))),
    );

Palette _palOf(BuildContext c) => ProviderScope.containerOf(c).read(settingsProvider).palette;

// --- Сообщения (.toast): тёмная «таблетка» с необязательной кнопкой справа -------------------------------

void _toast(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction, bool error = false}) {
  if (!context.mounted) return;
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  final pal = _palOf(context);
  m.hideCurrentSnackBar();
  final bg = error ? mix(const Color(0xFFB4412F), 0.88, Colors.transparent) : mix(pal.bar, 0.92, Colors.transparent);
  final fg = error ? Colors.white : pal.barText;
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: bg,
    elevation: 6,
    // в окне (у него свой Scaffold на весь экран) — над плавающим нижним меню, оно лежит поверх окон;
    // на главном экране место под меню уже оставлено
    margin: EdgeInsets.fromLTRB(16, 0, 16, 20 + (identical(m, Hub.messengerKey.currentState) ? 0 : tabBarInset.value)),
    padding: EdgeInsets.fromLTRB(16, actionLabel != null ? 6 : 10, actionLabel != null ? 6 : 16, actionLabel != null ? 6 : 10),
    // 22 — в одну строку это «таблетка», а в несколько строк — скруглённый прямоугольник, а не овал
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(error ? 14 : 22)),
    duration: Duration(seconds: actionLabel != null ? 6 : 4),
    content: Row(children: [
      Expanded(child: Text(text, textAlign: actionLabel != null ? TextAlign.left : TextAlign.center, style: TextStyle(fontSize: 14.4, color: fg))),
      if (actionLabel != null) ...[
        const SizedBox(width: 12),
        Material(
          color: mix(fg, 0.16, Colors.transparent),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              m.hideCurrentSnackBar();
              onAction?.call();
            },
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Text(actionLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: fg))),
          ),
        ),
      ],
    ]),
  ));
}

/// Сообщение с «Отменить»
void showUndo(BuildContext context, String text, VoidCallback onUndo) => _toast(context, text, actionLabel: t('Отменить'), onAction: onUndo);

void toast(BuildContext context, String text) => _toast(context, text);

// --- Кольцо прогресса (.ring) ----------------------------------------------------------------------------

/// Кольцо прогресса: доля 0…1, внутри — подпись
class Ring extends StatelessWidget {
  const Ring({super.key, required this.value, required this.color, required this.track, this.size = 64, this.stroke = 7, this.child});
  final double value;
  final Color color, track;
  final double size, stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _RingPainter(value.clamp(0, 1).toDouble(), color, track, stroke), child: Center(child: child)),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: (s.width - stroke) / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = track);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}

// --- Плашка (.chip) с отметкой «прочитано» и подписью -----------------------------------------------------

/// Обычная и выбранная плашки — AobChip из kit.dart; с отметкой (.chip.done) и подписью (small) — те же размеры
class ChipBtn extends ConsumerWidget {
  const ChipBtn({super.key, required this.label, this.onTap, this.on = false, this.done = false, this.sub});
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool on, done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!done && sub == null) return AobChip(label: label, onTap: onTap, on: on);
    final pal = paletteOf(ref);
    return Material(
      color: done ? mix(kOkSoft, 0.1, pal.bg) : pal.bg,
      shape: StadiumBorder(side: BorderSide(color: done ? mix(kOkSoft, 0.35, pal.line) : pal.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (done) ...[const Icon(LucideIcons.check, size: 12, color: kOk), const SizedBox(width: 5)],
            Text(label, style: TextStyle(fontSize: 13.8, color: done ? pal.muted : pal.text)),
            if (sub != null) ...[const SizedBox(width: 5), Text(sub!, style: TextStyle(fontSize: 12, color: pal.muted))],
          ]),
        ),
      ),
    );
  }
}

// --- Подтверждение удаления (ConfirmButton) ---------------------------------------------------------------

/// Корзина с подтверждением: первое нажатие превращает кнопку в красную «Удалить», второе — подтверждает.
/// Если не нажать — через 3 секунды возвращается обратно.
class ConfirmIcon extends ConsumerStatefulWidget {
  const ConfirmIcon({super.key, this.icon, this.linkText, required this.confirmText, required this.onConfirm, this.tooltip, this.size = 20});
  final IconData? icon; // значок-корзина…
  final String? linkText; // …или ссылка-текст («удалить проповедь»)
  final String confirmText;
  final String? tooltip;
  final VoidCallback onConfirm;
  final double size;

  @override
  ConsumerState<ConfirmIcon> createState() => _ConfirmIconState();
}

class _ConfirmIconState extends ConsumerState<ConfirmIcon> {
  bool _ask = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    setState(() => _ask = true);
    _timer = Timer(const Duration(seconds: 3), () => mounted ? setState(() => _ask = false) : null);
  }

  @override
  Widget build(BuildContext context) {
    if (_ask) {
      return AobButton(
        label: widget.confirmText,
        kind: BtnKind.danger,
        small: true,
        onTap: () {
          _timer?.cancel();
          setState(() => _ask = false);
          widget.onConfirm();
        },
      );
    }
    if (widget.linkText != null) {
      return GestureDetector(
        onTap: _arm,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(widget.linkText!, style: const TextStyle(color: kDangerLink, decoration: TextDecoration.underline, decorationColor: kDangerLink, fontSize: 13.1)),
        ),
      );
    }
    return IconBtn(icon: widget.icon!, subtle: true, size: widget.size, tooltip: widget.tooltip, onTap: _arm);
  }
}

// --- Поле ввода (input в веб-версии: скругление 9, рамка line, фон bg, шрифт 16) --------------------------

class PlainInput extends ConsumerWidget {
  const PlainInput({super.key, required this.controller, this.hint, this.autofocus = false, this.onSubmitted, this.onChanged, this.textAlign = TextAlign.start, this.keyboardType, this.style, this.height});
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AobInput(
        controller: controller,
        hint: hint,
        icon: null,
        clearable: false,
        autofocus: autofocus,
        textAlign: textAlign,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: style,
        height: height ?? 44,
      );
}

/// «!» в кружке рядом с названием (.hint-btn): по нажатию — пояснение облачком у значка (Hint), а не
/// сообщением внизу — длинный текст в «таблетке» сообщения становился овалом и обрезался
class HintBtn extends StatelessWidget {
  const HintBtn(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Hint(text);
}

/// --danger веб-версии: тёмная и светлая темы разные
Color dangerOf(Palette pal) => pal.dark ? const Color(0xFFEF8A78) : const Color(0xFFB4412F);
/// --ok веб-версии: «прочитано», «установлено» (в тёмных темах светлее)
Color okOf(Palette pal) => pal.dark ? const Color(0xFF7CC68A) : const Color(0xFF2F6339);
/// --late веб-версии: пропущенный день плана (в тёмных темах светлее)
Color lateOf(Palette pal) => pal.dark ? const Color(0xFFF0A868) : const Color(0xFFC2621F);

/// Пунктирная линия (border-top: 1px dashed)
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(height: 1, width: double.infinity, child: CustomPaint(painter: _DashPainter(color)));
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = color..strokeWidth = 1;
    for (var x = 0.0; x < s.width; x += 6) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + 3, s.width), 0.5), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

/// Кнопка «Начать» с вращающимся значком, пока идёт работа (Loader2 spin внутри .btn.primary);
/// AobButton принимает только значок, поэтому вид кнопки повторён здесь
class BusyButton extends ConsumerWidget {
  const BusyButton({super.key, required this.label, this.wide = true});
  final String label;
  final bool wide;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return Opacity(
      opacity: 0.5,
      child: Material(
        color: pal.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: pal.accent)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            Spinner(size: 16, color: pal.onAccent),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.2, fontWeight: FontWeight.w500, color: pal.onAccent))),
          ]),
        ),
      ),
    );
  }
}

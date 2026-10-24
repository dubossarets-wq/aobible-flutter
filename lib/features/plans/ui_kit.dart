// Общие кирпичики окон планов и проповедей: нижнее окно, шапка, кнопки, кольцо прогресса, «корзина с подтверждением».
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';

/// Окно почти на весь экран, как «Перейти» и поиск
Future<T?> showPage<T>(BuildContext context, WidgetBuilder builder, {double height = 0.92}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // свой ScaffoldMessenger: сообщения («Отменить», «Засчитано…») показываются внутри окна, а не под ним
      builder: (c) => FractionallySizedBox(heightFactor: height, child: ScaffoldMessenger(child: Scaffold(backgroundColor: Colors.transparent, body: Builder(builder: builder)))),
    );

/// Шапка окна: название, подпись, «назад» (если есть) и закрытие
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.pal, required this.title, this.subtitle, this.onBack, required this.child, this.onClose, this.trailing = const []});
  final Palette pal;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final List<Widget> trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: pal.panel,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 4, 4),
            child: Row(children: [
              if (onBack != null) IconButton(tooltip: t('Назад'), icon: Icon(Icons.arrow_back, color: pal.text), onPressed: onBack) else const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.text)),
                  if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.muted)),
                ]),
              ),
              ...trailing,
              IconButton(tooltip: t('Закрыть'), icon: Icon(Icons.close, color: pal.text), onPressed: onClose ?? () => Navigator.of(context).maybePop()),
            ]),
          ),
          Divider(height: 1, color: pal.line),
          Expanded(child: child),
        ]),
      );
}

/// Кнопка-таблетка: главная (акцентная), обычная, маленькая
class Pill extends StatelessWidget {
  const Pill({super.key, required this.pal, required this.label, this.icon, this.onTap, this.primary = false, this.small = false, this.expand = false});
  final Palette pal;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, small, expand;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? pal.onAccent : pal.text;
    final off = onTap == null;
    return Opacity(
      opacity: off ? 0.5 : 1,
      child: Material(
        color: primary ? pal.accent : pal.bg,
        shape: StadiumBorder(side: primary ? BorderSide.none : BorderSide(color: pal.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 8 : 12),
            child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, size: small ? 16 : 18, color: fg), const SizedBox(width: 6)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: small ? 13.5 : 15, color: fg))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Маленькая «чипса» (отрывок плана, срок, быстрый выбор)
class ChipBtn extends StatelessWidget {
  const ChipBtn({super.key, required this.pal, required this.label, this.onTap, this.on = false, this.done = false, this.sub});
  final Palette pal;
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool on, done;

  @override
  Widget build(BuildContext context) {
    final green = const Color(0xFF3AA66B);
    final bg = on ? pal.accent : done ? Color.alphaBlend(green.withValues(alpha: 0.1), pal.bg) : pal.bg;
    final fg = on ? pal.onAccent : done ? pal.muted : pal.text;
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: on ? pal.accent : done ? green.withValues(alpha: 0.35) : pal.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (done) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.check, size: 14, color: Color(0xFF2F9A5F))),
            Text(label, style: TextStyle(fontSize: 13.5, color: fg)),
            if (sub != null) Padding(padding: const EdgeInsets.only(left: 5), child: Text(sub!, style: TextStyle(fontSize: 11.5, color: pal.muted))),
          ]),
        ),
      ),
    );
  }
}

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

/// Корзина с подтверждением: первое нажатие превращает кнопку в красную «Удалить» (справа), второе — подтверждает.
/// Если не нажать — через 3 секунды возвращается обратно.
class ConfirmIcon extends StatefulWidget {
  const ConfirmIcon({super.key, required this.pal, this.icon, this.linkText, required this.confirmText, required this.onConfirm, this.tooltip, this.size = 20});
  final Palette pal;
  final IconData? icon; // значок-корзина…
  final String? linkText; // …или ссылка-текст («удалить проповедь»)
  final String confirmText;
  final String? tooltip;
  final VoidCallback onConfirm;
  final double size;

  @override
  State<ConfirmIcon> createState() => _ConfirmIconState();
}

class _ConfirmIconState extends State<ConfirmIcon> {
  bool _ask = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ask) {
      return Material(
        color: const Color(0xFFD64545),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            _timer?.cancel();
            setState(() => _ask = false);
            widget.onConfirm();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(widget.confirmText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      );
    }
    void ask() {
      setState(() => _ask = true);
      _timer = Timer(const Duration(seconds: 3), () => mounted ? setState(() => _ask = false) : null);
    }

    if (widget.linkText != null) {
      return GestureDetector(
        onTap: ask,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(widget.linkText!, style: const TextStyle(color: Color(0xFFD64545), decoration: TextDecoration.underline, fontSize: 13))),
      );
    }
    return IconButton(
      tooltip: widget.tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(widget.icon, size: widget.size, color: widget.pal.muted),
      onPressed: ask,
    );
  }
}

/// Сообщение с «Отменить»
void showUndo(BuildContext context, String text, VoidCallback onUndo) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6), action: SnackBarAction(label: t('Отменить'), onPressed: onUndo)));
}

void toast(BuildContext context, String text) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(text)));
}

Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

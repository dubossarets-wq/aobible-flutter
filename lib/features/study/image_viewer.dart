// Просмотр иллюстрации к стиху во весь экран (ImageViewer.jsx): увеличение двумя пальцами и нажатием,
// перетаскивание увеличенной картинки, переключение между картинками стиха, потянуть вниз — закрыть,
// подпись с автором и лицензией. Картинки не хранятся в приложении — загружаются с Wikimedia Commons.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../ui/kit.dart' show LucideIcons, Spinner;
import 'study_data.dart';
import '../../ui/ios_style.dart';

const _maxScale = 5.0;
const _tapScale = 2.5;

Future<void> openImageViewer(BuildContext context, {required VerseRef at, required List<Map<String, dynamic>> items}) {
  if (items.isEmpty) return Future.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (c, a, s, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (c, a, s) => _Viewer(at: at, items: items),
  );
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.at, required this.items});
  final VerseRef at;
  final List<Map<String, dynamic>> items;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  int _i = 0;
  double _fade = 0; // фон бледнеет, пока картинку тянут вниз

  void _go(int d) => setState(() => _i = (_i + d).clamp(0, widget.items.length - 1));

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final item = items[_i];
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    const fg = Color(0xFFF2EFE9);
    final author = [item['author'], item['year']].where((x) => x != null && x.toString().isNotEmpty).join(', ');
    final license = item['license'];
    final src = item['src'] as String?;
    return Material(
      color: Color.fromRGBO(11, 11, 12, _fade > 0 ? math.max(0.35, 1 - _fade / 400) : 1),
      child: DefaultTextStyle(
        style: const TextStyle(color: fg, fontSize: 16),
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, top + 6, 8, 6),
            child: Row(children: [
              Expanded(child: Text(fmtRef(widget.at), style: const TextStyle(fontWeight: FontWeight.w700))),
              if (items.length > 1) Text(t('{n} из {total}', {'n': '${_i + 1}', 'total': '${items.length}'}), style: const TextStyle(fontSize: 13.6, color: Color(0xBFF2EFE9))),
              const SizedBox(width: 6),
              _RoundBtn(icon: LucideIcons.x, label: t('Закрыть'), onTap: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: Stack(children: [
              _Zoomable(key: ValueKey(item['img']), item: item, onSwipe: _go, onPull: (y) => setState(() => _fade = y), onClose: () => Navigator.pop(context)),
              if (items.length > 1) ...[
                Positioned(left: 8, top: 0, bottom: 0, child: Center(child: _RoundBtn(icon: LucideIcons.chevronLeft, label: t('Предыдущая картинка'), onTap: _i == 0 ? null : () => _go(-1)))),
                Positioned(right: 8, top: 0, bottom: 0, child: Center(child: _RoundBtn(icon: LucideIcons.chevronRight, label: t('Следующая картинка'), onTap: _i == items.length - 1 ? null : () => _go(1)))),
              ],
            ]),
          ),
          Container(
            width: double.infinity,
            color: const Color(0x0AFFFFFF),
            padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (item['title'] != null) Text('${item['title']}', style: const TextStyle(fontSize: 14.4, fontWeight: FontWeight.w700, height: 1.4)),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: author + (license != null ? ' · $license' : '')),
                  if (src != null) ...[
                    const TextSpan(text: ' · '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: GestureDetector(
                        onTap: () => launchUrl(Uri.parse(src), mode: LaunchMode.externalApplication),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(t('источник'), style: const TextStyle(fontSize: 13, decoration: TextDecoration.underline)), const SizedBox(width: 3), AIcon(ico(LucideIcons.externalLink), size: 12)]),
                      ),
                    ),
                  ],
                ]),
                style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xCCF2EFE9)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.3 : 1,
        child: Material(
          color: const Color(0x14FFFFFF),
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Tooltip(message: label, child: SizedBox(width: 44, height: 44, child: AIcon(ico(icon), size: 24, color: const Color(0xFFF2EFE9))))),
        ),
      );
}

/// Картинка с жестами: два пальца — масштаб, один палец по увеличенной — сдвиг, по обычной вниз — закрыть,
/// влево/вправо — соседняя картинка, короткое нажатие — увеличить в этом месте (повторное — вернуть).
/// События сырые (Listener), без арены жестов — как pointer-события веб-версии.
class _Zoomable extends StatefulWidget {
  const _Zoomable({super.key, required this.item, required this.onSwipe, required this.onPull, required this.onClose});
  final Map<String, dynamic> item;
  final void Function(int) onSwipe;
  final void Function(double) onPull;
  final VoidCallback onClose;
  @override
  State<_Zoomable> createState() => _ZoomableState();
}

class _G {
  _G(this.list, this.s, this.x, this.y, this.at);
  final List<Offset> list;
  final double s, x, y;
  final int at;
}

class _ZoomableState extends State<_Zoomable> {
  final _box = GlobalKey();
  double _s = 1, _x = 0, _y = 0;
  double _pull = 0;
  final _pts = <int, Offset>{};
  _G? _g;
  ({Offset p, int at})? _tap;

  Size get _size => (_box.currentContext?.findRenderObject() as RenderBox?)?.size ?? Size.zero;
  Offset get _origin => (_box.currentContext?.findRenderObject() as RenderBox?)?.localToGlobal(Offset.zero) ?? Offset.zero;

  // Не даём увести картинку за край, когда она увеличена
  (double, double, double) _clamp(double s, double x, double y) {
    final z = _size;
    if (z.isEmpty || s <= 1) return (math.max(1.0, s), 0, 0);
    final mx = z.width * (s - 1) / 2, my = z.height * (s - 1) / 2;
    return (s, x.clamp(-mx, mx), y.clamp(-my, my));
  }

  void _set((double, double, double) v) => setState(() {
        _s = v.$1;
        _x = v.$2;
        _y = v.$3;
      });

  // Увеличить вокруг точки (cx, cy) экрана
  void _zoomAt(double s, Offset c) {
    final z = _size, o = _origin;
    final px = c.dx - (o.dx + z.width / 2), py = c.dy - (o.dy + z.height / 2);
    final k = s / _s;
    _set(_clamp(s, px - (px - _x) * k, py - (py - _y) * k));
  }

  void _setPull(double y) {
    setState(() => _pull = y);
    widget.onPull(y);
  }

  void _down(PointerDownEvent e) {
    _pts[e.pointer] = e.position;
    final list = _pts.values.toList();
    _tap = list.length == 1 ? (p: e.position, at: DateTime.now().millisecondsSinceEpoch) : null;
    _g = _G(list, _s, _x, _y, DateTime.now().millisecondsSinceEpoch);
  }

  void _move(PointerMoveEvent e) {
    if (!_pts.containsKey(e.pointer)) return;
    _pts[e.pointer] = e.position;
    final list = _pts.values.toList();
    final st = _g;
    if (st == null) return;
    if (_tap != null && (e.position - _tap!.p).distance > 8) _tap = null;
    if (list.length >= 2 && st.list.length >= 2) {
      // Два пальца: масштаб по расстоянию, сдвиг по середине
      final d0 = math.max(1e-6, (st.list[0] - st.list[1]).distance);
      final d1 = (list[0] - list[1]).distance;
      final s = (st.s * d1 / d0).clamp(1.0, _maxScale);
      final m0 = (st.list[0] + st.list[1]) / 2, m1 = (list[0] + list[1]) / 2;
      final z = _size, o = _origin;
      final px = m0.dx - (o.dx + z.width / 2), py = m0.dy - (o.dy + z.height / 2);
      final k = s / st.s;
      _set(_clamp(s, px - (px - st.x) * k + (m1.dx - m0.dx), py - (py - st.y) * k + (m1.dy - m0.dy)));
    } else if (list.length == 1 && st.s <= 1.02) {
      // Один палец вниз при обычном размере — картинка уходит вниз, отпустить — закрыть просмотр
      final dx = list[0].dx - st.list[0].dx, dy = list[0].dy - st.list[0].dy;
      if (_pull > 0 || (dy > 12 && dy > dx.abs() * 1.2)) _setPull(math.max(0, dy));
    } else if (list.length == 1 && st.s > 1) {
      // Один палец по увеличенной картинке — двигаем её
      _set(_clamp(st.s, st.x + (list[0].dx - st.list[0].dx), st.y + (list[0].dy - st.list[0].dy)));
    }
  }

  void _up(PointerEvent e) {
    final was = _g;
    _pts.remove(e.pointer);
    final list = _pts.values.toList();
    _g = list.isNotEmpty ? _G(list, _s, _x, _y, DateTime.now().millisecondsSinceEpoch) : null;
    if (list.isNotEmpty) return;
    if (_pull > 0) {
      final fast = was != null && (e.position.dy - was.list[0].dy) / math.max(1, DateTime.now().millisecondsSinceEpoch - was.at) > 0.6;
      _tap = null;
      if (_pull > 110 || fast) return widget.onClose();
      return _setPull(0);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_tap != null && now - _tap!.at < 350) {
      // Короткое нажатие: увеличить в этом месте, повторное — вернуть как было
      if (_s > 1.05) {
        _set((1, 0, 0));
      } else {
        _zoomAt(_tapScale, e.position);
      }
    } else if (was != null && was.s <= 1.02 && was.list.length == 1) {
      // Смахивание при обычном размере — к соседней картинке
      final dx = e.position.dx - was.list[0].dx;
      if (dx.abs() > 60) widget.onSwipe(dx < 0 ? 1 : -1);
    }
    _tap = null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scale = _s * (1 - math.min(_pull, 400) / 2000);
    return Stack(fit: StackFit.expand, children: [
      Listener(
        key: _box,
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: ClipRect(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(_x, _y + _pull, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1),
            child: Image.network(
              item['img'] as String,
              fit: BoxFit.contain,
              headers: const {'User-Agent': 'AOBible/1.0 (https://aobible.app)'},
              loadingBuilder: (c, child, p) => p == null ? child : const Center(child: Spinner(size: 28, color: Color(0xCCF2EFE9))),
              errorBuilder: (c, e, st) => Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(t('Картинка не загрузилась. Проверьте интернет.'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xCCF2EFE9))))),
            ),
          ),
        ),
      ),
      Positioned(
        right: 10,
        bottom: 10,
        child: Row(children: [
          _RoundBtn(icon: LucideIcons.zoomOut, label: t('Уменьшить'), onTap: _s <= 1 ? null : () => _set(_clamp(math.max(1.0, _s / 1.6), _x, _y))),
          const SizedBox(width: 8),
          _RoundBtn(
            icon: LucideIcons.zoomIn,
            label: t('Увеличить'),
            onTap: _s >= _maxScale
                ? null
                : () {
                    final z = _size, o = _origin;
                    _zoomAt(math.min(_maxScale, _s * 1.6), Offset(o.dx + z.width / 2, o.dy + z.height / 2));
                  },
          ),
        ]),
      ),
    ]);
  }
}

// Общие элементы интерфейса — один в один с веб-версией (G:\AO Bible\src\styles.css, src/components/ui.jsx,
// BottomSheet.jsx). Значки — Lucide (как lucide-react в веб-версии): LucideIcons.<имя в camelCase>.
// Базовый размер шрифта интерфейса — 15 px (body в веб-версии), 1rem = 16 px.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, OverflowBoxFit, PipelineOwner, RenderProxyBox;
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

/// Включённый значок на панели инструментов (.toolbar .tb-icon.on): на тёмной панели — акцент, осветлённый белым;
/// на светлой («Мята», «Лаванда», «Закат») осветлённый сливался с панелью — там полный акцент, если он отличим от текста
Color barOnColor(Palette pal) {
  final light = pal.bar.computeLuminance() > 0.5;
  final x = pal.accent.computeLuminance(), y = pal.barText.computeLuminance();
  final distinct = (x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05)) > 1.5; // в «Светлой» акцент почти как текст
  return light && distinct ? pal.accent : mix(pal.accent, 0.55, Colors.white);
}

/// Текст цвета акцента на плашке «акцент 12 %» (номер Стронга, выбранный раздел): чуть ближе к цвету текста —
/// иначе в тёплых темах контраст ниже 4.5 (WCAG)
Color accentOnTint(Palette pal) => mix(pal.accent, 0.85, pal.text);

/// Сколько полноэкранных страниц (проигрыватель) сейчас поверх — нижние вкладки на это время прячутся
final tabBarSuppress = ValueNotifier<int>(0);

/// Насколько проигрыватель ещё «не вырос» (px), пока раскрываются или прячутся его настройки: высота уже отдана
/// в раскладку целиком, а фон едет плавно. Стрелки глав (BarShiftDown) опускаются на столько же при рисовании.
class BarShift extends ChangeNotifier {
  double Function() read = () => 0;
  void tick() => notifyListeners();
}

final barShift = BarShift();

/// Сдвигает ребёнка вниз на barShift при рисовании и нажатии — без пересчёта раскладки на каждом кадре.
/// Ребёнок и сам сдвиг — в своих слоях: на кадре переставляется готовая картинка, остальной экран не перерисовывается
class BarShiftDown extends StatelessWidget {
  const BarShiftDown({super.key, this.enabled = true, required this.child});
  final bool enabled;
  final Widget child;
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: _BarShiftBox(enabled: enabled, child: RepaintBoundary(child: child)));
}

class _BarShiftBox extends SingleChildRenderObjectWidget {
  const _BarShiftBox({this.enabled = true, super.child});
  final bool enabled;
  @override
  RenderObject createRenderObject(BuildContext context) => RenderBarShift(enabled);
  @override
  void updateRenderObject(BuildContext context, RenderBarShift renderObject) => renderObject.enabled = enabled;
}

class RenderBarShift extends RenderProxyBox {
  RenderBarShift(this._enabled);
  bool _enabled;
  set enabled(bool v) {
    if (v == _enabled) return;
    _enabled = v;
    markNeedsPaint();
  }

  double get _dy => _enabled ? barShift.read() : 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    barShift.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    barShift.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset + Offset(0, _dy));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child != null && result.addWithPaintOffset(offset: Offset(0, _dy), position: position, hitTest: (r, p) => child!.hitTest(r, position: p));

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.translateByDouble(0, _dy, 0, 1);
}

/// Плавно раскрывает и сворачивает содержимое: высота и прозрачность, как у настроек проигрывателя
/// (мягкий разгон и остановка, 280 мс). Свёрнутое собрано и разложено заранее, но скрыто (Offstage: не рисуется,
/// не нажимается, места не занимает) — при раскрытии ничего не строится, и первый кадр не «съедает» анимацию.
/// На кадре меняется только обрезка (Align.heightFactor) — содержимое заново не раскладывается
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.open, required this.child});
  final bool open;
  final Widget child;
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: widget.open ? 1 : 0);
  late final _a = CurvedAnimation(parent: _c, curve: Curves.fastOutSlowIn);

  @override
  void didUpdateWidget(Reveal old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open) widget.open ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: FadeTransition(opacity: _a, child: RepaintBoundary(child: widget.child)),
        builder: (context, child) => ClipRect(
          clipBehavior: _c.isCompleted ? Clip.none : Clip.hardEdge, // раскрытое не обрезаем: тени и рамки целы (как .reveal в вебе)
          child: Align(alignment: Alignment.topCenter, heightFactor: _a.value, child: Offstage(offstage: _c.isDismissed, child: child)),
        ),
      );
}

/// Узкий экран (телефон): одиночные кнопки — на всю ширину
bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// Палитра текущей темы (со своими цветами)
Palette paletteOf(WidgetRef ref) => ref.watch(settingsProvider.select((s) => s.palette));

// --- Нижнее окно (BottomSheet.jsx): скруглённый верх, полоска, заголовок, крестик ------------------------

/// Какая нижняя вкладка сейчас открыта: plans, search, bible, saved, more (activeTab в TabBar.jsx)
final tabActive = ValueNotifier<String>('bible');

/// Открыть окно: initial — доля высоты экрана (как initial={1|2} в веб-версии: 0.5 или 0.92).
/// Окно, открытое поверх другого окна (из «Ещё», из «Настроек»…), получает стрелку «назад» к нему,
/// а крестик закрывает все окна разом.
Future<T?> showAobSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context) builder,
  double initial = 0.92,
  bool page = false,
  String? tab, // вкладка этого окна (plans, search, saved, more): подсвечивается, если окно открыто не с неё
}) {
  final nested = topRoute(context) is PopupRoute;
  // Окно поднимается над клавиатурой: поле ввода (заметка, поиск) не прячется под ней
  Widget body(BuildContext c) => _Nested(
        nested: nested,
        // С клавиатурой верх окна остаётся на месте, а низ встаёт над клавиатурой (окно «растягивается до клавиатуры»);
        // выше окно уезжает, только если иначе ему не хватит места (меньше 280 px)
        child: LayoutBuilder(builder: (c2, box) {
          final kb = MediaQuery.viewInsetsOf(c).bottom;
          // окно поднимается максимум до нижнего края верхней панели (плашки перевода и места) с зазором 5 px;
          // окна поверх окна и страницы — на весь экран
          final barH = ProviderScope.containerOf(c, listen: false).read(settingsProvider).d('barHeight');
          final cap = page || nested ? box.maxHeight : box.maxHeight - barH - 5;
          final want = math.min(box.maxHeight * (page || nested ? 1 : initial), cap);
          final h = kb == 0 ? want : math.max(want - kb, math.min(box.maxHeight - kb, 280.0));
          return Padding(
            padding: EdgeInsets.only(bottom: kb),
            // окно уже поднято над клавиатурой — внутрь её высоту не передаём: иначе Scaffold внутри окна ужимал бы
            // содержимое второй раз, и между окном и клавиатурой просвечивало окно под ним
            child: MediaQuery.removeViewInsets(
              context: c,
              removeBottom: true,
              child: SizedBox(height: h, child: builder(c)),
            ),
          );
        }),
      );
  final Future<T?> f = nested
      // окно поверх окна (подменю: «Ещё» → «Настройки») — на весь экран, въезжает справа и уезжает вправо
      ? showGeneralDialog<T>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.12),
          transitionDuration: const Duration(milliseconds: 300),
          transitionBuilder: (c, a, s, child) => SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.fastOutSlowIn, reverseCurve: Curves.fastOutSlowIn.flipped)),
            child: child,
          ),
          pageBuilder: (c, a, s) => SafeArea(
            bottom: false,
            child: Align(alignment: Alignment.bottomCenter, child: Material(type: MaterialType.transparency, child: body(c))),
          ),
        )
      : showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.32),
          builder: body,
        );
  // как activeTab в веб-версии: окно своего вида подсвечивает свою вкладку, пока открыто (если подсвечена «Библия»)
  if (tab != null && tabActive.value == 'bible') {
    tabActive.value = tab;
    f.whenComplete(() {
      if (tabActive.value == tab) tabActive.value = 'bible';
    });
  }
  return f;
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

/// Высота нижних вкладок вместе с отступами (0 — вкладок нет: широкий экран, первая загрузка).
/// Вкладки лежат поверх окон (.tabbar поверх .sheet), поэтому внизу окон — отступ такой высоты
/// (html.has-tabbar .sheet-body { padding-bottom: 20px + --tabbar-h }).
final tabBarInset = ValueNotifier<double>(0);

/// Сколько нижних окон (и меню) сейчас открыто — вкладки в режиме чтения не прячутся, пока окно открыто
final sheetsOpen = ValueNotifier<int>(0);

/// Следит за окнами: считает открытые PopupRoute (подключается в MaterialApp.navigatorObservers)
class SheetObserver extends NavigatorObserver {
  // Множество открытых окон, а не счётчик: пропущенное событие не сбивает число навсегда.
  // Новое приложение (новый наблюдатель) — счёт с нуля
  SheetObserver() {
    _open.clear();
    _sync();
  }
  static final _open = <Route<dynamic>>{};
  void _sync() => Future.microtask(() => sheetsOpen.value = _open.length);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && _open.add(route)) _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_open.remove(route)) _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_open.remove(route)) _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _open.remove(oldRoute);
    if (newRoute is PopupRoute) _open.add(newRoute);
    _sync();
  }
}

/// Отступ под вкладки для окна (с клавиатурой вкладки спрятаны — отступа нет)
Widget tabInsetBuilder(BuildContext context, Widget Function(double inset) build) => ValueListenableBuilder<double>(
      valueListenable: tabBarInset,
      builder: (c, v, _) => build(MediaQuery.viewInsetsOf(c).bottom > 0 ? 0 : v),
    );

/// Нижний отступ списка в окне: прежний + высота вкладок, лежащих поверх окна (MediaQuery.padding.bottom)
EdgeInsets padTabs(BuildContext context, EdgeInsets p) => p.copyWith(bottom: p.bottom + MediaQuery.paddingOf(context).bottom);

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
    // Размер шрифта меню и окон (uiFontSize) — для всех окон. Масштаб считаем от системного (а не от уже изменённого
    // выше AppSheet), чтобы окно, вложенное в AppSheet, не масштабировалось дважды
    final scale = ref.watch(settingsProvider.select((s) => s.d('uiFontSize'))) / 15;
    final mq = MediaQuery.of(context);
    final system = MediaQueryData.fromView(View.of(context)).textScaler;
    return MediaQuery(
      data: mq.copyWith(textScaler: scale == 1 ? system : TextScaler.linear(system.scale(1) * scale)),
      child: _sheet(context, pal, body, back),
    );
  }

  Widget _sheet(BuildContext context, Palette pal, Widget body, VoidCallback? back) {
    return Material(
      color: pal.panel,
      borderRadius: _Nested.of(context) ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(kRadius + 6)), // окно на весь экран — без скругления
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // полоска — только у окна, которое можно потянуть; у окна на весь экран — просто отступ сверху
        if (_Nested.of(context))
          const SizedBox(height: 14)
        else
          Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 1), // полоска ближе к заголовку — шапка ниже
            child: Container(width: 40, height: 5, decoration: BoxDecoration(color: mix(pal.muted, 0.45, pal.panel), borderRadius: BorderRadius.circular(3))),
          ),
        Container(
          // стрелка «назад», заголовок и крестик — на одной линии: одинаковые отступы сверху и снизу, у текста —
          // без невидимых полей над первой и под последней строкой (иначе его середина ниже середины значков)
          padding: EdgeInsets.fromLTRB(back != null ? 6 : 16, 2, 10, 6),
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (back != null) IconBtn(icon: LucideIcons.chevronLeft, tooltip: t('Назад'), onTap: back),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
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
            ...actions,
            IconBtn(icon: LucideIcons.x, tooltip: t('Закрыть'), onTap: onClose ?? () => closeAllSheets(context)),
          ]),
        ),
        // Содержимое доходит до самого низа и уходит под вкладки, лежащие поверх окна (как в веб-версии);
        // высота вкладок — запасом прокрутки внизу: окно с прокруткой добавляет его само, списку внутри окна он
        // приходит как MediaQuery.padding.bottom (список прибавляет его к своему нижнему отступу)
        Expanded(
          child: tabInsetBuilder(
            context,
            (inset) => scroll
                ? SingleChildScrollView(child: Column(children: [body, SizedBox(height: inset)]))
                : MediaQuery(
                    data: MediaQuery.of(context).copyWith(padding: MediaQuery.paddingOf(context).copyWith(bottom: MediaQuery.paddingOf(context).bottom + inset)),
                    child: body,
                  ),
          ),
        ),
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
  const AobButton({super.key, required this.label, this.icon, required this.onTap, this.kind = BtnKind.normal, this.small = false, this.wide = false, this.block = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool small;
  final bool wide;
  /// одиночная кнопка отдельной строкой («Сбросить оформление», «Очистить историю»): на телефоне — на всю ширину
  final bool block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final wide = this.wide || (block && isPhone(context));
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (pal.accent, pal.onAccent, pal.accent),
      BtnKind.danger => (const Color(0xffc93a3a), Colors.white, const Color(0xffc93a3a)),
      BtnKind.ghost => (Colors.transparent, pal.text, Colors.transparent),
      BtnKind.normal => (pal.bg, pal.text, pal.line),
    };
    final content = Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[Icon(icon, size: small ? 14 : 16, color: fg), const SizedBox(width: 6)],
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 13.8 : 15.2, fontWeight: FontWeight.w500, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: fg))),
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
    // выбор — плавно: фон, рамка и надпись перетекают в цвет акцента
    return TweenAnimationBuilder<double>(
      tween: Tween(end: on ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.fastOutSlowIn,
      builder: (context, v, _) {
        final fg = Color.lerp(ghost ? pal.muted : pal.text, pal.onAccent, v)!;
        return Material(
          animationDuration: Duration.zero,
          color: Color.lerp(ghost ? pal.accent.withValues(alpha: 0) : pal.bg, pal.accent, v),
          shape: StadiumBorder(side: BorderSide(color: Color.lerp(pal.line, pal.accent, v)!)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
                Text(label, style: TextStyle(fontSize: 13.8, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: fg)),
                if (count != null) ...[const SizedBox(width: 5), Text('$count', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8)))],
              ]),
            ),
          ),
        );
      },
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
    // как список переводов: подсветка нажатия и линии — от края до края окна, отступы — у содержимого
    return _bleed(InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
    ));
  }
}

/// .menu-item: значок цвета акцента, подпись, справа — дополнение (вкл/выкл, «новая»)
class MenuRow extends ConsumerWidget {
  const MenuRow({super.key, required this.icon, required this.label, required this.onTap, this.extra, this.color, this.flat = false});
  final bool flat; // в окне — от края до края, без скругления (меню «Ещё»); во всплывающем меню — со скруглением
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
      borderRadius: flat ? null : BorderRadius.circular(kRadius * 0.6),
      clipBehavior: flat ? Clip.none : Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: flat ? 20 : 12, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: color ?? pal.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 15.7, color: color ?? pal.text))),
            ?extra,
          ]),
        ),
      ),
    );
  }
}

class MenuSep extends ConsumerWidget {
  const MenuSep({super.key, this.full = false});
  final bool full; // от края до края окна
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(height: 1, margin: EdgeInsets.symmetric(horizontal: full ? 0 : 8, vertical: 4), color: paletteOf(ref).line);
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
double _textWidth(String text, TextStyle style, TextScaler scale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1, textScaler: scale)..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

class Segmented<T> extends ConsumerStatefulWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  ConsumerState<Segmented<T>> createState() => _SegmentedState<T>();
}

class _SegmentedState<T> extends ConsumerState<Segmented<T>> {
  int? _drag; // ведут пальцем: плашка идёт за ним, выбор — когда отпустили (как нижнее меню и веб-версия)

  // Ширина вариантов — как flex: 1 1 auto в веб-версии: по тексту плюс поровну свободного места строки;
  // не помещаются в строку — переносятся (flex-wrap), и каждая строка тоже растягивается на всю ширину.
  // Плашка выбранного варианта — одна, она переезжает к новому выбору (в том числе на другую строку)
  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final pal = paletteOf(ref);
    final scale = MediaQuery.textScalerOf(context);
    // запас строки — поровну сверху и снизу: надпись ровно посередине плашки
    TextStyle style(bool on) => TextStyle(fontSize: 14.08, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? pal.accent : pal.text);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: pal.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(kRadius * 0.75)),
      child: LayoutBuilder(builder: (context, c) {
        const gap = 2.0;
        final maxW = c.maxWidth;
        // ширина по жирному начертанию — выбор варианта не сдвигает соседей
        final basis = [for (final (_, label) in options) math.min(_textWidth(label, style(true), scale) + 16.5, maxW)];
        final tp = TextPainter(text: TextSpan(text: 'Ag', style: style(true)), textDirection: TextDirection.ltr, maxLines: 1, textScaler: scale)..layout();
        final h = tp.height + 14; // поля 7 сверху и снизу
        tp.dispose();
        // раскладка по строкам: что помещается — в строку, свободное место строки — поровну между её вариантами
        final rects = List<Rect>.filled(options.length, Rect.zero);
        var row = <int>[];
        var y = 0.0;
        void flush() {
          if (row.isEmpty) return;
          final used = row.fold<double>(0, (a, i) => a + basis[i]) + gap * (row.length - 1);
          final extra = math.max(0.0, (maxW - used) / row.length);
          var x = 0.0;
          for (final i in row) {
            final w = basis[i] + extra;
            rects[i] = Rect.fromLTWH(x, y, w, h);
            x += w + gap;
          }
          y += h + gap;
          row = [];
        }

        var lineW = 0.0;
        for (var i = 0; i < options.length; i++) {
          final add = (row.isEmpty ? 0 : gap) + basis[i];
          if (row.isNotEmpty && lineW + add > maxW + 0.01) {
            flush();
            lineW = 0;
          }
          lineW += row.isEmpty ? basis[i] : add;
          row.add(i);
        }
        flush();
        final height = math.max(0.0, y - gap);
        final chosen = options.indexWhere((o) => o.$1 == widget.value);
        final sel = _drag ?? chosen;
        final dur = Duration(milliseconds: _drag != null ? 140 : 300);
        // вариант под пальцем: в той же строке — ближайший по горизонтали
        int at(Offset p) {
          var best = chosen < 0 ? 0 : chosen;
          var bestD = double.infinity;
          for (var i = 0; i < rects.length; i++) {
            final r = rects[i];
            final dy = p.dy < r.top ? r.top - p.dy : (p.dy > r.bottom ? p.dy - r.bottom : 0.0);
            final dx = p.dx < r.left ? r.left - p.dx : (p.dx > r.right ? p.dx - r.right : 0.0);
            final d = dy * 1000 + dx;
            if (d < bestD) {
              bestD = d;
              best = i;
            }
          }
          return best;
        }

        void end() {
          final i = _drag;
          setState(() => _drag = null);
          if (i != null && i != chosen) widget.onChanged(options[i].$1);
        }

        return GestureDetector(
          onHorizontalDragStart: (d) => setState(() => _drag = at(d.localPosition)),
          onHorizontalDragUpdate: (d) {
            final i = at(d.localPosition);
            if (i != _drag) setState(() => _drag = i);
          },
          onHorizontalDragEnd: (_) => end(),
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: SizedBox(
          width: maxW,
          height: height,
          child: Stack(children: [
            if (sel >= 0)
              AnimatedPositioned(
                duration: dur,
                curve: Curves.easeOutCubic, // у тени не может быть «перелёта» пружинной кривой
                left: rects[sel].left,
                top: rects[sel].top,
                width: rects[sel].width,
                height: rects[sel].height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: pal.panel,
                    borderRadius: BorderRadius.circular(kRadius * 0.6),
                    boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))],
                  ),
                ),
              ),
            for (var i = 0; i < options.length; i++)
              Positioned.fromRect(
                rect: rects[i],
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onChanged(options[i].$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: dur,
                        curve: Curves.easeOutCubic,
                        style: style(i == sel),
                        child: Text(options[i].$2, maxLines: 1, softWrap: false, overflow: TextOverflow.clip),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          ),
        );
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
    // Когда в поле что-то вписано — крестик «Очистить» (если своей кнопки справа нет), как .search-clear в веб-версии
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) => TextField(
        controller: controller,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: TextStyle(fontSize: 16, color: pal.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: pal.muted),
          prefixIcon: icon == null ? null : Icon(icon, size: 18, color: pal.muted),
          suffixIcon: trailing ??
              (v.text.isEmpty
                  ? null
                  : IconBtn(
                      icon: LucideIcons.x,
                      subtle: true,
                      size: 18,
                      tooltip: t('Очистить'),
                      onTap: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                    )),
          isDense: true,
          filled: true,
          fillColor: pal.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide(color: pal.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide(color: pal.accent)),
        ),
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
      builder: (context, box) => OverflowBox(minWidth: box.maxWidth + 32, maxWidth: box.maxWidth + 32, fit: OverflowBoxFit.deferToChild, child: child),
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
      // смена вкладки — плавно: линия и цвет надписи перетекают
      final w = InkWell(
        onTap: () => onChanged(x.$1),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: on ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 240),
          curve: Curves.fastOutSlowIn,
          builder: (context, v, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            alignment: expand ? Alignment.center : null,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.accent.withValues(alpha: v), width: 2))),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: x.$2),
                if (x.$3 != null) TextSpan(text: ' ${x.$3}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: pal.muted)),
              ]),
              maxLines: 1,
              softWrap: false,
              style: label.copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: Color.lerp(pal.muted, pal.accent, v)),
            ),
          ),
        ),
      );
      return expand ? Expanded(child: w) : w;
    }

    final bar = LayoutBuilder(builder: (context, box) {
      final need = tabs.fold<double>(0, (a, x) {
        return a + _textWidth('${x.$2}${x.$3 != null ? ' ${x.$3}' : ''}', label, scale) + 24;
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

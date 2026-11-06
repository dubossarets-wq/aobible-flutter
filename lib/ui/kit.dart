// Общие элементы интерфейса — один в один с веб-версией (G:\AO Bible\src\styles.css, src/components/ui.jsx,
// BottomSheet.jsx). Значки — Lucide (как lucide-react в веб-версии): LucideIcons.<имя в camelCase>.
// Базовый размер шрифта интерфейса — 15 px (body в веб-версии), 1rem = 16 px.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator, CupertinoButton, CupertinoButtonSize, CupertinoColors, CupertinoIcons, CupertinoListTileChevron, CupertinoPageRoute, CupertinoSlidingSegmentedControl, CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, OverflowBoxFit, PipelineOwner, RenderProxyBox, ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart' show CNActionSheet, CNActionSheetAction, CNButton, CNButtonConfig, CNButtonStyle, CNSegmentedControl, CNSwitch, CNSymbol;

import 'glass.dart';
import 'ios_style.dart';
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
  // в стиле iPhone окно не укорачивается над клавиатурой, а уходит под неё; её высота приходит внутрь нижним
  // отступом (строка ввода поиска встаёт над клавиатурой, скруглённые углы клавиатуры — на фоне окна)
  bool underKeyboard = false,
  // окно к тексту (выбор перевода, «Перейти», выбор цвета): в стиле iPhone остаётся листом снизу;
  // остальные окна в стиле iPhone — на весь экран, с «назад» и «закрыть»
  bool scripture = false,
  // false — окно не забирает фокус
  bool requestFocus = true,
}) {
  final ios = ProviderScope.containerOf(context, listen: false).read(settingsProvider).get<bool>('iosStyle');
  final iosFull = !scripture && ios;
  final nested = isSheetRoute(topRoute(context)) || iosFull;
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
          // одно и то же дерево и с клавиатурой, и без неё: иначе при её появлении окно строилось бы заново (терялись
          // бы фокус, введённый текст и прокрутка)
          if (underKeyboard && ProviderScope.containerOf(c, listen: false).read(settingsProvider).get<bool>('iosStyle')) {
            final mq = MediaQuery.of(c).removeViewInsets(removeBottom: true);
            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: want,
                child: MediaQuery(data: kb > 0 ? mq.copyWith(padding: mq.padding.copyWith(bottom: kb)) : mq, child: SheetKeyboard(height: kb, child: builder(c))),
              ),
            );
          }
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
  final Future<T?> f = nested && ios
      // стиль iPhone: страница на весь экран — системный переход iOS (въезжает справа, предыдущая сдвигается,
      // свайп от левого края — назад)
      ? Navigator.of(context).push<T>(IosPageRoute<T>(
          requestFocus: requestFocus,
          instant: iosTabSwitch,
          // под строкой состояния — тот же системный фон, что у страницы (иначе там видно чёрное окно)
          builder: (c) => Consumer(
            builder: (c, ref, _) => ColoredBox(
              color: iosGroupedBg(paletteOf(ref), false),
              child: Material(type: MaterialType.transparency, child: body(c)),
            ),
          ),
        ))
      : nested
      // окно поверх окна (подменю: «Ещё» → «Настройки») — на весь экран, въезжает справа и уезжает вправо
      ? showGeneralDialog<T>(
          requestFocus: requestFocus,
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
/// Переход к месту в Библии: закрываются все окна и страницы поверх читалки (и «Ещё», из которого открыли окно)
void closeToReader(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

void closeAllSheets(BuildContext context) => Navigator.of(context).popUntil((r) => !isSheetRoute(r));

/// Сейчас окно открывается сменой вкладки нижнего меню (стиль iPhone: без анимации перехода)
bool iosTabSwitch = false;

/// Убрать все окна и страницы поверх чтения сразу, без анимации (смена вкладки в стиле iPhone): закрытие с анимацией
/// и одновременный въезд новой страницы накладывались друг на друга
void dropAllSheets(BuildContext context) {
  final nav = Navigator.of(context);
  for (var r = topRoute(context); r != null && !r.isFirst; r = topRoute(context)) {
    nav.removeRoute(r);
  }
}

/// Шапка листа стиля iPhone (UI Kit Apple, Toolbar - Top): слева «назад», по центру заголовок 17 pt полужирный
/// (и серая подпись), справа «закрыть»; на iOS 26+ — системные стеклянные кнопки
Widget iosNavHeader(BuildContext context, Palette pal, {required String title, String? subtitle, VoidCallback? back, required VoidCallback close, List<Widget> actions = const []}) {
  Widget btn(String symbol, IconData icon, double size, String label, VoidCallback onTap) => nativeGlass
      ? SizedBox(
          width: 44,
          height: 44,
          child: CNButton.icon(icon: CNSymbol(symbol), onPressed: onTap, semanticLabel: label, autoHideOnModal: false, config: const CNButtonConfig(style: CNButtonStyle.glass)),
        )
      : Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(width: 36, height: 36, decoration: BoxDecoration(color: iosFill(pal), shape: BoxShape.circle), child: Icon(icon, size: size, color: pal.text)),
          ),
        );
  return Padding(
    padding: EdgeInsets.fromLTRB(iosEdge, 4, iosEdge, 8),
    child: Row(children: [
      SizedBox(width: 48, child: back == null ? null : Align(alignment: Alignment.centerLeft, child: btn('chevron.backward', CupertinoIcons.chevron_back, 19, t('Назад'), back))),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, height: 1.2, fontWeight: FontWeight.w600, color: pal.text)),
          if (subtitle != null) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.25, color: pal.muted)),
        ]),
      ),
      ...actions,
      SizedBox(width: 48, child: Align(alignment: Alignment.centerRight, child: btn('xmark', CupertinoIcons.xmark, 16, t('Закрыть'), close))),
    ]),
  );
}

/// Полоска-ручка листа (UI Kit Apple, Grabber): 36×5, системный серый
Widget iosGrabber(Palette pal) => Padding(
      padding: const EdgeInsets.only(top: 5, bottom: 3),
      child: Container(width: 36, height: 5, decoration: BoxDecoration(color: sysColor(CupertinoColors.tertiaryLabel, dark: pal.dark), borderRadius: BorderRadius.circular(2.5))),
    );

/// Страница открыта вкладкой нижнего меню (корневая страница раздела, как «Настройки» или «Папки» в iPhone)
class IosTabRoot extends InheritedWidget {
  const IosTabRoot({super.key, required this.root, required super.child});
  final bool root;
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IosTabRoot>()?.root ?? false;
  @override
  bool updateShouldNotify(IosTabRoot old) => old.root != root;
}

/// Страница окна на весь экран в стиле iPhone (системный переход iOS со свайпом назад) — тоже «окно»
class IosPageRoute<T> extends CupertinoPageRoute<T> {
  IosPageRoute({required super.builder, super.requestFocus, this.instant = false});

  // открыто сменой вкладки нижнего меню — без анимации перехода (в iOS вкладки переключаются мгновенно)
  final bool instant;
  @override
  Duration get transitionDuration => instant ? Duration.zero : super.transitionDuration;

  // страница вкладки (открыта нижним меню) — корневая: крупный заголовок, без «назад» и «закрыть»
  @override
  Widget buildContent(BuildContext context) => IosTabRoot(root: instant, child: super.buildContent(context));

  // Назад — свайпом вправо с любого места страницы (как в iOS 26), а не только от левого края
  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      _SwipeBack(route: this, child: super.buildTransitions(context, animation, secondaryAnimation, child));

  AnimationController? get _swipe => controller;
}

/// Свайп назад с любого места страницы: страница едет за пальцем; отпустили дальше середины или быстрым движением
/// вправо — закрывается, иначе возвращается. Горизонтальная прокрутка внутри страницы (ряды плашек) — у неё
class _SwipeBack extends StatefulWidget {
  const _SwipeBack({required this.route, required this.child});
  final IosPageRoute<dynamic> route;
  final Widget child;
  @override
  State<_SwipeBack> createState() => _SwipeBackState();
}

class _SwipeBackState extends State<_SwipeBack> {
  bool _active = false;

  bool get _can => widget.route.isCurrent && !widget.route.isFirst && !widget.route.navigator!.userGestureInProgress;

  void _update(DragUpdateDetails d) {
    final c = widget.route._swipe;
    if (c == null) return;
    final w = context.size?.width ?? 1;
    if (!_active) {
      // начинаем только движением вправо
      if ((d.primaryDelta ?? 0) <= 0 || !_can) return;
      _active = true;
      widget.route.navigator!.didStartUserGesture();
    }
    c.value = (c.value - (d.primaryDelta ?? 0) / w).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    if (!_active) return;
    _active = false;
    final c = widget.route._swipe!;
    final nav = widget.route.navigator!;
    final v = d.velocity.pixelsPerSecond.dx / (context.size?.width ?? 1);
    final back = v > 1.0 || (v > -1.0 && c.value < 0.5);
    if (back && widget.route.instant) {
      // страница вкладки открыта без анимации — её закрытие тоже мгновенное: сначала плавно уводим страницу
      // (как системный жест iOS), затем закрываем уже уехавшую
      final ms = (c.value * (v > 1.0 ? 240 : 350)).round().clamp(90, 350);
      c.animateBack(0.0, duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic).whenComplete(() {
        if (widget.route.isActive) nav.pop();
        nav.didStopUserGesture();
      });
      return;
    }
    if (back) {
      nav.pop();
      // доводка, как у системного жеста iOS: быстро и с замедлением у края; время — по оставшемуся пути
      // (не больше 0,35 с, при быстром смахивании — короче), а не полные 0,5 с закрытия ровным ходом
      if (c.isAnimating) {
        final ms = (c.value * (v > 1.0 ? 240 : 350)).round().clamp(90, 350);
        c.animateBack(0.0, duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic);
      }
    } else {
      c.animateTo(1.0, duration: const Duration(milliseconds: 250), curve: Curves.fastLinearToSlowEaseIn);
    }
    if (c.isAnimating) {
      void done(AnimationStatus s) {
        if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
          nav.didStopUserGesture();
          c.removeStatusListener(done);
        }
      }

      c.addStatusListener(done);
    } else {
      nav.didStopUserGesture();
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: _end,
        onHorizontalDragCancel: () {
          if (!_active) return;
          _active = false;
          widget.route._swipe?.animateTo(1.0, duration: const Duration(milliseconds: 200));
          widget.route.navigator?.didStopUserGesture();
        },
        child: widget.child,
      );
}

/// Окно (нижнее окно, меню, страница окна в стиле iPhone) — не экран чтения
bool isSheetRoute(Route<dynamic>? r) => r is PopupRoute || r is IosPageRoute;

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
    if (isSheetRoute(route) && _open.add(route)) _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_open.remove(route)) _sync();
    // окно закрыли — клавиатура уходит вместе с ним
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_open.remove(route)) _sync();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _open.remove(oldRoute);
    if (isSheetRoute(newRoute)) _open.add(newRoute!);
    _sync();
  }
}

/// Отступ под вкладки для окна (с клавиатурой вкладки спрятаны — отступа нет)
Widget tabInsetBuilder(BuildContext context, Widget Function(double inset) build) => ValueListenableBuilder<double>(
      valueListenable: tabBarInset,
      builder: (c, v, _) => build(MediaQuery.viewInsetsOf(c).bottom > 0 ? 0 : v),
    );

/// Нижний отступ списка в окне: прежний + высота вкладок, лежащих поверх окна (MediaQuery.padding.bottom)
EdgeInsets padTabs(BuildContext context, EdgeInsets p) => p.copyWith(top: p.top + IosPageTop.of(context), bottom: p.bottom + MediaQuery.paddingOf(context).bottom);

class _Nested extends InheritedWidget {
  const _Nested({required this.nested, required super.child});
  final bool nested;
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Nested>()?.nested ?? false;
  @override
  bool updateShouldNotify(_Nested old) => old.nested != nested;
}

class AobSheet extends ConsumerWidget {
  const AobSheet({super.key, required this.title, this.subtitle, required this.child, this.onBack, this.actions = const [], this.onClose, this.scroll = true, this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 20), this.titleWidget, this.underHeader = false});
  // стиль iPhone, страница: содержимое (свой список окна) уходит под прозрачную шапку, как в iOS; список прибавляет
  // отступ сверху сам (padTabs или IosPageTop.of). С прокруткой окна (scroll) — всегда так
  final bool underHeader;
  final String title;
  final Widget? titleWidget; // вместо названия — своё (размер текста «− 100% +» в проповеди); title остаётся подписью
  final String? subtitle;
  final Widget child;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final bool scroll; // false — child сам прокручивается (списки)
  final EdgeInsets padding;

  // Шапка листа iOS: «назад» слева, название по центру (полужирное 17), справа — серый круглый крестик
  Widget _iosHeader(BuildContext context, Palette pal, VoidCallback? back) {
    // корневая страница вкладки: сверху справа — только свои кнопки, ниже — крупный заголовок слева (34, жирный),
    // под ним — серая подпись (как «172 заметки» в «Заметках»)
    if (IosTabRoot.of(context) && titleWidget == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (actions.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.end, children: actions) else const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: iosTracking(34), color: pal.text)),
        ),
        if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, height: 1.3, color: pal.muted)),
      ]);
    }
    if (nativeGlass) {
      Widget glass(String symbol, String label, VoidCallback onTap) => SizedBox(
            width: 44,
            height: 44,
            child: CNButton.icon(icon: CNSymbol(symbol), onPressed: onTap, semanticLabel: label, autoHideOnModal: false, config: const CNButtonConfig(style: CNButtonStyle.glass)),
          );
      return Row(children: [
        SizedBox(width: 48, child: back == null ? null : Align(alignment: Alignment.centerLeft, child: glass('chevron.backward', t('Назад'), back))),
        Expanded(
          child: titleWidget != null
              ? Semantics(label: title, child: Center(child: titleWidget))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, height: 1.2, fontWeight: FontWeight.w600, color: pal.text)),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.25, color: pal.muted)),
                ]),
        ),
        ...actions,
        SizedBox(width: 48, child: Align(alignment: Alignment.centerRight, child: glass('xmark', t('Закрыть'), onClose ?? () => closeAllSheets(context)))),
      ]);
    }
    final close = Semantics(
      button: true,
      label: t('Закрыть'),
      child: GestureDetector(
        onTap: onClose ?? () => closeAllSheets(context),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: iosFill(pal), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.xmark, size: 16, color: pal.text),
        ),
      ),
    );
    return Row(children: [
      SizedBox(
        width: 44,
        child: back == null
            ? null
            : Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: t('Назад'),
                  child: GestureDetector(
                    onTap: back,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: iosFill(pal), shape: BoxShape.circle),
                      child: Icon(CupertinoIcons.chevron_back, size: 19, color: pal.text),
                    ),
                  ),
                ),
              ),
      ),
      Expanded(
        child: titleWidget != null
            ? Semantics(label: title, child: Center(child: titleWidget))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, height: 1.2, fontWeight: FontWeight.w600, color: pal.text)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.25, color: pal.muted)),
              ]),
      ),
      ...actions,
      // справа — пустое место той же ширины, что у «назад», чтобы название было ровно по центру
      SizedBox(width: 44, child: Align(alignment: Alignment.centerRight, child: close)),
    ]);
  }

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
    final ios = iosStyleOf(ref);
    final sheet = MediaQuery(
      data: mq.copyWith(textScaler: scale == 1 ? system : TextScaler.linear(system.scale(1) * scale)),
      child: IosElevated(elevated: !_Nested.of(context), child: _sheet(context, pal, body, back, ios)),
    );
    // окно снизу (не вложенное): список уже у верха — потянули вниз дальше, и окно уезжает за пальцем и закрывается
    return _Nested.of(context) ? sheet : _PullToClose(child: sheet);
  }

  Widget _sheet(BuildContext context, Palette pal, Widget body, VoidCallback? back, bool ios) {
    final nested = _Nested.of(context);
    if (ios && nested) {
      final root = IosTabRoot.of(context) && titleWidget == null;
      return Material(
        color: iosGroupedBg(pal, false),
        child: _IosPageFrame(
          pal: pal,
          under: scroll || underHeader,
          root: root,
          title: title,
          subtitle: subtitle,
          actions: actions,
          bar: root
              ? null
              : Container(padding: EdgeInsets.symmetric(horizontal: iosEdge), constraints: const BoxConstraints(minHeight: 44), child: _iosHeader(context, pal, back)),
          body: (top, under) => tabInsetBuilder(
            context,
            (inset) => scroll
                ? SingleChildScrollView(child: Column(children: [SizedBox(height: top), body, SizedBox(height: inset)]))
                : MediaQuery(
                    data: MediaQuery.of(context).copyWith(padding: MediaQuery.paddingOf(context).copyWith(bottom: MediaQuery.paddingOf(context).bottom + inset)),
                    child: under ? IosPageTop(top: top, child: body) : Padding(padding: EdgeInsets.only(top: top), child: body),
                  ),
          ),
        ),
      );
    }
    return Material(
      color: ios ? iosGroupedBg(pal, !nested) : pal.panel,
      // окно на весь экран — без скругления; стиль iPhone — скругление листа iOS
      // стиль iPhone: верх листа — скруглением Apple (суперэллипс)
      shape: _Nested.of(context)
          ? null
          : ios
              ? const RoundedSuperellipseBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(38)))
              : RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius + 6))),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // полоска — только у окна, которое можно потянуть; у окна на весь экран — просто отступ сверху
        if (_Nested.of(context))
          const SizedBox(height: 14)
        else
          ios
              // стиль iPhone: системная ручка листа (UI Kit Apple, Grabber)
              ? iosGrabber(pal)
              : Padding(
                  padding: const EdgeInsets.only(top: 7, bottom: 1), // полоска ближе к заголовку — шапка ниже
                  child: Container(width: 40, height: 5, decoration: BoxDecoration(color: mix(pal.muted, 0.45, pal.panel), borderRadius: BorderRadius.circular(3))),
                ),
        Container(
          // стрелка «назад», заголовок и крестик — на одной линии: одинаковые отступы сверху и снизу, у текста —
          // без невидимых полей над первой и под последней строкой (иначе его середина ниже середины значков)
          padding: ios ? EdgeInsets.fromLTRB(iosEdge, 4, iosEdge, 8) : EdgeInsets.fromLTRB(back != null ? 6 : 16, 2, 10, 6),
          constraints: const BoxConstraints(minHeight: 44),
          decoration: ios ? null : BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: ios ? _iosHeader(context, pal, back) : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (back != null) IconBtn(icon: LucideIcons.chevronLeft, tooltip: t('Назад'), onTap: back),
            if (titleWidget != null) Expanded(child: Semantics(label: title, child: Align(alignment: Alignment.centerLeft, child: titleWidget))) else
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

/// Окно уходит под клавиатуру (underKeyboard): её высота — для строки ввода, что встаёт над ней
class SheetKeyboard extends InheritedWidget {
  const SheetKeyboard({super.key, required this.height, required super.child});
  final double height;
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SheetKeyboard>()?.height ?? 0;
  @override
  bool updateShouldNotify(SheetKeyboard old) => old.height != height;
}

/// Высота прозрачной шапки страницы iOS над содержимым: на столько список окна сдвигает начало (padTabs)
class IosPageTop extends InheritedWidget {
  const IosPageTop({super.key, required this.top, required super.child});
  final double top;
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IosPageTop>()?.top ?? 0;
  @override
  bool updateShouldNotify(IosPageTop old) => old.top != top;
}

/// Размер ребёнка — после раскладки (высота шапки страницы)
class _SizeReport extends SingleChildRenderObjectWidget {
  const _SizeReport({required this.onSize, super.child});
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReport(onSize);
  @override
  void updateRenderObject(BuildContext context, _RenderSizeReport r) => r.onSize = onSize;
}

class _RenderSizeReport extends RenderProxyBox {
  _RenderSizeReport(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      final s = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
    }
  }
}

/// Страница iOS: содержимое прокручивается под строку состояния и прозрачную шапку; когда под шапкой есть текст —
/// за ней размытая полоса цвета фона (эффект края прокрутки iOS 26). У страницы вкладки — крупный заголовок 34 pt:
/// при прокрутке уменьшается до 17 pt и переезжает в центр шапки
class _IosPageFrame extends StatefulWidget {
  const _IosPageFrame({required this.pal, required this.under, required this.root, required this.title, this.subtitle, this.actions = const [], this.bar, required this.body});
  final Palette pal;
  final bool under, root;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bar; // шапка обычной страницы; у страницы вкладки — строится здесь
  final Widget Function(double top, bool under) body;
  @override
  State<_IosPageFrame> createState() => _IosPageFrameState();
}

class _IosPageFrameState extends State<_IosPageFrame> {
  // шапка как в iOS (по замеру «Настроек» iPhone): ряд 44 pt сразу под строкой состояния, полоса фона заканчивается
  // на 7 pt ниже ряда
  static const _row = 44.0, _below = 7.0, _titleTop = 4.0;
  double _bar = _row + _below, _off = 0;

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final mq = MediaQuery.of(context);
    final status = mq.padding.top;
    final width = mq.size.width;
    final base = DefaultTextStyle.of(context).style;
    final largeStyle = base.merge(TextStyle(fontSize: 34, height: 41 / 34, fontWeight: FontWeight.w700, letterSpacing: iosTracking(34), color: pal.text));
    final subStyle = base.merge(TextStyle(fontSize: 15, height: 20 / 15, color: pal.muted));
    // размеры крупного заголовка (и подписи под ним) — заранее, чтобы вести его в шапку
    double tw = 0, th = 0, sh = 0;
    if (widget.root) {
      // справа в том же ряду — свои кнопки страницы
      final maxW = math.max(0.0, width - 2 * iosEdge - 48.0 * widget.actions.length);
      final scaler = MediaQuery.textScalerOf(context);
      final dir = Directionality.of(context);
      final tp = TextPainter(text: TextSpan(text: widget.title, style: largeStyle), textDirection: dir, maxLines: 1, ellipsis: '\u2026', textScaler: scaler)..layout(maxWidth: maxW);
      tw = math.min(maxW, tp.width.ceilToDouble());
      th = tp.height;
      tp.dispose();
      if (widget.subtitle != null) {
        final sp = TextPainter(text: TextSpan(text: widget.subtitle, style: subStyle), textDirection: dir, maxLines: 1, ellipsis: '\u2026', textScaler: scaler)..layout(maxWidth: maxW);
        sh = sp.height;
        sp.dispose();
      }
    }
    // крупный заголовок стоит в ряду шапки; ниже шапки содержимому место нужно только под подпись
    final large = widget.root ? math.max(0.0, _titleTop + th + sh + 6 - _bar) : 0.0;
    final top = status + _bar + large;
    final off = widget.under ? _off : 0.0;
    // полоса за шапкой — только когда под ней уже есть текст
    final covered = widget.under && off > large + 1;
    final bg = iosGroupedBg(pal, false);
    // полоса как в iOS: ровная, почти непрозрачная (за ней лишь угадывается размытый текст), снизу — тонкая линия
    final band = Color.lerp(bg, const Color(0xffffffff), pal.dark ? 0.035 : 0.6)!.withValues(alpha: pal.dark ? 0.96 : 0.94);
    final sep = sysColor(CupertinoColors.separator, dark: pal.dark);
    final bar = widget.bar ??
        SizedBox(
          height: _row,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: iosEdge),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: widget.actions),
          ),
        );
    // крупный заголовок страницы вкладки: при прокрутке плавно уменьшается (34 → 17 pt) и переезжает в центр
    // шапки, на место обычного заголовка; при оттягивании списка вниз — едет вниз вместе с ним
    Widget? title;
    if (widget.root) {
      final p = th > 0 ? (off / th).clamp(0.0, 1.0) : 1.0;
      final pull = off < 0 ? -off : 0.0;
      final k = 1 - p * (1 - 17 / 34);
      final c = Offset.lerp(Offset(iosEdge + tw / 2, status + _titleTop + th / 2 + pull), Offset(width / 2, status + _row / 2), p)!;
      title = Positioned(
        left: c.dx - tw * k / 2,
        top: c.dy - th * k / 2,
        child: IgnorePointer(
          child: Transform.scale(
            scale: k,
            alignment: Alignment.topLeft,
            child: SizedBox(width: tw, height: th, child: Text(widget.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: largeStyle)),
          ),
        ),
      );
    }
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
          final v = n.metrics.pixels.clamp(-400.0, 4000.0);
          if ((v - _off).abs() > 0.5 && (v < large + 80 || _off < large + 80)) setState(() => _off = v);
        }
        return false;
      },
      child: Stack(children: [
        Positioned.fill(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.body(top, widget.under))),
        // подпись под крупным заголовком — едет вместе со списком и тает
        if (widget.root && widget.subtitle != null)
          Positioned(
            left: iosEdge,
            right: iosEdge,
            top: status + _titleTop + th - off,
            child: IgnorePointer(
              child: Opacity(
                opacity: (1 - (off / math.max(1.0, th)) * 2).clamp(0.0, 1.0),
                child: Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
              ),
            ),
          ),
        // эффект края прокрутки: ровная полоса под строкой состояния и шапкой — до её нижнего края, без перехода
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: status + _bar,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: covered ? 1 : 0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: band, border: Border(bottom: BorderSide(color: sep, width: 1 / mq.devicePixelRatio))),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: status,
          child: _SizeReport(
            onSize: (s) {
              if (mounted && (s.height - _bar).abs() > 0.5) setState(() => _bar = s.height);
            },
            child: Padding(padding: const EdgeInsets.only(bottom: _below), child: bar),
          ),
        ),
        ?title,
      ]),
    );
  }
}

/// Свайп вниз по раскрытому окну, когда его список уже прокручен до верха: окно едет за пальцем;
/// отпустили дальше 90 px — закрывается, ближе — плавно возвращается на место
class _PullToClose extends StatefulWidget {
  const _PullToClose({required this.child});
  final Widget child;
  @override
  State<_PullToClose> createState() => _PullToCloseState();
}

class _PullToCloseState extends State<_PullToClose> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..addListener(() => setState(() => _pull = _from * (1 - Curves.fastOutSlowIn.transform(_back.value))));
  double _pull = 0, _from = 0;
  bool _closing = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _release() {
    if (_pull <= 0 || _closing) return;
    if (_pull > 90) {
      _closing = true;
      Navigator.of(context).maybePop();
      return;
    }
    _from = _pull;
    _back.forward(from: 0);
  }

  /// Сдвиг пальца делится до того, как его получит список (_PullPhysics): так список не дёргается туда-обратно
  /// и не уезжает, пока окно опущено. Возвращает, сколько сдвига осталось списку
  double _share(ScrollMetrics m, double offset) {
    if (m.axis != Axis.vertical || _closing) return offset;
    // палец вниз, список у верха — едет окно (и на iPhone: список у верха не пружинит, а тянет окно)
    if (offset > 0 && (_pull > 0 || m.pixels <= m.minScrollExtent)) {
      _back.stop();
      setState(() => _pull += offset);
      return 0;
    }
    // палец вверх, а окно опущено: сначала окно поднимается до конца, остаток прокручивает список
    if (offset < 0 && _pull > 0) {
      _back.stop();
      final take = math.min(-offset, _pull);
      setState(() => _pull -= take);
      return offset + take;
    }
    return offset;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || _closing) return false;
    if (n is ScrollEndNotification || (n is UserScrollNotification && n.direction == ScrollDirection.idle)) _release();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final conf = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: conf.copyWith(physics: _PullPhysics(this, parent: conf.getScrollPhysics(context))),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Transform.translate(offset: Offset(0, _pull), child: widget.child),
      ),
    );
  }
}

/// Физика списков внутри окна: сдвиг пальца сначала отдаётся окну (_PullToCloseState._share), остаток — списку
class _PullPhysics extends ScrollPhysics {
  const _PullPhysics(this.owner, {super.parent});
  final _PullToCloseState owner;
  @override
  _PullPhysics applyTo(ScrollPhysics? ancestor) => _PullPhysics(owner, parent: buildParent(ancestor));
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final rest = owner._share(position, offset);
    return rest == 0 ? 0 : super.applyPhysicsToUserOffset(position, rest);
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
    final ios = iosStyleOf(ref);
    final icon = ios ? iosIcon(this.icon) : this.icon;
    final d = subtle ? 32.0 : 38.0;
    final btn = SizedBox(
      width: d,
      height: d,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: AIcon(ico(icon), size: size ?? (subtle ? 18 : 22), color: color ?? (on ? pal.accent : subtle ? pal.muted : pal.text))),
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
    final ios = iosStyleOf(ref);
    final icon = ios && this.icon != null ? iosIcon(this.icon!) : this.icon;
    final wide = this.wide || (block && isPhone(context));
    // стиль iPhone: кнопки-капсулы iOS 26 без рамки — главная залита акцентом, обычная — серой заливкой
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (pal.accent, pal.onAccent, pal.accent),
      BtnKind.danger => ios ? (iosFill(pal), const Color(0xffff3b30), Colors.transparent) : (const Color(0xffc93a3a), Colors.white, const Color(0xffc93a3a)),
      BtnKind.ghost => (Colors.transparent, ios ? pal.accent : pal.text, Colors.transparent),
      BtnKind.normal => ios ? (iosFill(pal), pal.accent, Colors.transparent) : (pal.bg, pal.text, pal.line),
    };
    final content = Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[AIcon(ico(icon), size: small ? 14 : 16, color: fg), const SizedBox(width: 6)],
      Flexible(child: Transform.translate(offset: const Offset(0, -1), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 13.8 : 15.2, fontWeight: FontWeight.w500, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: fg)))),
    ]);
    if (ios) {
      // UI Kit Apple (Buttons): капсулы высотой 28 (мелкая), 34 (обычная), 50 (крупная — на всю ширину)
      final size = small ? CupertinoButtonSize.small : (wide ? CupertinoButtonSize.large : CupertinoButtonSize.medium);
      final minH = small ? 28.0 : (wide ? 50.0 : 34.0);
      const pill = BorderRadius.all(Radius.circular(100));
      final child = Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[AIcon(ico(icon), size: small ? 15 : 17), const SizedBox(width: 6)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]);
      final btn = switch (kind) {
        BtnKind.primary => CupertinoButton.filled(sizeStyle: size, minimumSize: Size(minH, minH), borderRadius: pill, onPressed: onTap, child: child),
        BtnKind.danger => CupertinoButton.tinted(sizeStyle: size, minimumSize: Size(minH, minH), borderRadius: pill, color: CupertinoColors.systemRed, onPressed: onTap, child: child),
        BtnKind.ghost => CupertinoButton(sizeStyle: size, minimumSize: Size(minH, minH), borderRadius: pill, onPressed: onTap, child: child),
        BtnKind.normal => CupertinoButton.tinted(sizeStyle: size, minimumSize: Size(minH, minH), borderRadius: pill, onPressed: onTap, child: child),
      };
      return wide ? SizedBox(width: double.infinity, child: btn) : btn;
    }
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: ios ? StadiumBorder(side: BorderSide(color: border)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: small
                ? EdgeInsets.symmetric(horizontal: ios ? 12 : 10, vertical: 6)
                : EdgeInsets.symmetric(horizontal: ios ? 18 : 14, vertical: ios ? 11 : 9),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// .chip: плашка-«таблетка»; on — цвет акцента; ghost — без фона
class AobChip extends ConsumerWidget {
  const AobChip({super.key, required this.label, this.onTap, this.on = false, this.icon, this.ghost = false, this.count, this.compact = false});
  final String label;
  final VoidCallback? onTap;
  final bool on;
  final IconData? icon;
  final bool ghost;
  final int? count;
  final bool compact; // ряды фильтров: высота 30, число мельче и серее

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final ios = iosStyleOf(ref);
    final icon = ios && this.icon != null ? iosIcon(this.icon!) : this.icon;
    // выбор — плавно: фон, рамка и надпись перетекают в цвет акцента
    return TweenAnimationBuilder<double>(
      tween: Tween(end: on ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.fastOutSlowIn,
      builder: (context, v, _) {
        final fg = Color.lerp(ghost ? pal.muted : pal.text, pal.onAccent, v)!;
        return Material(
          animationDuration: Duration.zero,
          color: Color.lerp(ghost ? pal.accent.withValues(alpha: 0) : (ios ? iosFill(pal) : pal.bg), pal.accent, v),
          shape: StadiumBorder(side: ios ? BorderSide.none : BorderSide(color: Color.lerp(pal.line, pal.accent, v)!)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 11, vertical: compact ? 0 : 5),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: compact ? 30 : 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[AIcon(ico(icon), size: 14, color: fg), const SizedBox(width: 5)],
                  // на 1 px выше: строчные без выносных элементов визуально садятся ниже середины
                  Transform.translate(offset: const Offset(0, -1), child: Text(label, style: TextStyle(fontSize: compact ? 13.5 : 13.8, height: 1.2, leadingDistribution: TextLeadingDistribution.even, color: fg))),
                  if (count != null) ...[
                    SizedBox(width: compact ? 4 : 5),
                    // в компактном ряду число тише: серое у невыбранной плашки
                    Transform.translate(offset: const Offset(0, -1), child: Text('$count', style: TextStyle(fontSize: compact ? 11.5 : 12, color: compact ? Color.lerp(pal.muted, pal.onAccent, v)!.withValues(alpha: 0.85) : fg.withValues(alpha: 0.8)))),
                  ],
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- Строки ---------------------------------------------------------------------------------------------

/// .pref-row: значок в цветном квадрате 38×38 (скругление 11), заголовок, подпись, стрелка; линия снизу
class PrefRow extends ConsumerWidget implements IosGroupRow {
  const PrefRow({super.key, required this.icon, required this.title, this.sub, required this.onTap, this.trailing, this.last = false, this.leading, this.value});
  final IconData icon;
  final String title;
  final String? sub;
  final String? value; // значение строки (язык «Русский»): в стиле iPhone — серым справа, вместо подписи
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading; // вместо значка (флаг языка)
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    if (iosStyleOf(ref)) return _ios(pal);
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
                child: AIcon(ico(icon), size: 20, color: pal.accent),
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: TextStyle(fontSize: 12.5, color: pal.muted))),
            ]),
          ),
          trailing ?? AIcon(ico(LucideIcons.chevronRight), size: 18, color: pal.muted),
        ]),
      ),
    ));
  }

  @override
  double get iosIndent => iosRowTextLeft; // линия под строкой — от начала текста

  // Стиль iPhone — системная строка списка iOS (CupertinoListTile): значок в цветном квадрате, название, справа —
  // значение серым и системная «›»; подписи под названием нет (как в «Настройках» iPhone)
  Widget _ios(Palette pal) => iosTile(
        leading: leading == null ? IosIconSquare(icon) : SizedBox(width: iosRowIcon, height: iosRowIcon, child: FittedBox(child: leading)),
        title: Text(title),
        additionalInfo: value == null ? null : Text(value!),
        trailing: trailing ?? const CupertinoListTileChevron(),
        onTap: onTap,
      );
}

/// Строка списка стиля iPhone без значка: название, справа — значение серым и «›» (системная CupertinoListTile)
class IosNavRow extends StatelessWidget implements IosGroupRow {
  const IosNavRow({super.key, required this.title, required this.onTap, this.value});
  final String title;
  final String? value;
  final VoidCallback onTap;
  @override
  double get iosIndent => iosRowIconLeft + 2;
  @override
  Widget build(BuildContext context) => iosTile(
        title: Text(title),
        additionalInfo: value == null ? null : Text(value!),
        trailing: const CupertinoListTileChevron(),
        onTap: onTap,
      );
}

/// Строка-действие стиля iPhone, как «Выключить» в «Настройках»: только название цветом акцента (или красным)
class IosActionRow extends ConsumerWidget implements IosGroupRow {
  const IosActionRow({super.key, required this.title, required this.onTap, this.destructive = false});
  final String title;
  final VoidCallback onTap;
  final bool destructive;
  @override
  double get iosIndent => iosRowIconLeft + 2;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return iosTile(
      title: Text(title, style: TextStyle(color: destructive ? sysColor(CupertinoColors.systemRed, dark: pal.dark) : pal.accent)),
      onTap: onTap,
    );
  }
}

/// Системное подтверждение iOS снизу экрана (CupertinoActionSheet): красное действие и «Отменить»
Future<void> iosConfirm(BuildContext context, {required String action, String? message, required VoidCallback onConfirm}) async {
  // на iPhone — настоящий UIAlertController (стекло iOS 26), на других — его повтор на Flutter
  final ok = await CNActionSheet.show<bool>(
    context: context,
    message: message,
    cancelLabel: t('Отменить'),
    actions: [CNActionSheetAction<bool>(label: action, value: true, isDestructive: true)],
  );
  if (ok == true) onConfirm();
}

/// .menu-item: значок цвета акцента, подпись, справа — дополнение (вкл/выкл, «новая»)
class MenuRow extends ConsumerWidget implements IosGroupRow {
  const MenuRow({super.key, required this.icon, required this.label, required this.onTap, this.extra, this.color, this.flat = false, this.last = false});
  final bool flat; // в окне — от края до края, без скругления (меню «Ещё»); во всплывающем меню — со скруглением
  final bool last; // последняя строка группы (линии в стиле iPhone рисует карточка группы)
  @override
  double get iosIndent => iosRowTextLeft; // линия под строкой — от начала текста
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? extra;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final ios = iosStyleOf(ref);
    final icon = ios ? iosIcon(this.icon) : this.icon;
    return Material(
      // стиль iPhone: строки меню в окне — белые на сером фоне, как в «Настройках» iPhone
      type: MaterialType.transparency,
      borderRadius: flat ? null : BorderRadius.circular(kRadius * 0.6),
      clipBehavior: flat ? Clip.none : Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ios && flat
            // стиль iPhone: системная строка списка iOS (CupertinoListTile) — значок в цветном квадрате, название,
            // справа значение серым и системная «›»
            ? iosTile(
                leading: IosIconSquare(this.icon, color: color),
                title: Text(label, style: color == null ? null : TextStyle(color: color)),
                additionalInfo: extra,
                trailing: const CupertinoListTileChevron(),
                onTap: onTap,
              )
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: flat ? 20 : 12, vertical: 10),
                child: Row(children: [
                  AIcon(ico(icon), size: ios ? 22 : 20, color: color ?? pal.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: TextStyle(fontSize: ios ? 16.5 : 15.7, color: color ?? pal.text))),
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
  Widget build(BuildContext context, WidgetRef ref) {
    // стиль iPhone: между группами в окне — промежуток цвета фона групп, во всплывающем меню — тонкая линия
    if (iosStyleOf(ref)) return full ? const SizedBox(height: 36) : Container(height: 0.5, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), color: paletteOf(ref).line);
    return Container(height: 1, margin: EdgeInsets.symmetric(horizontal: full ? 0 : 8, vertical: 4), color: paletteOf(ref).line);
  }
}

/// Подзаголовок группы (h4 в окнах веб-версии)
class GroupTitle extends ConsumerWidget {
  const GroupTitle(this.text, {super.key, this.dot});
  final String text;
  final Color? dot; // цветная точка (разделы книг в «Перейти»)
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final ios = iosStyleOf(ref);
    return Padding(
      // стиль iPhone: подзаголовок группы прописными, мелко и серым, как в «Настройках» iPhone
      padding: ios ? const EdgeInsets.only(top: 14, bottom: 0) : const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(children: [
        if (dot != null) ...[Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 6)],
        // iOS 26: заголовок группы — обычными буквами, полужирный, серый (как «Яркость» в «Экран и яркость»)
        Flexible(child: Text(text, style: ios ? TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.muted) : TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: pal.muted))),
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
    // стиль iPhone: системный переключатель iOS (зелёный)
    if (iosStyleOf(ref)) return iosSwitch(pal, value, onChanged);
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
/// Системный переключатель: на iPhone (iOS 26) — настоящий UISwitch, иначе — CupertinoSwitch
Widget iosSwitch(Palette pal, bool value, ValueChanged<bool>? onChanged, {String? label}) => nativeGlass
    // системный вид — 44 по высоте (чтобы переключатель не обрезался), в строке он занимает 36: строка с ним — 52,
    // как в UI Kit (иначе 44 + отступы давали 60)
    ? SizedBox(
        height: 36,
        child: OverflowBox(
          minHeight: 44,
          maxHeight: 44,
          fit: OverflowBoxFit.deferToChild,
          child: CNSwitch(value: value, onChanged: onChanged ?? (_) {}, enabled: onChanged != null, color: iosGreenOf(pal), autoHideOnModal: false, semanticLabel: label),
        ),
      )
    : CupertinoSwitch(value: value, onChanged: onChanged, activeTrackColor: iosGreenOf(pal));

class SwitchRow extends ConsumerWidget implements IosGroupRow, IosFooterRow {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  double get iosIndent => iosRowIconLeft + 2;
  // стиль iPhone: пояснение — серым текстом под карточкой (вместо значка «i»)
  @override
  String? get iosFooter => hint;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    // стиль iPhone: системная строка списка iOS с системным переключателем
    if (iosStyleOf(ref)) {
      return iosTile(
        title: Row(children: [Flexible(child: Text(label)), if (hint != null && !IosInCard.of(context)) Hint(hint!)]),
        trailing: iosSwitch(pal, value, onChanged, label: label),
        // iPhone: строку переключают только самим переключателем (нажатие и свайп — его, без задержки)
        onTap: nativeGlass ? null : () => onChanged(!value),
      );
    }
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(child: Text(label, style: iosStyleOf(ref) ? TextStyle(fontSize: 16.5, color: pal.text) : TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text))),
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
    final ios = iosStyleOf(ref);
    // стиль iPhone: системный переключатель-сегменты iOS (до пяти вариантов — они помещаются в строку)
    if (ios && options.length <= 5 && nativeGlass) {
      // iPhone: системный UISegmentedControl — капсула 32 pt, как в UI Kit Apple
      return SizedBox(
        width: double.infinity,
        child: CNSegmentedControl(
          labels: [for (final o in options) o.$2],
          selectedIndex: options.indexWhere((o) => o.$1 == widget.value),
          onValueChanged: (i) {
            if (i >= 0 && i < options.length) widget.onChanged(options[i].$1);
          },
          height: 32,
          autoHideOnModal: false,
        ),
      );
    }
    if (ios && options.length <= 5) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<int>(
          groupValue: options.indexWhere((o) => o.$1 == widget.value),
          onValueChanged: (i) {
            if (i != null && i >= 0) widget.onChanged(options[i].$1);
          },
          children: {
            for (var i = 0; i < options.length; i++)
              i: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(options[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: pal.text))),
          },
        ),
      );
    }
    TextStyle style(bool on) => TextStyle(fontSize: ios ? 13.5 : 14.08, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: on ? FontWeight.w600 : (ios ? FontWeight.w500 : FontWeight.w400), color: on && !ios ? pal.accent : pal.text);
    return Container(
      padding: EdgeInsets.all(ios ? 2 : 3),
      decoration: BoxDecoration(color: ios ? iosFill(pal) : pal.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(ios ? 9 : kRadius * 0.75)),
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
                    color: ios ? (pal.dark ? const Color(0xff636366) : Colors.white) : pal.panel,
                    borderRadius: BorderRadius.circular(ios ? 7 : kRadius * 0.6),
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

/// Строка ввода без рамки: текст и подсказка — строго по центру по высоте. Высота строки задана жёстко (strut),
/// подсказку рисуем сами тем же стилем и в той же точке, что и текст: подсказка InputDecoration на разных шрифтах и
/// платформах съезжает (вниз, а то и под рамку). Строчные буквы визуально ниже середины строки — поднимаем на 1.
class BareField extends StatelessWidget {
  const BareField({
    super.key,
    required this.controller,
    required this.style,
    required this.hintColor,
    this.focusNode,
    this.hint,
    this.padding = EdgeInsets.zero,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.autocorrect = true,
    this.cursorColor,
    this.onTapOutside,
  });
  final TapRegionCallback? onTapOutside;
  final TextEditingController controller;
  final TextStyle style;
  final Color hintColor;
  final FocusNode? focusNode;
  final String? hint;
  final EdgeInsetsGeometry padding;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final bool autofocus, autocorrect;
  final Color? cursorColor;

  @override
  Widget build(BuildContext context) {
    final st = style.copyWith(leadingDistribution: TextLeadingDistribution.even);
    final strut = StrutStyle(fontSize: st.fontSize, height: st.height ?? 1.25, leadingDistribution: TextLeadingDistribution.even, forceStrutHeight: true);
    return Padding(
      padding: padding,
      child: Transform.translate(
        offset: const Offset(0, -1),
        child: Stack(alignment: textAlign == TextAlign.center ? Alignment.center : AlignmentDirectional.centerStart, children: [
          if (hint != null)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, v, _) => v.text.isEmpty
                  ? IgnorePointer(
                      child: Text(hint!, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, textAlign: textAlign, strutStyle: strut, style: st.copyWith(color: hintColor)),
                    )
                  : const SizedBox.shrink(),
            ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            autocorrect: autocorrect,
            enableSuggestions: autocorrect,
            keyboardType: keyboardType,
            textAlign: textAlign,
            textInputAction: textInputAction,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            onTapOutside: onTapOutside,
            cursorColor: cursorColor,
            maxLines: 1,
            style: st,
            strutStyle: strut,
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ]),
      ),
    );
  }
}

/// Поле ввода (.input-wrap): фон, скругление, рамка (в фокусе — цвет акцента и кольцо), значок слева, справа — крестик
/// «Очистить» (когда что-то вписано) или своя кнопка. Текст и подсказка — строго по центру (BareField)
class AobInput extends ConsumerStatefulWidget {
  const AobInput({
    super.key,
    required this.controller,
    this.hint,
    this.icon = LucideIcons.search,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.trailing,
    this.clearable = true,
    this.autocorrect = true,
    this.textInputAction,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.style,
    this.height = 46,
  });
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus, clearable, autocorrect;
  final Widget? trailing;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final TextStyle? style;
  final double height;

  @override
  ConsumerState<AobInput> createState() => _AobInputState();
}

class _AobInputState extends ConsumerState<AobInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final w = widget;
    final focused = _focus.hasFocus;
    final ios = iosStyleOf(ref);
    final style = w.style ?? TextStyle(fontSize: ios ? 17 : 16, height: 1.25, color: pal.text);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus, // нажатие на поля рамки — тоже в поле
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        // стиль iPhone (iOS 26, как «Имя устройства»): высота строки 52, заливка карточки, скругление Apple,
        // на одной линии с карточками групп (20 от края экрана)
        height: ios ? iosRowHeight : w.height,
        margin: ios ? EdgeInsets.symmetric(horizontal: iosEdge - 16) : null,
        decoration: ios
            ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRowHeight / 2))
            : BoxDecoration(
                color: pal.bg,
                borderRadius: BorderRadius.circular(kRadius * 0.75),
                border: Border.all(color: focused ? pal.accent : pal.line),
                boxShadow: focused ? [BoxShadow(color: pal.accent.withValues(alpha: 0.2), spreadRadius: 3)] : null,
              ),
        child: Row(children: [
          if (w.icon != null) ...[SizedBox(width: ios ? 16 : 12), Icon(ios ? iosIcon(w.icon!) : w.icon, size: ios ? 18 : 18, color: pal.muted)],
          Expanded(
            child: BareField(
              controller: w.controller,
              focusNode: _focus,
              hint: w.hint,
              style: style,
              hintColor: ios ? sysColor(CupertinoColors.placeholderText, dark: pal.dark) : pal.muted,
              cursorColor: pal.accent,
              padding: EdgeInsets.only(left: w.icon != null ? 8 : (ios ? 20 : 12), right: 4),
              autofocus: w.autofocus,
              autocorrect: w.autocorrect,
              textAlign: w.textAlign,
              textInputAction: w.textInputAction,
              keyboardType: w.keyboardType,
              onChanged: w.onChanged,
              onSubmitted: w.onSubmitted,
            ),
          ),
          // Когда в поле что-то вписано — крестик «Очистить» (если своей кнопки справа нет), как .search-clear в веб-версии
          if (w.trailing != null)
            w.trailing!
          else if (w.clearable)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: w.controller,
              builder: (context, v, _) => v.text.isEmpty
                  ? SizedBox(width: ios ? 20 : 8)
                  : ios
                      // стиль iPhone: системный серый кружок с крестиком
                      ? Semantics(
                          button: true,
                          label: t('Очистить'),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              w.controller.clear();
                              w.onChanged?.call('');
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 12, 18, 12),
                              child: Icon(CupertinoIcons.xmark_circle_fill, size: 19, color: sysColor(CupertinoColors.tertiaryLabel, dark: pal.dark)),
                            ),
                          ),
                        )
                      : Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: IconBtn(
                        icon: LucideIcons.x,
                        subtle: true,
                        size: 18,
                        tooltip: t('Очистить'),
                        onTap: () {
                          w.controller.clear();
                          w.onChanged?.call('');
                        },
                      ),
                    ),
            )
          else
            const SizedBox(width: 8),
        ]),
      ),
    );
  }
}

/// Круглая кнопка поверх текста (стрелки глав, «Слушать»): 44×44, полупрозрачная панель, тень
class RoundFab extends ConsumerWidget {
  const RoundFab({super.key, required this.icon, required this.onTap, this.tooltip, this.glass = true});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool glass; // на iOS 26 — системное стекло (false — когда панелей слишком много)
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    final icon = iosStyleOf(ref) ? iosIcon(this.icon) : this.icon;
    if (glass && nativeGlass) return GlassFab(icon: icon, onTap: onTap, label: tooltip, tint: pal.text);
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
        child: Material(type: MaterialType.transparency, shape: const CircleBorder(), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: AIcon(ico(icon), size: 22, color: pal.text))),
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
      // не шире 280, как .hint-pop: на широком окне длинное пояснение не растягивается в одну строку
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: pal.bar,
        borderRadius: BorderRadius.circular(kRadius * 0.8),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      textStyle: TextStyle(fontSize: 13.4, height: 1.45, color: pal.barText),
      child: SizedBox(width: 26, height: 24, child: AIcon(ico(LucideIcons.circleAlert), size: 15, color: pal.muted)),
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
      iosStyleOf(ref)
          ? SizedBox(width: widget.size, height: widget.size, child: CupertinoActivityIndicator(radius: widget.size / 2.2, color: widget.color))
          : RotationTransition(turns: _c, child: AIcon(ico(LucideIcons.loaderCircle), size: widget.size, color: widget.color ?? paletteOf(ref).muted));
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
            // в одну строку — «таблетка», в несколько — скруглённый прямоугольник, а не овал
            borderRadius: BorderRadius.circular(22),
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
/// Подложка карточек в окнах (как «Свой план»): чистая нейтральная, чуть темнее окна — карточка видна без жирной рамки
Color cardFill(Palette pal) => mix(pal.text, 0.055, pal.panel);

/// Содержимое — от края до края окна (поверх его полей 16 px): строки списков, линии
Widget bleed(Widget child) => _bleed(child);

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
    Widget tab((T, String, int?) x, {int? flex}) {
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
            alignment: flex != null ? Alignment.center : null,
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
      return flex != null ? Expanded(flex: flex, child: w) : w;
    }

    // стиль iPhone: до четырёх вкладок — системный сегментный переключатель; больше — ряд капсул (как фильтры в
    // «Музыке»): подчёркнутых вкладок в iOS нет
    if (iosStyleOf(ref)) {
      String name((T, String, int?) x) => x.$3 == null ? x.$2 : '${x.$2} ${x.$3}';
      if (tabs.length <= 4) {
        return Padding(
          padding: EdgeInsets.fromLTRB(iosEdge, 6, iosEdge, 8),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: tabs.indexWhere((x) => x.$1 == value),
              onValueChanged: (i) {
                if (i != null && i >= 0) onChanged(tabs[i].$1);
              },
              children: {
                for (final (i, x) in tabs.indexed)
                  i: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(name(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: pal.text))),
              },
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: FadeRow(gap: 8, padding: EdgeInsets.symmetric(horizontal: iosEdge), children: [
          for (final x in tabs) AobChip(label: x.$2, count: x.$3, on: x.$1 == value, onTap: () => onChanged(x.$1)),
        ]),
      );
    }
    final bar = LayoutBuilder(builder: (context, box) {
      final widths = [for (final x in tabs) _textWidth('${x.$2}${x.$3 != null ? ' ${x.$3}' : ''}', label, scale) + 24];
      final need = widths.fold<double>(0, (a, w) => a + w);
      final inner = box.maxWidth - 32;
      // поровну — если каждая подпись влезает в свою долю; иначе доля по длине подписи, чтобы длинная не обрезалась
      final even = widths.fold<double>(0, math.max) * tabs.length <= inner;
      return Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
        child: need <= inner
            ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [for (final (i, x) in tabs.indexed) tab(x, flex: even ? 1 : (widths[i] * 10).round())]))
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

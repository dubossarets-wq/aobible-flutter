// Раскрытый проигрыватель на весь экран (AudioPlayer.jsx): сверху ручка и название главы; в центре — стихи главы
// крупно, «караоке»: звучащий стих чёткий, соседние полупрозрачные и размытые. Текст сам держит звучащий стих
// посередине; человек листает пальцем — размытие снимается, через 3,5 с без касаний текст возвращается к стиху.
// Нажатие на стих — запись идёт с начала этого стиха. Ниже — перемотка, ⏮ ▶/⏸ ⏭, громкость, скорость, таймер сна,
// скачивание книги, закрытие. Закрывается свайпом вниз за шапку или стрелкой вниз.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/markup.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'audio_bar.dart';
import 'audio_download.dart';
import 'audio_engine.dart';
import 'audio_logic.dart';
import '../../ui/ios_style.dart';

bool _open = false;

void openAudioPlayer(BuildContext context) {
  if (_open) return;
  _open = true;
  // нижние вкладки остаются поверх проигрывателя (его кнопки — над ними); нажатие на вкладку закрывает его
  Navigator.of(context, rootNavigator: true)
      .push(PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => const AudioPlayerPage(),
        transitionsBuilder: (_, anim, _, child) =>
            SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)).animate(anim), child: child),
      ))
      .whenComplete(() => _open = false);
}

const _backAfter = Duration(milliseconds: 3500); // через сколько после ручной прокрутки текст возвращается к стиху

class AudioPlayerPage extends ConsumerStatefulWidget {
  const AudioPlayerPage({super.key});
  @override
  ConsumerState<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends ConsumerState<AudioPlayerPage> {
  final _sc = ItemScrollController();
  final _e = AudioEngine.I;
  List<(int, String)> _verses = const [];
  String _versesKey = '';
  String _names = '';
  String _namesKey = '';
  bool _manual = false;
  Timer? _backTimer;
  double? _seek;
  int _lastActive = -2;
  bool _placed = false;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _e.state.addListener(_onState);
  }

  @override
  void dispose() {
    _e.state.removeListener(_onState);
    _backTimer?.cancel();
    super.dispose();
  }

  void _onState() {
    final a = _e.s;
    if (!a.canExpand) {
      // Запись выключили — сворачиваем
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    if (mounted) setState(() {});
  }

  void _loadVerses(AudioState a) {
    final r = a.ref!;
    final key = '${a.moduleId}|${r.book}.${r.chapter}';
    if (key == _versesKey) return;
    _versesKey = key;
    _lastActive = -2;
    try {
      _verses = [
        for (final it in loadBook(a.moduleId!, r.book).items)
          if (it.kind == ItemKind.verse && it.chapter == r.chapter) (it.verse, plainText(it.text)),
      ];
    } catch (_) {
      _verses = const [];
    }
  }

  void _loadNames(AudioState a) {
    final key = '${a.moduleId}|${a.source}';
    if (key == _namesKey) return;
    _namesKey = key;
    final bible = ModuleStore.instance.get(a.moduleId ?? '')?.name ?? '';
    final rec = ModuleStore.instance.get(a.source ?? '');
    _names = [bible, rec?.title ?? rec?.name ?? ''].where((x) => x.isNotEmpty).join(' · ');
  }

  void _toActive(int index, {bool smooth = true}) {
    if (!_sc.isAttached || index < 0) return;
    if (smooth && _placed) {
      _sc.scrollTo(index: index, alignment: 0.4, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
    } else {
      _sc.jumpTo(index: index, alignment: 0.4);
    }
    _placed = true;
  }

  void _userScroll() {
    if (!_manual) setState(() => _manual = true);
    _backTimer?.cancel();
    _backTimer = Timer(_backAfter, () {
      if (!mounted) return;
      setState(() => _manual = false);
      _toActive(_lastActive);
    });
  }

  void _endManual() {
    _backTimer?.cancel();
    if (_manual) setState(() => _manual = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = _e.s;
    if (!a.canExpand) return const SizedBox.shrink();
    final pal = ref.watch(settingsProvider).palette;
    _loadVerses(a);
    _loadNames(a);
    final r = a.ref!;
    final active = _verses.indexWhere((v) => v.$1 == r.verse);
    if (active != _lastActive) {
      _lastActive = active;
      if (!_manual) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _toActive(active) : null);
    }
    final title = '${Books.instance.meta(r.book).name} ${r.chapter}';
    final bg = pal.bg;
    final top = Color.lerp(bg, pal.accent, 0.22)!, mid = Color.lerp(bg, pal.accent, 0.08)!;
    return Transform.translate(
      offset: Offset(0, _drag),
      child: Scaffold(
        backgroundColor: bg,
        body: Container(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, mid, bg], stops: const [0, 0.42, 1])),
          child: SafeArea(
            child: Column(children: [
              // Шапка: ручка, свернуть, название главы. Свайп вниз за шапку закрывает
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(0, 600)),
                onVerticalDragEnd: (d) {
                  final close = _drag > 110 || (d.primaryVelocity ?? 0) > 700;
                  setState(() => _drag = 0);
                  if (close) Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                  child: Column(children: [
                    Container(width: 42, height: 5, margin: const EdgeInsets.only(top: 2, bottom: 6), decoration: BoxDecoration(color: pal.text.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(3))),
                    // .ap-head-row: промежуток 8; .ap-title: колонка по центру, промежуток 2
                    Row(children: [
                      Semantics(
                        button: true,
                        label: t('Свернуть проигрыватель'),
                        child: InkResponse(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: pal.text.withValues(alpha: 0.08)), child: Icon(ico(LucideIcons.chevronDown), size: 26, color: pal.text)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(spacing: 2, children: [
                          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17.6, fontWeight: FontWeight.w700, color: pal.text, height: 1.25)),
                          if (_names.isNotEmpty) Text(_names, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.8, color: pal.muted, height: 1.3)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      const SizedBox(width: 44),
                    ]),
                  ]),
                ),
              ),
              Expanded(child: _lyrics(pal, active, r)),
              _controls(a, pal, r),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _lyrics(Palette pal, int active, VerseRef r) {
    final w = MediaQuery.sizeOf(context).width;
    final fs = (w * 0.056).clamp(20.8, 29.6);
    return LayoutBuilder(builder: (context, box) {
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, 0.15, 0.85, 1]).createShader(rect),
        child: NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            if (n.direction != ScrollDirection.idle) {
              _userScroll();
            } else if (_manual) {
              _userScroll(); // отпустили — отсчёт заново
            }
            return false;
          },
          child: ScrollablePositionedList.builder(
            itemScrollController: _sc,
            initialScrollIndex: active < 0 ? 0 : active,
            initialAlignment: 0.4,
            padding: EdgeInsets.symmetric(vertical: box.maxHeight * 0.45, horizontal: 18),
            itemCount: _verses.length,
            itemBuilder: (_, i) {
              final d = active < 0 ? 4 : (i - active).abs().clamp(0, 4);
              return _VerseLine(
                number: _verses[i].$1,
                text: _verses[i].$2,
                d: d,
                manual: _manual,
                fontSize: fs.toDouble(),
                pal: pal,
                onTap: () {
                  _endManual();
                  _e.playVerse(VerseRef(r.book, r.chapter, _verses[i].$1));
                },
              );
            },
          ),
        ),
      );
    });
  }

  Widget _controls(AudioState a, Palette pal, VerseRef r) {
    final left = sleepLeftMinutes(a.sleep);
    final sleepLabel = a.sleep == null ? t('Выкл') : a.sleep!.kind == 'chapter' ? t('Конец главы') : t('{n} мин', {'n': '${left ?? a.sleep!.minutes}'});
    // .ap-controls: промежуток 10 (14 при высоте окна от 760 px), поля 4 22 max(22, нижний отступ − 8);
    // есть нижние вкладки — кнопки над ними
    final gap = MediaQuery.sizeOf(context).height >= 760 ? 14.0 : 10.0;
    final bottom = tabBarInset.value > 0 ? tabBarInset.value + 6 : math.max(22.0, MediaQuery.paddingOf(context).bottom - 8);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 4, 22, bottom),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: [
            if (a.error != null) Text(a.error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.4, color: _danger)),
            DownloadNote(pal: pal, center: true, border: false, gap: gap),
            // Перемотка
            ValueListenableBuilder<TimeSnap>(
              valueListenable: _e.time,
              builder: (_, tm, _) {
                final len = tm.len;
                final pos = (_seek ?? tm.pos).clamp(0, len > 0 ? len : 1).toDouble();
                return Column(children: [
                  SizedBox(
                    height: 24,
                    child: SliderTheme(
                      data: _sliderTheme(pal),
                      child: Semantics(
                        label: t('Место в записи'),
                        value: t('{cur} из {total}', {'cur': clock(pos), 'total': clock(len)}),
                        child: Slider(
                          min: 0,
                          max: len > 0 ? len : 1,
                          value: pos,
                          onChanged: len > 0 ? (v) => setState(() => _seek = v) : null,
                          onChangeEnd: (v) {
                            setState(() => _seek = null);
                            _e.seekChapter(v);
                          },
                        ),
                      ),
                    ),
                  ),
                  // .ap-times: отступ сверху 2, 12,5 px
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(clock(pos), style: TextStyle(fontSize: 12.5, color: pal.muted, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                      Text('−${clock((len - pos).clamp(0, double.infinity))}', style: TextStyle(fontSize: 12.5, color: pal.muted, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                    ]),
                  ),
                ]);
              },
            ),
            // .ap-transport: промежуток 28; .ap-btn 60×60 (значок 30), .ap-play 78×78 (значок 34)
            Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 28, children: [
              _big(Icons.skip_previous_rounded, 38, () => _e.stepVerse(-1), pal, t('Предыдущий стих')),
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: pal.accent.withValues(alpha: 0.38), blurRadius: 26, offset: const Offset(0, 8))]),
                child: audioPlayButton(a, pal, 78, iconSize: 34),
              ),
              _big(Icons.skip_next_rounded, 38, () => _e.stepVerse(1), pal, t('Следующий стих')),
            ]),
            // Громкость (.ap-volume: промежуток 10, значки 18)
            Row(spacing: 10, children: [
              Icon(ico(LucideIcons.volume1), size: 18, color: pal.muted),
              Expanded(
                child: SizedBox(
                  height: 24,
                  child: SliderTheme(
                    data: _sliderTheme(pal),
                    child: Semantics(
                      label: t('Громкость'),
                      value: '${(a.volume * 100).round()}%',
                      child: Slider(min: 0, max: 1, value: a.volume, onChanged: (v) => _e.setVolume(v)),
                    ),
                  ),
                ),
              ),
              Icon(ico(LucideIcons.volume2), size: 18, color: pal.muted),
            ]),
            // .ap-extras: между краями, промежуток 8
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, spacing: 8, children: [
              _ApChip(
                onTap: () {
                  final i = rates.indexOf(a.rate);
                  _e.setRate(rates[(i + 1) % rates.length]);
                },
                label: '${t('Скорость')}: ${rateText(a.rate)}',
                pal: pal,
                child: Text(rateText(a.rate)),
              ),
              _ApChip(
                onTap: () => _openSleep(a, pal),
                on: a.sleep != null,
                label: '${t('Таймер сна')}: $sleepLabel',
                pal: pal,
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  Icon(ico(LucideIcons.moon), size: 16, color: a.sleep != null ? pal.accent : pal.text),
                  if (a.sleep != null) Text(sleepLabel),
                ]),
              ),
              if (a.source != null) DownloadButton(audioId: a.source!, book: r.book, size: 20, pal: pal),
              InkResponse(
                onTap: _e.stop,
                radius: 24,
                child: SizedBox(width: 40, height: 40, child: Icon(ico(LucideIcons.x), size: 20, color: pal.text, semanticLabel: t('Закрыть аудио'))),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // Ползунки: дорожка 5 px, бегунок 17 px (радиус 8,5), без круга-нажатия
  SliderThemeData _sliderTheme(Palette pal) => SliderThemeData(
        trackHeight: 5,
        activeTrackColor: pal.accent,
        inactiveTrackColor: pal.text.withValues(alpha: 0.16),
        thumbColor: pal.accent,
        overlayColor: pal.accent.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 8.5),
        trackShape: const RoundedRectSliderTrackShape(),
      );

  Widget _big(IconData i, double size, VoidCallback f, Palette pal, String label) => Semantics(
        button: true,
        label: label,
        child: InkResponse(onTap: f, radius: 36, child: SizedBox(width: 60, height: 60, child: Icon(i, size: size, color: pal.text))),
      );

  void _openSleep(AudioState a, Palette pal) {
    // Свой нижний лист, как .sp-layer/.sp: затемнение text 18 %, скругление 28, ширина до 560, без шапки и крестика
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.panel,
      barrierColor: pal.text.withValues(alpha: 0.18),
      isScrollControlled: true,
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SleepPicker(initial: a.sleep?.minutes ?? 15, active: a.sleep != null, pal: pal),
    );
  }
}

const _danger = Color(0xFFB4412F); // --danger

/// .ap-chip: пилюля от 54×38, рамка line, фон panel 72 %, жирный 14 px; включённая — accent
class _ApChip extends StatelessWidget {
  const _ApChip({required this.child, required this.onTap, required this.pal, this.on = false, this.label});
  final Widget child;
  final VoidCallback onTap;
  final Palette pal;
  final bool on;
  final String? label;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          // включённая — рамка и надпись перетекают в цвет акцента
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: on ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 240),
            curve: Curves.fastOutSlowIn,
            child: child,
            builder: (context, v, child) => Container(
              constraints: const BoxConstraints(minWidth: 54, minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Color.lerp(pal.line, mix(pal.accent, 0.5, pal.line), v)!),
                color: mix(pal.panel, 0.72, Colors.transparent),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.1, color: Color.lerp(pal.text, pal.accent, v), fontFeatures: const [ui.FontFeature.tabularFigures()]),
                child: child!,
              ),
            ),
          ),
        ),
      );
}

/// Одна строка стиха в «караоке» (.ap-verse): чем дальше от звучащего, тем бледнее и размытее
class _VerseLine extends StatelessWidget {
  const _VerseLine({required this.number, required this.text, required this.d, required this.manual, required this.fontSize, required this.pal, required this.onTap});
  final int number, d;
  final String text;
  final bool manual;
  final double fontSize;
  final Palette pal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const op = [1.0, 0.5, 0.32, 0.22, 0.15];
    final opacity = manual ? (d == 0 ? 1.0 : 0.62) : op[d];
    // text-shadow: 0 0 4/6/8/9 px при прозрачном тексте — это размытие с σ = радиус / 2
    final sigma = manual || d == 0 ? 0.0 : [0.0, 2.0, 3.0, 4.0, 4.5][d];
    Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text.rich(
        TextSpan(children: [
          // .ap-vn: .5em, отступ справа .35em от собственного кегля, цвет accent
          WidgetSpan(alignment: PlaceholderAlignment.top, child: Padding(padding: EdgeInsets.only(right: fontSize * 0.5 * 0.35), child: Text('$number', style: TextStyle(fontSize: fontSize * 0.5, fontWeight: FontWeight.w700, color: pal.accent, height: 1)))),
          TextSpan(text: text),
        ]),
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, height: 1.3, color: pal.text),
      ),
    );
    if (sigma > 0) child = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal), child: child);
    final ms = Duration(milliseconds: manual ? 200 : 500);
    return Semantics(
      button: true,
      selected: d == 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedOpacity(
          duration: ms,
          opacity: opacity,
          // transform: scale(.95) с началом слева по центру, пока стих не звучит
          child: AnimatedScale(
            duration: ms,
            scale: manual || d == 0 ? 1 : 0.95,
            alignment: Alignment.centerLeft,
            child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child)),
          ),
        ),
      ),
    );
  }
}

// --- Таймер сна: лента минут, как у таймера в телефоне (.sp) -----------------------------------

const _spMax = 120; // минут на ленте
const _spStep = 12.0; // px на минуту

class SleepPicker extends StatefulWidget {
  const SleepPicker({super.key, required this.initial, required this.active, required this.pal});
  final int initial;
  final bool active;
  final Palette pal;
  @override
  State<SleepPicker> createState() => _SleepPickerState();
}

class _SleepPickerState extends State<SleepPicker> {
  late final ScrollController _c = ScrollController(initialScrollOffset: widget.initial * _spStep);
  late int _min = widget.initial;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _moveTo(int m) => _c.animateTo(m.clamp(0, _spMax) * _spStep, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final e = AudioEngine.I;
    final w = MediaQuery.sizeOf(context).width;
    final half = math.min(w, 560.0) / 2 - _spStep / 2;
    // .sp: поля 18 0 max(22, нижний отступ − 8); есть нижние вкладки — над ними
    final bottom = tabBarInset.value > 0 ? tabBarInset.value + 6 : math.max(22.0, MediaQuery.paddingOf(context).bottom - 8);
    final timeSize = (w * 0.13).clamp(41.6, 57.6).toDouble();
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 18, 0, bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          slider: true,
          label: t('Таймер сна'),
          value: t('{n} мин', {'n': '$_min'}),
          child: SizedBox(
            height: 88,
            child: Stack(alignment: Alignment.bottomCenter, children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
                    final m = (_c.offset / _spStep).round().clamp(0, _spMax);
                    if (m != _min) {
                      setState(() => _min = m);
                      HapticFeedback.selectionClick();
                    }
                    if (n is ScrollEndNotification && (_c.offset - m * _spStep).abs() > 0.5) _moveTo(m);
                  }
                  return false;
                },
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, 0.18, 0.82, 1]).createShader(r),
                  child: ListView.builder(
                    controller: _c,
                    scrollDirection: Axis.horizontal,
                    itemExtent: _spStep,
                    padding: EdgeInsets.symmetric(horizontal: half),
                    itemCount: _spMax + 1,
                    itemBuilder: (_, m) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _moveTo(m),
                      child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
                        // .sp-tick: чёрточка 3×34 на 14 px выше нижнего края; кратные 5 — яркие, с числом
                        Container(width: 3, height: 34, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: m % 5 == 0 ? pal.accent : pal.accent.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2))),
                        if (m % 5 == 0)
                          Positioned(bottom: 56, child: SizedBox(width: 40, child: Text('$m', textAlign: TextAlign.center, softWrap: false, overflow: TextOverflow.visible, style: TextStyle(fontSize: 16.8, fontWeight: FontWeight.w600, color: pal.accent, fontFeatures: const [ui.FontFeature.tabularFigures()])))),
                      ]),
                    ),
                  ),
                ),
              ),
              IgnorePointer(child: CustomPaint(size: const Size(16, 11), painter: _MarkPainter(pal.accent))),
            ]),
          ),
        ),
        // .sp-row: поля 8 22 0, промежуток 12
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, spacing: 12, children: [
            Opacity(
              opacity: _min == 0 ? 0.45 : 1,
              child: Material(
                color: mix(pal.accent, 0.16, pal.panel),
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _min == 0
                      ? null
                      : () {
                          e.setSleepMinutes(_min);
                          Navigator.pop(context);
                        },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    alignment: Alignment.center,
                    child: Text(t('Запустить таймер'), style: TextStyle(fontSize: 16.3, fontWeight: FontWeight.w700, color: pal.accent)),
                  ),
                ),
              ),
            ),
            // Крупный текст телефона (×1.3) не помещался рядом с кнопкой — время ужимается, а не вылезает за край
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(fmtMin(_min), style: TextStyle(fontSize: timeSize, fontWeight: FontWeight.w300, height: 1, letterSpacing: -0.02 * timeSize, color: pal.accent, fontFeatures: const [ui.FontFeature.tabularFigures()])),
              ),
            ),
          ]),
        ),
        // .sp-more: слева, перенос строк, отступ сверху 14
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              _SpChip(t('До конца главы'), pal, () {
                e.setSleepChapter();
                Navigator.pop(context);
              }),
              if (widget.active)
                _SpChip(t('Выключить таймер'), pal, () {
                  e.clearSleep();
                  Navigator.pop(context);
                }),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Кнопки под лентой — тот же .ap-chip, что в проигрывателе
class _SpChip extends StatelessWidget {
  const _SpChip(this.label, this.pal, this.onTap);
  final String label;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _ApChip(onTap: onTap, pal: pal, child: Text(label));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) => c.drawPath(Path()..moveTo(s.width / 2, 0)..lineTo(s.width, s.height)..lineTo(0, s.height)..close(), Paint()..color = color);
  @override
  bool shouldRepaint(_MarkPainter o) => o.color != color;
}

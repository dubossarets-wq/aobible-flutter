// Раскрытый проигрыватель на весь экран (AudioPlayer.jsx): сверху ручка и название главы; в центре — стихи главы
// крупно, «караоке»: звучащий стих чёткий, соседние полупрозрачные и размытые. Текст сам держит звучащий стих
// посередине; человек листает пальцем — размытие снимается, через 3,5 с без касаний текст возвращается к стиху.
// Нажатие на стих — запись идёт с начала этого стиха. Ниже — перемотка, ⏮ ▶/⏸ ⏭, громкость, скорость, таймер сна,
// скачивание книги, закрытие. Закрывается свайпом вниз за шапку или стрелкой вниз.
import 'dart:async';

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
import 'audio_bar.dart';
import 'audio_download.dart';
import 'audio_engine.dart';
import 'audio_logic.dart';

bool _open = false;

void openAudioPlayer(BuildContext context) {
  if (_open) return;
  _open = true;
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
                    Row(children: [
                      Semantics(
                        button: true,
                        label: t('Свернуть проигрыватель'),
                        child: InkResponse(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: pal.text.withValues(alpha: 0.08)), child: Icon(Icons.keyboard_arrow_down, size: 28, color: pal.text)),
                        ),
                      ),
                      Expanded(
                        child: Column(children: [
                          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17.6, fontWeight: FontWeight.w700, color: pal.text, height: 1.25)),
                          if (_names.isNotEmpty) Text(_names, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.8, color: pal.muted, height: 1.3)),
                        ]),
                      ),
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
    Widget chip(Widget child, VoidCallback f, {bool on = false, String? label}) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: f,
            child: Container(
              constraints: const BoxConstraints(minWidth: 54, minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? Color.lerp(pal.line, pal.accent, 0.5)! : pal.line),
                color: pal.panel.withValues(alpha: 0.72),
              ),
              child: DefaultTextStyle.merge(style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: on ? pal.accent : pal.text), child: child),
            ),
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (a.error != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(a.error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.4, color: Color(0xFFC0392B)))),
            DownloadNote(pal: pal, center: true, border: false),
            // Перемотка
            ValueListenableBuilder<TimeSnap>(
              valueListenable: _e.time,
              builder: (_, tm, _) {
                final len = tm.len;
                final pos = (_seek ?? tm.pos).clamp(0, len > 0 ? len : 1).toDouble();
                return Column(children: [
                  SliderTheme(
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(clock(pos), style: TextStyle(fontSize: 12.5, color: pal.muted, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                      Text('−${clock((len - pos).clamp(0, double.infinity))}', style: TextStyle(fontSize: 12.5, color: pal.muted, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                    ]),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _big(Icons.skip_previous, 34, () => _e.stepVerse(-1), pal, t('Предыдущий стих')),
              const SizedBox(width: 28),
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: pal.accent.withValues(alpha: 0.38), blurRadius: 26, offset: const Offset(0, 8))]),
                child: audioPlayButton(a, pal, 78),
              ),
              const SizedBox(width: 28),
              _big(Icons.skip_next, 34, () => _e.stepVerse(1), pal, t('Следующий стих')),
            ]),
            const SizedBox(height: 10),
            // Громкость
            Row(children: [
              Icon(Icons.volume_down, size: 20, color: pal.muted),
              Expanded(
                child: SliderTheme(
                  data: _sliderTheme(pal),
                  child: Semantics(
                    label: t('Громкость'),
                    value: '${(a.volume * 100).round()}%',
                    child: Slider(min: 0, max: 1, value: a.volume, onChanged: (v) => _e.setVolume(v)),
                  ),
                ),
              ),
              Icon(Icons.volume_up, size: 20, color: pal.muted),
            ]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              chip(Text(rateText(a.rate)), () {
                final i = rates.indexOf(a.rate);
                _e.setRate(rates[(i + 1) % rates.length]);
              }, label: '${t('Скорость')}: ${rateText(a.rate)}'),
              chip(
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bedtime_outlined, size: 17, color: a.sleep != null ? pal.accent : pal.text),
                  if (a.sleep != null) ...[const SizedBox(width: 6), Text(sleepLabel)],
                ]),
                () => _openSleep(a, pal),
                on: a.sleep != null,
                label: '${t('Таймер сна')}: $sleepLabel',
              ),
              if (a.source != null) DownloadButton(audioId: a.source!, book: r.book, size: 21, pal: pal),
              InkResponse(
                onTap: _e.stop,
                radius: 24,
                child: SizedBox(width: 40, height: 40, child: Icon(Icons.close, size: 22, color: pal.text, semanticLabel: t('Закрыть аудио'))),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  SliderThemeData _sliderTheme(Palette pal) => SliderThemeData(
        trackHeight: 5,
        activeTrackColor: pal.accent,
        inactiveTrackColor: pal.text.withValues(alpha: 0.16),
        thumbColor: pal.accent,
        overlayColor: pal.accent.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.5),
        trackShape: const RoundedRectSliderTrackShape(),
      );

  Widget _big(IconData i, double size, VoidCallback f, Palette pal, String label) => Semantics(
        button: true,
        label: label,
        child: InkResponse(onTap: f, radius: 36, child: SizedBox(width: 60, height: 60, child: Icon(i, size: size, color: pal.text))),
      );

  void _openSleep(AudioState a, Palette pal) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.panel,
      isScrollControlled: true,
      builder: (_) => SleepPicker(initial: a.sleep?.minutes ?? 15, active: a.sleep != null, pal: pal),
    );
  }
}

/// Одна строка стиха в «караоке»: чем дальше от звучащего, тем бледнее и размытее
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
    final sigma = manual || d == 0 ? 0.0 : [0.0, 1.4, 2.4, 3.2, 3.6][d];
    Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text.rich(
        TextSpan(children: [
          WidgetSpan(alignment: PlaceholderAlignment.top, child: Padding(padding: const EdgeInsets.only(right: 4), child: Text('$number', style: TextStyle(fontSize: fontSize * 0.5, fontWeight: FontWeight.w700, color: pal.accent, height: 1)))),
          TextSpan(text: text),
        ]),
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, height: 1.3, color: pal.text),
      ),
    );
    if (sigma > 0) child = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal), child: child);
    return Semantics(
      button: true,
      selected: d == 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedOpacity(duration: const Duration(milliseconds: 300), opacity: opacity, child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child))),
      ),
    );
  }
}

// --- Таймер сна: лента минут, как у таймера в телефоне -----------------------------------------

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
    final half = MediaQuery.sizeOf(context).width / 2 - _spStep / 2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 14),
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
                          Container(width: 3, height: m % 5 == 0 ? 34 : 34, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: m % 5 == 0 ? pal.accent : pal.accent.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2))),
                          if (m % 5 == 0)
                            Positioned(bottom: 56, child: SizedBox(width: 40, child: Text('$m', textAlign: TextAlign.center, softWrap: false, overflow: TextOverflow.visible, style: TextStyle(fontSize: 16.8, fontWeight: FontWeight.w600, color: pal.accent)))),
                        ]),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(child: CustomPaint(size: const Size(16, 11), painter: _MarkPainter(pal.accent))),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Color.lerp(pal.panel, pal.accent, 0.16), foregroundColor: pal.accent, minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 22), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                onPressed: _min == 0
                    ? null
                    : () {
                        e.setSleepMinutes(_min);
                        Navigator.pop(context);
                      },
                child: Text(t('Запустить таймер')),
              ),
              Text(fmtMin(_min), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w300, color: pal.accent, fontFeatures: const [ui.FontFeature.tabularFigures()])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
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
      ),
    );
  }
}

class _SpChip extends StatelessWidget {
  const _SpChip(this.label, this.pal, this.onTap);
  final String label;
  final Palette pal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: pal.line)),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: pal.text)),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) => c.drawPath(Path()..moveTo(s.width / 2, 0)..lineTo(s.width, s.height)..lineTo(0, s.height)..close(), Paint()..color = color);
  @override
  bool shouldRepaint(_MarkPainter o) => o.color != color;
}

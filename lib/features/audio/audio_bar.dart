// Мини-проигрыватель над вкладками (AudioBar.jsx): ▶/⏸, предыдущий/следующий стих, место, скорость, таймер сна,
// скачивание книги. Нажатие на свободную часть или свайп вверх — раскрыть проигрыватель на весь экран.
import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart' show livePositions;
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'audio_download.dart';
import 'audio_engine.dart';
import 'audio_player.dart';
import 'narrator_ui.dart';

const rates = [0.75, 1.0, 1.25, 1.5];
String rateText(double r) => '${r == r.roundToDouble() ? r.toInt() : r}×';

/// Подпись таймера сна для переключателя («Выкл», «15», «chapter»)
String sleepKey(SleepTimer? s) => s == null ? 'off' : s.kind == 'chapter' ? 'chapter' : '${s.minutes}';

List<(String, String)> sleepOptions() => [
      ('off', t('Выкл')),
      ('15', t('{n} мин', {'n': '15'})),
      ('30', t('{n} мин', {'n': '30'})),
      ('60', t('{n} мин', {'n': '60'})),
      ('chapter', t('Конец главы')),
    ];

void applySleepKey(String v) {
  final e = AudioEngine.I;
  if (v == 'off') {
    e.clearSleep();
  } else if (v == 'chapter') {
    e.setSleepChapter();
  } else {
    e.setSleepMinutes(int.parse(v));
  }
}

/// Сколько минут осталось до сна (или null)
int? sleepLeftMinutes(SleepTimer? s) => s?.kind == 'min' ? ((s!.until!.difference(DateTime.now()).inSeconds / 60).round()).clamp(1, 100000) : null;

class AudioBar extends ConsumerStatefulWidget {
  const AudioBar({super.key});
  @override
  ConsumerState<AudioBar> createState() => _AudioBarState();
}

class _AudioBarState extends ConsumerState<AudioBar> with SingleTickerProviderStateMixin {
  bool _opts = false;
  bool _optsShown = false; // панель настроек на экране (в том числе пока уезжает)
  Timer? _tick;
  // Раскрытие настроек: высота проигрывателя меняется один раз (в начале раскрытия / в конце скрытия), а плавно
  // едут только фон с рамкой и обрезка содержимого — это перерисовка без раскладки, глава под проигрывателем
  // не пересчитывается на каждом кадре
  // мягкий разгон и мягкая остановка: первый кадр раскрытия почти не сдвигается, поэтому нет «рывка»
  late final _oc = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final _ov = CurvedAnimation(parent: _oc, curve: Curves.fastOutSlowIn);
  final _panelH = _Height(); // высота панели настроек — пишется при раскладке, читается при рисовании

  void _toggleOpts() {
    if (!_opts) {
      setState(() => _opts = _optsShown = true);
      _oc.forward();
    } else {
      setState(() => _opts = false);
      _oc.reverse().then((_) {
        if (mounted && !_opts) setState(() => _optsShown = false);
      });
    }
  }

  // стрелки глав едут вместе с фоном проигрывателя (BarShiftDown)
  void _bindShift() {
    if (barShift.read == _hidden) return;
    barShift.read = _hidden;
    _oc.addListener(barShift.tick);
  }

  /// Сколько панели настроек ещё скрыто сверху (0 — раскрыта целиком)
  double _hidden() => _optsShown ? _panelH.value * (1 - _ov.value) : 0;

  @override
  void initState() {
    super.initState();
    // Обратный отсчёт таймера сна
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && AudioEngine.I.s.sleep?.kind == 'min') setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (barShift.read == _hidden) barShift.read = () => 0;
    _oc.removeListener(barShift.tick);
    _oc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bindShift();
    final pal = ref.watch(settingsProvider).palette;
    final e = AudioEngine.I;
    return ValueListenableBuilder<AudioState>(
      valueListenable: e.state,
      builder: (context, a, _) {
        if (!a.active) return const SizedBox.shrink();
        final left = sleepLeftMinutes(a.sleep);
        final sub = a.error != null && !a.offer
            ? a.error!
            : [if (a.narrated) t('Диктор'), if (left != null) t('сон через {n} мин', {'n': '$left'}) else if (a.sleep?.kind == 'chapter') t('до конца главы')].join(' · ');
        final r = a.ref;
        void expand() => a.canExpand ? openAudioPlayer(context) : null;
        final recorded = a.source != null && !a.narrated && r != null;
        return SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                // .audio-bar: рамка line, капсула (скругление 32 — как у панели вкладок; с настройками — 16), тень 0 10 34 rgba(0,0,0,.2)
                child: CustomPaint(
                  painter: _BarBg(pal: pal, anim: _ov, hidden: _hidden),
                  child: _ClipCached(
                    clipper: _BarClip(anim: _ov, hidden: _hidden),
                    child: Material(
                  color: Colors.transparent,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DownloadNote(pal: pal),
                    // .audio-opts: колонка с отступом 10, поля 12 12 4, линия снизу; проявляется вместе с фоном.
                    // Собрана и разложена заранее (скрыта, места не занимает) — при нажатии ничего не строится
                    Offstage(
                      offstage: !_optsShown,
                      child: FadeTransition(
                        opacity: _ov,
                        child: _Measure(
                        height: _panelH,
                        child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
                        child: Column(children: [
                          _Field(label: t('Скорость'), pal: pal, child: Segmented<double>(value: a.rate, options: [for (final x in rates) (x, rateText(x))], onChanged: e.setRate)),
                          const SizedBox(height: 10),
                          _Field(label: t('Таймер сна'), pal: pal, child: Segmented<String>(value: sleepKey(a.sleep), options: sleepOptions(), onChanged: applySleepKey)),
                          const SizedBox(height: 10),
                        ]),
                      ),
                      ),
                      ),
                    ),
                    if (a.offer)
                      NarratorOffer(pal: pal, error: a.error)
                    else
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: expand,
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) < -250) expand();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(children: [
                          // .audio-main: промежуток 2 между кнопками, у .audio-info отступ 0 6
                          _Btn(icon: Icons.skip_previous_rounded, label: t('Предыдущий стих'), onTap: () => e.stepVerse(-1), pal: pal, size: 24),
                          const SizedBox(width: 2),
                          _PlayBtn(a: a, pal: pal, size: 46, iconSize: 22),
                          const SizedBox(width: 2),
                          _Btn(icon: Icons.skip_next_rounded, label: t('Следующий стих'), onTap: () => e.stepVerse(1), pal: pal, size: 24),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                // Человек ушёл в другое место — место чтения становится кнопкой «вернуться»
                                // …а под ней — «▶ Слушать отсюда»: читать с места, где человек сейчас в тексте
                                if (r != null && !a.follow) ...[
                                  Tooltip(
                                    message: t('К звучащему месту'),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: () => e.resumeFollow(jump: true),
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
                                        decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          SizedBox(width: 14, child: Icon(LucideIcons.cornerUpLeft, size: 14, color: pal.accent)),
                                          const SizedBox(width: 5),
                                          Flexible(child: Text(Books.instance.formatRef(r.book, r.chapter, r.verse), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.4, color: pal.accent))),
                                        ]),
                                      ),
                                    ),
                                  ),
                                  if (Hub.listenFrom != null && livePositions[a.pane] != null)
                                    _ListenHere(
                                      here: livePositions[a.pane]!,
                                      pal: pal,
                                      onTap: (here) => Hub.listenFrom!(context, ref, a.pane, here),
                                    ),
                                ]
                                else
                                  Semantics(
                                    label: r == null ? null : '${Books.instance.formatRef(r.book, r.chapter, r.verse)} — ${t('Открыть проигрыватель')}',
                                    child: Text(r == null ? '' : Books.instance.formatRef(r.book, r.chapter, r.verse), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.2, color: pal.text)),
                                  ),
                                if (sub.isNotEmpty && (r == null || a.follow)) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.muted)),
                              ]),
                            ),
                          ),
                          if (recorded) DownloadButton(audioId: a.source!, book: r.book, pal: pal),
                          const SizedBox(width: 2),
                          _Btn(icon: LucideIcons.slidersHorizontal, label: t('Настройки чтения вслух'), onTap: _toggleOpts, pal: pal, on: _opts, size: 19),
                          const SizedBox(width: 2),
                          _Btn(icon: LucideIcons.x, label: t('Закрыть аудио'), onTap: e.stop, pal: pal, size: 20),
                        ]),
                      ),
                    ),
                  ]),
                ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Подпись над переключателем (.field + .field-label: 15 px, вес 500, отступ 6)
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.pal, required this.child});
  final String label;
  final Palette pal;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: pal.text)),
        const SizedBox(height: 6),
        child,
      ]);
}

/// «▶ Слушать отсюда» под «↰ место»: значок и текст — по тем же линиям, что у плашки выше. Подпись — самая полная,
/// какая помещается целиком: «Слушать отсюда · Мф. 2:5» → «Слушать отсюда» → «Отсюда» (без обрезки многоточием)
class _ListenHere extends StatelessWidget {
  const _ListenHere({required this.here, required this.pal, required this.onTap});
  final ValueNotifier<VerseRef> here;
  final Palette pal;
  final void Function(VerseRef) onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: pal.accent);
    final scale = MediaQuery.textScalerOf(context);
    return ValueListenableBuilder<VerseRef>(
      valueListenable: here,
      builder: (context, at, _) => LayoutBuilder(builder: (context, c) {
        final refText = Books.instance.formatRef(at.book, at.chapter, at.verse);
        final avail = c.maxWidth - 8 - 14 - 5 - 10; // поля и значок — как у плашки «↰ место»
        double w(String s) {
          final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 1, textScaler: scale)..layout();
          final v = tp.width;
          tp.dispose();
          return v;
        }

        final label = [
          '${t('Слушать отсюда')} · $refText',
          t('Слушать отсюда'),
          t('Отсюда'),
        ].firstWhere((s) => w(s) <= avail, orElse: () => t('Отсюда'));
        return Tooltip(
          message: '${t('Слушать отсюда')}: $refText',
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onTap(at),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 10, 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 14, child: Icon(LucideIcons.play, size: 12, color: pal.accent)),
                const SizedBox(width: 5),
                Flexible(child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: style)),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

/// Фон проигрывателя: тень, заливка и рамка; верх опускается на ещё скрытую часть панели настроек,
/// скругление — от 32 (капсула) к 16 (раскрыты настройки)
class _BarBg extends CustomPainter {
  _BarBg({required this.pal, required this.anim, required this.hidden}) : super(repaint: anim);
  final Palette pal;
  final Animation<double> anim;
  final double Function() hidden;
  @override
  void paint(Canvas canvas, Size size) {
    final r = _barRect(size, hidden(), anim.value);
    canvas.drawRRect(r.shift(const Offset(0, 10)), Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(34)));
    canvas.drawRRect(r, Paint()..color = pal.panel);
    canvas.drawRRect(r.deflate(0.5), Paint()
      ..style = PaintingStyle.stroke
      ..color = pal.line);
  }

  @override
  bool shouldRepaint(_BarBg old) => old.pal != pal;
}

/// Обрезка по фону; содержимое — в своём слое, поэтому при каждом кадре не перерисовывается
class _ClipCached extends StatelessWidget {
  const _ClipCached({required this.clipper, required this.child});
  final CustomClipper<Path> clipper;
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipPath(clipper: clipper, child: RepaintBoundary(child: child));
}

class _BarClip extends CustomClipper<Path> {
  _BarClip({required this.anim, required this.hidden}) : super(reclip: anim);
  final Animation<double> anim;
  final double Function() hidden;
  @override
  Path getClip(Size size) => Path()..addRRect(_barRect(size, hidden(), anim.value));
  @override
  bool shouldReclip(_BarClip old) => false;
}

/// Высота, записанная при раскладке (_Measure), — чтобы рисование не лезло в дерево виджетов
class _Height {
  double value = 0;
}

class _Measure extends SingleChildRenderObjectWidget {
  const _Measure({required this.height, super.child});
  final _Height height;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(height);
  @override
  void updateRenderObject(BuildContext context, _RenderMeasure r) => r.height = height;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.height);
  _Height height;
  @override
  void performLayout() {
    super.performLayout();
    height.value = size.height;
  }
}

RRect _barRect(Size size, double top, double t) =>
    RRect.fromRectAndRadius(Rect.fromLTRB(0, top, size.width, size.height), Radius.circular(lerpDouble(32, 16, t)!));

/// .audio-btn: круглая 40×40; включённая — фон accent 12 % и цвет accent
class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap, required this.pal, this.size = 20, this.on = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Palette pal;
  final double size;
  final bool on;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            decoration: on ? BoxDecoration(shape: BoxShape.circle, color: pal.accent.withValues(alpha: 0.12)) : null,
            child: Icon(icon, size: size, color: on ? pal.accent : pal.text),
          ),
        ),
      );
}

/// ▶ / ⏸ / крутилка загрузки (Loader2 со .spin) — круглая кнопка акцентного цвета
class _PlayBtn extends StatelessWidget {
  const _PlayBtn({required this.a, required this.pal, required this.size, required this.iconSize});
  final AudioState a;
  final Palette pal;
  final double size, iconSize;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: a.playing ? t('Пауза') : t('Слушать'),
        child: GestureDetector(
          onTap: () => a.playing ? AudioEngine.I.pause() : AudioEngine.I.resume(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: pal.accent),
            child: a.loading ? Center(child: _Spin(icon: LucideIcons.loader2, size: iconSize * 0.9, color: pal.onAccent)) : Icon(a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: iconSize * 1.3, color: pal.onAccent), // залитые
          ),
        ),
      );
}

/// .spin: оборот за секунду, равномерно
class _Spin extends StatefulWidget {
  const _Spin({required this.icon, required this.size, required this.color});
  final IconData icon;
  final double size;
  final Color color;
  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Дуга рисуется сама, а не значком шрифта: у глифа центр смещён на пиксель-другой, и при вращении он «прыгал».
  // Вращается готовая картинка в своём слое — кадр не перерисовывает кнопку
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: RotationTransition(
          turns: _c,
          child: SizedBox.square(dimension: widget.size, child: CustomPaint(painter: _Arc(widget.color, widget.size * 0.11))),
        ),
      );
}

/// Как Loader2: три четверти окружности со скруглёнными концами
class _Arc extends CustomPainter {
  _Arc(this.color, this.stroke);
  final Color color;
  final double stroke;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawArc(r, 0, 4.7, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_Arc old) => old.color != color || old.stroke != stroke;
}

/// Кнопка ▶/⏸ для раскрытого проигрывателя (.ap-play: 78 px, значок 34)
Widget audioPlayButton(AudioState a, Palette pal, double size, {double? iconSize}) => _PlayBtn(a: a, pal: pal, size: size, iconSize: iconSize ?? size * 0.5);

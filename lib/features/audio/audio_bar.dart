// Мини-проигрыватель над вкладками (AudioBar.jsx): ▶/⏸, предыдущий/следующий стих, место, скорость, таймер сна,
// скачивание книги. Нажатие на свободную часть или свайп вверх — раскрыть проигрыватель на весь экран.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
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

class _AudioBarState extends ConsumerState<AudioBar> {
  bool _opts = false;
  Timer? _tick;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                // .audio-bar: рамка line, скругление radius+4, тень 0 10 34 rgba(0,0,0,.2)
                decoration: BoxDecoration(
                  color: pal.panel,
                  borderRadius: BorderRadius.circular(kRadius + 4),
                  border: Border.all(color: pal.line),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 34, offset: Offset(0, 10))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DownloadNote(pal: pal),
                    if (_opts)
                      // .audio-opts: колонка с отступом 10, поля 12 12 4, линия снизу
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
                        child: Column(children: [
                          _Field(label: t('Скорость'), pal: pal, child: Segmented<double>(value: a.rate, options: [for (final x in rates) (x, rateText(x))], onChanged: e.setRate)),
                          const SizedBox(height: 10),
                          _Field(label: t('Таймер сна'), pal: pal, child: Segmented<String>(value: sleepKey(a.sleep), options: sleepOptions(), onChanged: applySleepKey)),
                          const SizedBox(height: 10),
                        ]),
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
                          _Btn(icon: LucideIcons.skipBack, label: t('Предыдущий стих'), onTap: () => e.stepVerse(-1), pal: pal, size: 20),
                          const SizedBox(width: 2),
                          _PlayBtn(a: a, pal: pal, size: 46, iconSize: 22),
                          const SizedBox(width: 2),
                          _Btn(icon: LucideIcons.skipForward, label: t('Следующий стих'), onTap: () => e.stepVerse(1), pal: pal, size: 20),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                // Человек ушёл в другое место — место чтения становится кнопкой «вернуться»
                                if (r != null && !a.follow)
                                  Tooltip(
                                    message: t('К звучащему месту'),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: () => e.resumeFollow(jump: true),
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
                                        decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(LucideIcons.cornerUpLeft, size: 14, color: pal.accent),
                                          const SizedBox(width: 4),
                                          Flexible(child: Text(Books.instance.formatRef(r.book, r.chapter, r.verse), overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.4, color: pal.accent))),
                                        ]),
                                      ),
                                    ),
                                  )
                                else
                                  Semantics(
                                    label: r == null ? null : '${Books.instance.formatRef(r.book, r.chapter, r.verse)} — ${t('Открыть проигрыватель')}',
                                    child: Text(r == null ? '' : Books.instance.formatRef(r.book, r.chapter, r.verse), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.2, color: pal.text)),
                                  ),
                                if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.muted)),
                              ]),
                            ),
                          ),
                          if (recorded) DownloadButton(audioId: a.source!, book: r.book, pal: pal),
                          const SizedBox(width: 2),
                          _Btn(icon: LucideIcons.slidersHorizontal, label: t('Настройки чтения вслух'), onTap: () => setState(() => _opts = !_opts), pal: pal, on: _opts, size: 19),
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
            child: a.loading ? _Spin(icon: LucideIcons.loader2, size: iconSize, color: pal.onAccent) : Icon(a.playing ? LucideIcons.pause : LucideIcons.play, size: iconSize, color: pal.onAccent),
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

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: Icon(widget.icon, size: widget.size, color: widget.color));
}

/// Кнопка ▶/⏸ для раскрытого проигрывателя (.ap-play: 78 px, значок 34)
Widget audioPlayButton(AudioState a, Palette pal, double size, {double? iconSize}) => _PlayBtn(a: a, pal: pal, size: size, iconSize: iconSize ?? size * 0.5);

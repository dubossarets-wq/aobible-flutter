// Мини-проигрыватель над вкладками (AudioBar.jsx): ▶/⏸, предыдущий/следующий стих, место, скорость, таймер сна,
// скачивание книги. Нажатие на свободную часть или свайп вверх — раскрыть проигрыватель на весь экран.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'audio_download.dart';
import 'audio_engine.dart';
import 'audio_player.dart';

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
        final sub = a.error != null
            ? a.error!
            : [if (left != null) t('сон через {n} мин', {'n': '$left'}) else if (a.sleep?.kind == 'chapter') t('до конца главы')].join(' · ');
        final r = a.ref;
        void expand() => a.canExpand ? openAudioPlayer(context) : null;
        final recorded = a.source != null && r != null;
        return SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                decoration: BoxDecoration(
                  color: pal.panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: pal.line),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DownloadNote(pal: pal),
                    if (_opts)
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
                        child: Column(children: [
                          Segmented<double>(label: t('Скорость'), value: a.rate, options: [for (final x in rates) (x, rateText(x))], onChanged: e.setRate, pal: pal),
                          const SizedBox(height: 10),
                          Segmented<String>(label: t('Таймер сна'), value: sleepKey(a.sleep), options: sleepOptions(), onChanged: applySleepKey, pal: pal),
                        ]),
                      ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: expand,
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) < -250) expand();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(children: [
                          _Btn(icon: Icons.skip_previous, label: t('Предыдущий стих'), onTap: () => e.stepVerse(-1), pal: pal, size: 24),
                          _PlayBtn(a: a, pal: pal, size: 46),
                          _Btn(icon: Icons.skip_next, label: t('Следующий стих'), onTap: () => e.stepVerse(1), pal: pal, size: 24),
                          const SizedBox(width: 6),
                          Expanded(
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
                                        Icon(Icons.subdirectory_arrow_left, size: 14, color: pal.accent),
                                        const SizedBox(width: 4),
                                        Flexible(child: Text(Books.instance.formatRef(r.book, r.chapter, r.verse), overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: pal.accent))),
                                      ]),
                                    ),
                                  ),
                                )
                              else
                                Semantics(
                                  label: r == null ? null : '${Books.instance.formatRef(r.book, r.chapter, r.verse)} — ${t('Открыть проигрыватель')}',
                                  child: Text(r == null ? '' : Books.instance.formatRef(r.book, r.chapter, r.verse), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: pal.text)),
                                ),
                              if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.muted)),
                            ]),
                          ),
                          if (recorded) DownloadButton(audioId: a.source!, book: r.book, pal: pal),
                          _Btn(icon: Icons.tune, label: t('Настройки чтения вслух'), onTap: () => setState(() => _opts = !_opts), pal: pal, on: _opts, size: 20),
                          _Btn(icon: Icons.close, label: t('Закрыть аудио'), onTap: e.stop, pal: pal, size: 22),
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

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap, required this.pal, this.size = 22, this.on = false});
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

/// ▶ / ⏸ / крутилка загрузки — круглая кнопка акцентного цвета
class _PlayBtn extends StatelessWidget {
  const _PlayBtn({required this.a, required this.pal, required this.size});
  final AudioState a;
  final Palette pal;
  final double size;
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
            child: a.loading
                ? Padding(padding: EdgeInsets.all(size * 0.28), child: CircularProgressIndicator(strokeWidth: 2.5, color: pal.onAccent))
                : Icon(a.playing ? Icons.pause : Icons.play_arrow, size: size * 0.5, color: pal.onAccent),
          ),
        ),
      );
}

/// Кнопка ▶/⏸ для раскрытого проигрывателя
Widget audioPlayButton(AudioState a, Palette pal, double size) => _PlayBtn(a: a, pal: pal, size: size);

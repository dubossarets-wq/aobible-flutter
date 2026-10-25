// Круглая кнопка «Слушать» в читалке (ListenFab из BibleReader.jsx): наушники справа внизу панели чтения,
// пока аудио не включено. Ядро кладёт её в Stack панели: Positioned(right: 14, bottom: 16, child: ListenFab(pane: i)).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'audio_engine.dart';
import 'audio_listen.dart';

class ListenFab extends ConsumerWidget {
  const ListenFab({super.key, required this.pane});
  final int pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider).palette;
    return ValueListenableBuilder<bool>(
      valueListenable: _activeOnly,
      builder: (_, active, _) {
        if (active) return const SizedBox.shrink();
        final panes = ref.read(panesProvider);
        final at = livePositions[pane]?.value ?? (pane < panes.length ? panes[pane].ref : startRef);
        final label = Books.instance.formatRef(at.book, at.chapter, at.verse);
        return Semantics(
          button: true,
          label: t('Слушать с этого места: {ref}', {'ref': label}),
          child: Tooltip(
            message: t('Слушать с {ref}', {'ref': label}),
            // .listen-fab: 44 px, рамка line, панель 96 %, значок accent 20 px, тень 0 4 14, прозрачность .85
            child: Opacity(
              opacity: 0.85,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mix(pal.panel, 0.96, Colors.transparent),
                  border: Border.all(color: pal.line),
                  boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 14, offset: Offset(0, 4))],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(onTap: () => openAudioFrom(context, ref, pane), child: Icon(LucideIcons.headphones, size: 20, color: pal.accent)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Только «включено ли аудио»: кнопка не перерисовывается на каждый стих
final _activeOnly = _ActiveListenable();

class _ActiveListenable extends ValueNotifier<bool> {
  _ActiveListenable() : super(AudioEngine.I.s.active) {
    AudioEngine.I.state.addListener(() => value = AudioEngine.I.s.active);
  }
}

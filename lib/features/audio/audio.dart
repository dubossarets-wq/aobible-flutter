// Аудиокниги: подключение к оболочке и читалке через Hub (вызывается из features.dart).
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'audio_bar.dart';
import 'audio_fab.dart';
import 'audio_engine.dart';
import 'audio_listen.dart';
import 'audio_settings.dart';

export 'audio_fab.dart' show ListenFab;
export 'audio_settings.dart' show AudioOfflineList, AudioSettingsPage, openAudioSettings;

void register() {
  Hub.audioBar = (context, ref) => const AudioBar();
  Hub.listenFab = (context, ref, pane) => ListenFab(pane: pane);
  Hub.openAudio = (context, ref, pane) => openAudioFrom(context, ref, pane);
  Hub.listenFrom = (context, ref, pane, from) => listenFromRef(context, pane, from);

  // Звучащий стих подсвечивается в тексте (панель, где включено аудио)
  Hub.verseDecorators.add((context, ref, pane, moduleId, item, book) {
    final a = AudioEngine.I.s;
    final r = a.ref;
    if (!a.active || r == null || a.pane != pane || a.moduleId != moduleId) return null;
    if (r.book != book || r.chapter != item.chapter || r.verse != item.verse) return null;
    return VerseDecor(background: ref.read(settingsProvider).palette.accent.withValues(alpha: 0.16));
  });

  // Скачанные книги (настройки → «Аудио»)
  Hub.moreItems.add(MoreItem(
    id: 'audio',
    icon: Icons.headphones_outlined,
    label: t('Аудио'),
    order: 60,
    run: (context, ref, pane) => openAudioSettings(context),
  ));
  Hub.afterStart.add(autoInstallAudio);
}

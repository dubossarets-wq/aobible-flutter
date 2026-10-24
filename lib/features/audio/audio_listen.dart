// «Слушать с этого места» (listen.js) и автоподключение аудиомодулей к установленным переводам (App.jsx).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import 'audio_data.dart';
import 'audio_engine.dart';
import 'audio_logic.dart';

/// Слушать с места [from] в панели [pane] (перевод — тот, что открыт в панели)
Future<void> listenFromRef(BuildContext context, int pane, VerseRef from) {
  final c = ProviderScope.containerOf(context);
  final panes = c.read(panesProvider);
  if (pane >= panes.length) return Future.value();
  return AudioEngine.I.listenFrom(c, pane, panes[pane].moduleId, from);
}

/// Кнопка «Слушать»: с текущего места панели; если запись уже открыта на паузе — продолжить её
Future<void> openAudioFrom(BuildContext context, WidgetRef ref, int pane) {
  final e = AudioEngine.I;
  if (e.s.active && e.s.pane == pane && e.s.source != null) {
    if (!e.s.playing) return e.resume();
    return Future.value();
  }
  final panes = ref.read(panesProvider);
  if (pane >= panes.length) return Future.value();
  final at = livePositions[pane]?.value ?? panes[pane].ref;
  return listenFromRef(context, pane, at);
}

/// При запуске: аудиокниги к установленным переводам ставим сами (они маленькие), уже стоящие обновляем
/// при новой версии каталога. Каждую пробуем один раз (prefs «autoAudioList»), чтобы не ставить заново удалённое.
Future<void> autoInstallAudio(WidgetRef ref) async {
  final store = ModuleStore.instance;
  final List<CatalogEntry> cat;
  try {
    cat = await store.catalog();
  } catch (_) {
    return; // нет сети — в следующий раз
  }
  final bibles = store.bibles.map((b) => b.id).toList();
  final tried = <String>{...?prefs.getStringList('autoAudioList')};
  for (final e in cat.where((e) => e.type == 'audio' && !e.unavailable)) {
    final have = store.get(e.id);
    if (have != null) {
      if (have.meta['catalogVersion'] != e.version) {
        try {
          await store.install(e);
          forgetPack(e.id);
        } catch (_) {
          // обновим в следующий раз
        }
      }
      continue;
    }
    final translation = e.json['translation'] as String?;
    if (tried.contains(e.id) || !bibles.any((b) => fitsTranslation(translation, b))) continue;
    tried.add(e.id);
    await prefs.setStringList('autoAudioList', tried.toList());
    try {
      await store.install(e);
    } catch (_) {
      tried.remove(e.id); // не вышло — попробуем в следующий раз
      await prefs.setStringList('autoAudioList', tried.toList());
    }
  }
}

// Аудиомодули на устройстве: разбор записей из таблицы payload, какие записи подходят к главе и переводу.
import 'dart:convert';
import 'dart:isolate';

import '../../core/books.dart';
import '../../core/modules.dart';
import 'audio_logic.dart';

final _packs = <String, AudioPack>{};

/// Аудиомодуль целиком (главы, время стихов). Разбор — в отдельном потоке (у «Шмуэлоф» 3 МБ JSON), затем из памяти.
Future<AudioPack?> loadPack(String id) async {
  final hit = _packs[id];
  if (hit != null) return hit;
  final m = ModuleStore.instance.get(id);
  if (m == null) return null;
  final raw = ModuleStore.instance.db(id).select('SELECT json FROM payload').firstOrNull?['json'] as String?;
  if (raw == null) return null;
  final pack = await Isolate.run(() => AudioPack.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>()));
  return _packs[id] = pack;
}

/// Забыть разобранный модуль (после переустановки)
void forgetPack(String id) => _packs.remove(id);

List<InstalledModule> audioModules() => ModuleStore.instance.installed.where((m) => m.type == 'audio').toList();

class AudioSources {
  const AudioSources(this.recorded, this.other);
  final List<AudioPack> recorded; // записи, подходящие к переводу и озвучившие эту главу
  final List<AudioPack> other; // озвучившие главу, но для другого перевода
}

/// Записи для главы [ref] при чтении в переводе [moduleId]
Future<AudioSources> audioSourcesFor(String moduleId, VerseRef ref) async {
  final fits = <AudioPack>[], others = <AudioPack>[];
  for (final m in audioModules()) {
    final p = await loadPack(m.id);
    if (p == null || !p.has(ref.book, ref.chapter)) continue;
    (fitsTranslation(p.translation, moduleId) ? fits : others).add(p);
  }
  return AudioSources(fits, others);
}

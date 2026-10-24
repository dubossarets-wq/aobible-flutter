// Панели чтения (одна или две) и синхронная прокрутка.
// Место каждой панели запоминается (последнее место — при следующем запуске), переход — через nav++.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'books.dart';
import 'settings.dart';

class PaneState {
  const PaneState({required this.moduleId, required this.ref, this.nav = 0});
  final String moduleId;
  final VerseRef ref; // куда перейти (при nav++); текущее место при прокрутке — в livePositions
  final int nav;

  PaneState copyWith({String? moduleId, VerseRef? ref, int? nav}) => PaneState(moduleId: moduleId ?? this.moduleId, ref: ref ?? this.ref, nav: nav ?? this.nav);
  Map<String, dynamic> toJson() => {'moduleId': moduleId, 'ref': ref.toJson()};
}

/// Самое первое открытие — с начала Библии; дальше — с последнего места
const startRef = VerseRef('Gen', 1, 1);

// Панели читаются из prefs заново (перенос данных, «Мои данные») — у каждой новый nav, иначе панель не перешла бы
int _generation = 0;

class PanesNotifier extends Notifier<List<PaneState>> {
  @override
  List<PaneState> build() {
    final raw = prefs.getString('panes');
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map>();
        final out = [
          for (final p in list)
            PaneState(moduleId: p['moduleId'] as String, ref: VerseRef.fromJson(p['ref']) ?? startRef, nav: ++_generation),
        ];
        if (out.isNotEmpty) return out;
      } catch (_) {
        // повреждённые данные — начинаем с начала
      }
    }
    return [PaneState(moduleId: ref.read(settingsProvider).get<String>('primaryModule'), ref: startRef)];
  }

  void _save() => prefs.setString('panes', jsonEncode([for (final p in state) p.toJson()]));

  void navigate(int i, VerseRef to) {
    state = [for (var k = 0; k < state.length; k++) k == i ? state[k].copyWith(ref: to, nav: state[k].nav + 1) : state[k]];
    livePositions[i]?.value = to;
    _save();
  }

  void setModule(int i, String moduleId) {
    final at = livePositions[i]?.value ?? state[i].ref;
    state = [for (var k = 0; k < state.length; k++) k == i ? state[k].copyWith(moduleId: moduleId, ref: at, nav: state[k].nav + 1) : state[k]];
    _save();
  }

  /// Вторая панель: открыть (тот же стих, перевод — заданный или тот же) или закрыть
  void toggleSplit({String? moduleId}) {
    if (state.length > 1) {
      state = [state.first.copyWith(ref: livePositions[0]?.value ?? state.first.ref)];
    } else {
      final at = livePositions[0]?.value ?? state.first.ref;
      state = [state.first.copyWith(ref: at), PaneState(moduleId: moduleId ?? state.first.moduleId, ref: at)];
    }
    _save();
  }

  /// Место при прокрутке: сохраняем без перехода (раз в полсекунды, а не на каждом кадре)
  void remember(int i, VerseRef at) {
    if (i >= state.length || state[i].ref == at) return;
    state = [for (var k = 0; k < state.length; k++) k == i ? PaneState(moduleId: state[k].moduleId, ref: at, nav: state[k].nav) : state[k]];
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  Timer? _saveTimer;
}

final panesProvider = NotifierProvider<PanesNotifier, List<PaneState>>(PanesNotifier.new);

/// Карта места во второй половине экрана: место (объект функции карт) или null. Не сохраняется —
/// после перезапуска снова чтение; вторая панель чтения под картой не теряется.
class MapPaneNotifier extends Notifier<Object?> {
  @override
  Object? build() => null;
  void open(Object place) => state = place;
  void close() => state = null;
}

final mapPaneProvider = NotifierProvider<MapPaneNotifier, Object?>(MapPaneNotifier.new);

/// Текущее место каждой панели (для шапки) — без перерисовки всего приложения
final livePositions = <int, ValueNotifier<VerseRef>>{};
ValueNotifier<VerseRef> livePosition(int i, VerseRef initial) => livePositions.putIfAbsent(i, () => ValueNotifier(initial));

/// Синхронная прокрутка: ведущая панель — та, которую человек трогал последней
class SyncHub {
  static int driver = 0;
  static final listeners = <int, void Function(VerseRef ref, double frac)>{};
  static void emit(int from, VerseRef ref, double frac) {
    listeners.forEach((pane, fn) {
      if (pane != from) fn(ref, frac);
    });
  }
}

// Панели чтения (одна или две) и синхронная прокрутка.
// Место каждой панели запоминается (последнее место — при следующем запуске), переход — через nav++.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'books.dart';
import 'modules.dart';
import 'settings.dart';

class PaneState {
  const PaneState({required this.moduleId, required this.ref, this.nav = 0, this.history = const [], this.hIndex = 0});
  final String moduleId;
  final VerseRef ref; // куда перейти (при nav++); текущее место при прокрутке — в livePositions
  final int nav;
  final List<VerseRef> history; // история переходов («←» / «→» в шапке, как в веб-версии); в памяти
  final int hIndex;

  PaneState copyWith({String? moduleId, VerseRef? ref, int? nav, List<VerseRef>? history, int? hIndex}) =>
      PaneState(moduleId: moduleId ?? this.moduleId, ref: ref ?? this.ref, nav: nav ?? this.nav, history: history ?? this.history, hIndex: hIndex ?? this.hIndex);
  Map<String, dynamic> toJson() => {'moduleId': moduleId, 'ref': ref.toJson()};
}

/// Сколько панелей чтения можно открыть рядом («+» в шапке последней панели; MAX_PANES в App.jsx)
const maxPanes = 4;

/// Самое первое открытие — с начала Библии; дальше — с последнего места
const startRef = VerseRef('Gen', 1, 1);

// Панели читаются из prefs заново (перенос данных, «Мои данные») — у каждой новый nav, иначе панель не перешла бы
int _generation = 0;

class PanesNotifier extends Notifier<List<PaneState>> {
  @override
  List<PaneState> build() {
    ref.onDispose(() => _saveTimer?.cancel()); // отложенное сохранение не должно сработать после закрытия
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

  /// Переход. highlight — слово из поиска: подсвечивается в тексте 8 с (как в веб-версии), стих мигает (flash)
  void navigate(int i, VerseRef to, {String? highlight, bool flash = true}) {
    readerMarks.value = {...readerMarks.value, i: (ref: to, highlight: highlight, flash: flash, stamp: DateTime.now().millisecondsSinceEpoch)};
    final p = state[i];
    // История: текущее место (куда долистали) — на свою позицию, новое — следом; «вперёд» отбрасываем
    final at = livePositions[i]?.value ?? p.ref;
    final hist = p.history.isEmpty ? <VerseRef>[at] : [...p.history.take(p.hIndex + 1)];
    hist[hist.length - 1] = at;
    if (hist.last != to) hist.add(to);
    state = [for (var k = 0; k < state.length; k++) k == i ? p.copyWith(ref: to, nav: p.nav + 1, history: hist, hIndex: hist.length - 1) : state[k]];
    livePositions[i]?.value = to;
    _save();
  }

  /// Перевод панели удалён или недоступен — панель переходит на основной (или первый) перевод, место остаётся
  /// (App.jsx: следим за списком переводов). Возвращает, переключили ли что-нибудь.
  bool repairModules() {
    final store = ModuleStore.instance;
    final ids = [for (final m in store.bibles) if (m.features['helper'] != true) m.id];
    if (ids.isEmpty) return false; // переводов ещё нет (первый запуск) — ждём установки
    final primary = ref.read(settingsProvider).get<String>('primaryModule');
    final fallback = ids.contains(primary) ? primary : ids.first;
    var changed = false;
    final out = <PaneState>[];
    for (var k = 0; k < state.length; k++) {
      final p = state[k];
      if (ids.contains(p.moduleId)) {
        out.add(p);
        continue;
      }
      changed = true;
      out.add(p.copyWith(moduleId: fallback, ref: livePositions[k]?.value ?? p.ref, nav: p.nav + 1));
    }
    if (changed) {
      state = out;
      _save();
    }
    return changed;
  }

  /// «←» / «→» по истории переходов
  void go(int i, int dir) {
    final p = state[i];
    final h = p.hIndex + dir;
    if (h < 0 || h >= p.history.length) return;
    final hist = [...p.history];
    hist[p.hIndex] = livePositions[i]?.value ?? p.ref;
    state = [for (var k = 0; k < state.length; k++) k == i ? p.copyWith(ref: hist[h], nav: p.nav + 1, history: hist, hIndex: h) : state[k]];
    livePositions[i]?.value = hist[h];
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
      livePositions.remove(1); // место закрытой панели не должно «прилипнуть» к следующей второй панели
    } else {
      final at = livePositions[0]?.value ?? state.first.ref;
      state = [state.first.copyWith(ref: at), PaneState(moduleId: moduleId ?? state.first.moduleId, ref: at)];
    }
    _save();
  }

  /// Ещё одна панель (до maxPanes) — сразу под той, где нажали «+» (after; без него — под последней): перевод и место —
  /// как у неё. Панели ниже сдвигаются и остаются там, где их читали (новый nav — панель на этом месте экрана перейдёт
  /// к своему стиху). place — открыть в новой это место (с миганием стиха)
  void addPane([int? after, VerseRef? place]) {
    if (state.length >= maxPanes) return;
    final i = math.min(after ?? state.length - 1, state.length - 1);
    final src = state[i];
    final at = place ?? livePositions[i]?.value ?? src.ref;
    final top = state.map((p) => p.nav).reduce(math.max) + 1;
    final out = <PaneState>[];
    for (var k = 0; k < state.length; k++) {
      final p = state[k];
      out.add(k <= i ? p : p.copyWith(ref: livePositions[k]?.value ?? p.ref, nav: top + k + 1));
      if (k == i) out.add(PaneState(moduleId: src.moduleId, ref: at, nav: top));
    }
    // места панелей — по их новым номерам (снизу вверх, чтобы не затереть ещё не перенесённые)
    for (var k = out.length - 1; k > i; k--) {
      livePosition(k, out[k].ref).value = out[k].ref;
    }
    // пометки переходов панелей ниже — снимаем (сдвинутая панель не мигнёт старым местом ещё раз);
    // у новой панели — мигание открытого места
    final marks = {for (final e in readerMarks.value.entries) if (e.key <= i) e.key: e.value};
    if (place != null) marks[i + 1] = (ref: place, highlight: null, flash: true, stamp: DateTime.now().millisecondsSinceEpoch);
    readerMarks.value = marks;
    state = out;
    _save();
  }

  /// Закрыть панель, на которой нажали «×» (closeSplit в App.jsx): следующие сдвигаются на её место — каждая
  /// со своим переводом, историей и там, где её читали (новый nav: панель на этом месте экрана перейдёт к своему стиху)
  void closePane(int i) {
    if (state.length < 2 || i >= state.length) return;
    final top = state.map((p) => p.nav).reduce(math.max) + 1;
    final out = <PaneState>[];
    for (var k = 0; k < state.length; k++) {
      if (k == i) continue;
      final p = state[k];
      out.add(out.length == k ? p : p.copyWith(ref: livePositions[k]?.value ?? p.ref, nav: top + out.length));
    }
    // места панелей — по их новым номерам; место закрытой не «прилипнет» к следующей новой панели
    for (var k = i; k < out.length; k++) {
      livePosition(k, out[k].ref).value = out[k].ref;
    }
    livePositions.remove(state.length - 1);
    state = out;
    _save();
  }

  /// Место при прокрутке: сохраняем без перехода (раз в полсекунды, а не на каждом кадре)
  void remember(int i, VerseRef at) {
    if (i >= state.length || state[i].ref == at) return;
    state = [for (var k = 0; k < state.length; k++) k == i ? state[k].copyWith(ref: at) : state[k]];
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

/// Пометки последнего перехода панели: какой стих мигнуть и какое слово подсветить (ChapterView.jsx: flash, highlight).
/// Читалка показывает их stamp-ом один раз: подсветка слова гаснет через 8 с, мигание стиха — короткое
final readerMarks = ValueNotifier<Map<int, ({VerseRef ref, String? highlight, bool flash, int stamp})>>({});

/// Доступно обновление приложения (Google Play): на «Ещё» и на значке ⋮ загорается точка (updates.available в веб-версии).
/// Ставит главный экран после тихой проверки
final updateAvailable = ValueNotifier<bool>(false);

/// Режим чтения (focusMode): читалка при прокрутке вниз ставит true — шапка и нижние вкладки прячутся; вверх — false
final focusHidden = ValueNotifier<bool>(false);

/// Панель в режиме плана (PlanView в веб-версии: лента отрывков дня вместо обычной читалки). uid плана и день.
/// Ставит и снимает функция планов; главный экран рисует вместо читалки Hub.planView
final planMode = ValueNotifier<Map<int, ({String uid, int day})>>({});
void setPlanMode(int pane, ({String uid, int day})? v) {
  final m = {...planMode.value};
  if (v == null) {
    m.remove(pane);
  } else {
    m[pane] = v;
  }
  planMode.value = m;
}
ValueNotifier<VerseRef> livePosition(int i, VerseRef initial) => livePositions.putIfAbsent(i, () => ValueNotifier(initial));

/// Синхронная прокрутка: ведущая панель — та, которую человек трогал последней
class SyncHub {
  static int driver = 0;
  static final listeners = <int, void Function(VerseRef ref, double frac)>{};
  // высота (пиксели) стиха у верхнего края ведущей панели — ведомая сравнивает со своей: во сколько раз
  // её текст длиннее на экране, во столько раз дальше ей сдвигаться
  static double leadH = 0;
  // что у верхнего края ведущей: заголовок главы, заголовок раздела или стих (стих 1 и заголовок главы — разные строки)
  static int leadKind = 2; // 0 — глава, 1 — заголовок раздела, 2 — стих
  static void emit(int from, VerseRef ref, double frac, [double h = 0, int kind = 2]) {
    leadH = h;
    leadKind = kind;
    listeners.forEach((pane, fn) {
      if (pane != from) fn(ref, frac);
    });
  }

  // Сдвиг ведущей панели (пиксели) — сразу, в том же кадре: ведомая двигается вместе с ней, а не кадром позже
  static final deltaListeners = <int, void Function(double dy)>{};
  static void emitDelta(int from, double dy) {
    deltaListeners.forEach((pane, fn) {
      if (pane != from) fn(dy);
    });
  }
}

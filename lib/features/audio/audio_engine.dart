// Движок аудиокниг (аналог core/audio.js): запись главы с разметкой времени стихов, звучащий стих сообщается
// читалке — она подсвечивает его и ведёт текст за чтецом. Когда записи нет — сообщение «Для этой главы нет аудиозаписи».
// Звук — just_audio; фон, уведомление и кнопки экрана блокировки — audio_service (AoAudioHandler).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'audio_data.dart';
import 'audio_logic.dart';
import 'audio_offline.dart';

/// Таймер сна: через N минут или до конца главы
class SleepTimer {
  const SleepTimer.min(this.minutes, this.until)
      : kind = 'min',
        book = null,
        chapter = null;
  const SleepTimer.chapter(this.book, this.chapter)
      : kind = 'chapter',
        minutes = null,
        until = null;
  final String kind; // 'min' | 'chapter'
  final int? minutes;
  final DateTime? until;
  final String? book;
  final int? chapter;
}

const _keep = Object();

class AudioState {
  const AudioState({
    this.active = false,
    this.playing = false,
    this.loading = false,
    this.pane = 0,
    this.moduleId,
    this.ref,
    this.source,
    this.rate = 1,
    this.volume = 1,
    this.sleep,
    this.error,
    this.follow = true,
  });
  final bool active;
  final bool playing;
  final bool loading;
  final int pane;
  final String? moduleId; // перевод, текст которого читается
  final VerseRef? ref; // звучащий стих
  final String? source; // id аудиомодуля; null — записи нет (показываем только сообщение)
  final double rate;
  final double volume;
  final SleepTimer? sleep;
  final String? error;
  final bool follow; // текст идёт за чтецом; человек ушёл читать другое — false

  /// Можно ли раскрыть полноэкранный проигрыватель
  bool get canExpand => active && ref != null && source != null;

  AudioState copyWith({
    bool? active,
    bool? playing,
    bool? loading,
    int? pane,
    Object? moduleId = _keep,
    Object? ref = _keep,
    Object? source = _keep,
    double? rate,
    double? volume,
    Object? sleep = _keep,
    Object? error = _keep,
    bool? follow,
  }) =>
      AudioState(
        active: active ?? this.active,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        pane: pane ?? this.pane,
        moduleId: identical(moduleId, _keep) ? this.moduleId : moduleId as String?,
        ref: identical(ref, _keep) ? this.ref : ref as VerseRef?,
        source: identical(source, _keep) ? this.source : source as String?,
        rate: rate ?? this.rate,
        volume: volume ?? this.volume,
        sleep: identical(sleep, _keep) ? this.sleep : sleep as SleepTimer?,
        error: identical(error, _keep) ? this.error : error as String?,
        follow: follow ?? this.follow,
      );
}

/// Положение в записи главы (секунды от начала главы) и длина главы
class TimeSnap {
  const TimeSnap(this.pos, this.len);
  final double pos, len;
}

T _load<T>(String key, T def) {
  try {
    final raw = prefs.getString(key);
    return raw == null ? def : (jsonDecode(raw) as T);
  } catch (_) {
    return def;
  }
}

void _save(String key, Object? v) => prefs.setString(key, jsonEncode(v));

class AudioEngine {
  AudioEngine._() {
    state = ValueNotifier(AudioState(rate: (_load<num>('audioRate', 1)).toDouble(), volume: (_load<num>('audioVolume', 1)).toDouble().clamp(0, 1)));
  }
  static final I = AudioEngine._();

  late final ValueNotifier<AudioState> state;
  final time = ValueNotifier<TimeSnap>(const TimeSnap(0, 0));

  ProviderContainer? _c;
  AudioPlayer? _player;
  final _subs = <StreamSubscription<Object?>>[]; // подписки на события плеера — снимаются вместе с ним
  AoAudioHandler? _handler;
  AudioChapter? _timing;
  String? _timingKey, _timingPack, _loadedUrl;
  int _gen = 0; // поколение воспроизведения: устаревшие ожидания игнорируются
  bool _switching = false; // идёт загрузка/перемотка — события позиции не трогают стих
  bool _advancing = false;
  DateTime _lastAdvance = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _sleepTimer;
  DateTime _userScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ownNavAt = DateTime.fromMillisecondsSinceEpoch(0);
  ValueNotifier<VerseRef>? _live;
  int _livePane = -1;
  final _shapes = <String, BookShape>{};

  AudioState get s => state.value;
  static const followIdle = Duration(seconds: 4); // столько человек не листает — текст снова идёт за чтецом

  void _set(AudioState Function(AudioState s) f) {
    final old = state.value;
    final next = f(old);
    state.value = next;
    if (old.active != next.active || old.pane != next.pane || old.ref != next.ref) _bumpDecor();
    if (old.active && next.active && next.ref != null && old.ref != next.ref) _followText(next);
    if (old.playing != next.playing || old.loading != next.loading || old.ref?.chapter != next.ref?.chapter || old.ref?.book != next.ref?.book) _publish();
  }

  void _bumpDecor() {
    try {
      _c?.read(decorVersionProvider.notifier).bump();
    } catch (_) {
      // контейнер уже закрыт
    }
  }

  // --- Текст идёт за чтецом ------------------------------------------------------------------

  void _watchLive(int pane) {
    if (_livePane == pane) return;
    _live?.removeListener(_onLive);
    _livePane = pane;
    final c = _c;
    final init = c == null ? const VerseRef('Gen', 1, 1) : (c.read(panesProvider).elementAtOrNull(pane)?.ref ?? const VerseRef('Gen', 1, 1));
    _live = livePosition(pane, init)..addListener(_onLive);
    // перевод этой панели сменили — озвучка переходит на запись на его языке
    _moduleSub?.close();
    _moduleSub = c?.listen<String?>(panesProvider.select((l) => l.elementAtOrNull(pane)?.moduleId), (_, next) => _onModule(next));
  }

  void _unwatchLive() {
    _live?.removeListener(_onLive);
    _live = null;
    _livePane = -1;
    _moduleSub?.close();
    _moduleSub = null;
  }

  ProviderSubscription<String?>? _moduleSub;

  /// Сменили перевод панели во время чтения вслух: запись подходит и к нему — читает дальше; нет — берём запись
  /// на его языке (ту, что слушали раньше, или первую) с того же места; записи нет — звучит прежняя.
  /// Настройка «Озвучка — на языке перевода» (audioFollowsTranslation)
  Future<void> _onModule(String? moduleId) async {
    final a = s, c = _c, at = a.ref;
    if (moduleId == null || c == null || at == null || !a.active || a.source == null || moduleId == a.moduleId) return;
    if (c.read(settingsProvider).get<bool>('audioFollowsTranslation') == false) return;
    final src = await audioSourcesFor(moduleId, at);
    if (!s.active || s.pane != a.pane) return;
    if (src.recorded.any((m) => m.id == a.source)) return _set((x) => x.copyWith(moduleId: moduleId));
    final pref = _load<String?>('audioSource', null);
    final next = src.recorded.any((m) => m.id == pref) ? pref : src.recorded.firstOrNull?.id;
    if (next == null) return;
    final wasPlaying = s.playing;
    await start(c, pane: a.pane, moduleId: moduleId, ref: s.ref ?? at, source: next);
    if (!wasPlaying) await pause();
  }

  // Место в панели изменилось не по нашему переходу — человек листает сам
  void _onLive() {
    final now = DateTime.now();
    if (!s.active || now.difference(_ownNavAt) < const Duration(milliseconds: 1500)) return;
    _userScrollAt = now;
    if (s.follow) _set((x) => x.copyWith(follow: false));
  }

  void _followText(AudioState next) {
    final r = next.ref;
    final c = _c;
    if (r == null || c == null) return;
    if (!next.follow) {
      // Человек давно не листает — возвращаем текст к чтецу
      if (DateTime.now().difference(_userScrollAt) < followIdle) return;
      state.value = next.copyWith(follow: true);
    }
    _goTo(next.pane, r);
  }

  void _goTo(int pane, VerseRef r) {
    final c = _c;
    if (c == null) return;
    try {
      if (pane >= c.read(panesProvider).length) return;
      _ownNavAt = DateTime.now();
      c.read(panesProvider.notifier).navigate(pane, r);
    } catch (_) {
      // панели ещё нет — не страшно
    }
  }

  void detachFollow(int pane) {
    if (s.active && s.follow && s.pane == pane) _set((x) => x.copyWith(follow: false));
  }

  /// «К звучащему месту»: текст снова идёт за чтецом
  void resumeFollow({bool jump = false}) {
    if (!s.active) return;
    _userScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
    if (!s.follow) state.value = s.copyWith(follow: true);
    if (jump && s.ref != null) _goTo(s.pane, s.ref!);
  }

  // --- Источники и запуск --------------------------------------------------------------------

  /// «Слушать с этого места»: запись, которую слушали раньше (если подходит к переводу), иначе первая подходящая
  Future<void> listenFrom(ProviderContainer c, int pane, String moduleId, VerseRef ref) async {
    _c = c;
    final src = await audioSourcesFor(moduleId, ref);
    final pref = _load<String?>('audioSource', null);
    final source = src.recorded.any((m) => m.id == pref) ? pref : src.recorded.firstOrNull?.id;
    if (source != null) return start(c, pane: pane, moduleId: moduleId, ref: ref, source: source);
    _showMessage(pane, moduleId, ref, t('Для этой главы нет аудиозаписи.'));
  }

  void _showMessage(int pane, String moduleId, VerseRef ref, String error) {
    _stopEngines();
    _watchLive(pane);
    _set((x) => x.copyWith(active: true, playing: false, loading: false, pane: pane, moduleId: moduleId, ref: ref, source: null, error: error, follow: true));
  }

  Future<void> start(ProviderContainer c, {required int pane, required String moduleId, required VerseRef ref, required String source}) async {
    _c = c;
    _stopEngines();
    _watchLive(pane);
    _userScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
    _set((x) => x.copyWith(active: true, pane: pane, moduleId: moduleId, ref: ref, source: source, error: null, playing: true, follow: true));
    await _playFrom(ref);
  }

  Future<void> pause() async {
    _gen++;
    _switching = false;
    _set((x) => x.copyWith(playing: false, loading: false));
    await _player?.pause();
  }

  Future<void> resume() async {
    final a = s;
    if (!a.active || a.ref == null) return;
    if (a.source == null) return;
    _set((x) => x.copyWith(playing: true, error: null));
    final p = _player;
    final key = '${a.ref!.book}.${a.ref!.chapter}';
    if (p != null && _timingKey == key && _timingPack == a.source && p.processingState != ProcessingState.completed && p.processingState != ProcessingState.idle) {
      _unawaitedPlay(p);
    } else {
      await _playFrom(a.ref!);
    }
  }

  Future<void> stop() async {
    _stopEngines();
    _sleepTimer?.cancel();
    _unwatchLive();
    _timing = null;
    _timingKey = null;
    _releasePlayer();
    time.value = const TimeSnap(0, 0);
    _set((x) => x.copyWith(active: false, playing: false, loading: false, sleep: null, ref: null, error: null));
    _handler?.playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
  }

  /// Предыдущий/следующий стих
  Future<void> stepVerse(int dir) async {
    resumeFollow();
    final r = s.ref;
    if (r == null || s.source == null) return;
    final next = _neighbourVerse(r, dir);
    if (next == null) return;
    _stopEngines();
    _set((x) => x.copyWith(ref: next, playing: true));
    await _playFrom(next);
  }

  /// Предыдущая/следующая глава (кнопки экрана блокировки). «Назад» после первых секунд — в начало этой главы.
  Future<void> stepChapter(int dir) async {
    resumeFollow();
    final r = s.ref;
    if (r == null || s.source == null) return;
    VerseRef? next;
    // «Назад» после первых секунд — в начало главы
    if (dir < 0 && time.value.pos > 4) {
      next = _chapterStart(r);
    } else {
      next = _neighbourChapter(r, dir);
    }
    if (next == null) return;
    _stopEngines();
    _set((x) => x.copyWith(ref: next, playing: true));
    await _playFrom(next);
  }

  VerseRef? _chapterStart(VerseRef r) {
    final vs = _shape(r.book).verses[r.chapter];
    return vs == null || vs.isEmpty ? null : VerseRef(r.book, r.chapter, vs.first);
  }

  /// Слушать с выбранного стиха (нажатие на стих в раскрытом проигрывателе)
  Future<void> playVerse(VerseRef ref) async {
    resumeFollow();
    if (!s.active) return;
    _stopEngines();
    _set((x) => x.copyWith(ref: ref, playing: true, error: null));
    await _playFrom(ref);
  }

  /// Перемотка внутри главы: [sec] — секунды от начала главы
  Future<void> seekChapter(double sec) async {
    final p = _player, ch = _timing;
    if (p == null || ch == null) return;
    resumeFollow();
    final (start, len) = ch.span((p.duration ?? Duration.zero).inMilliseconds / 1000);
    final to = start + sec.clamp(0, len);
    await p.seek(Duration(milliseconds: (to * 1000).round()));
    _emitTime(to);
    _syncVerse(to);
  }

  Future<void> setRate(double rate) async {
    _save('audioRate', rate);
    _set((x) => x.copyWith(rate: rate));
    await _player?.setSpeed(rate);
    _publish();
  }

  Future<void> setVolume(double v) async {
    final x = v.clamp(0.0, 1.0);
    _save('audioVolume', x);
    state.value = s.copyWith(volume: x);
    await _player?.setVolume(x);
  }

  /// Сменить запись (другой чтец) на ходу
  Future<void> setSource(String source) async {
    _save('audioSource', source);
    final r = s.ref;
    _stopEngines();
    _timingKey = null;
    _set((x) => x.copyWith(source: source, error: null));
    if (s.active && r != null) {
      _set((x) => x.copyWith(playing: true));
      await _playFrom(r);
    }
  }

  void setSleepMinutes(int? minutes) {
    _sleepTimer?.cancel();
    if (minutes == null || minutes <= 0) return _set((x) => x.copyWith(sleep: null));
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      pause();
      _set((x) => x.copyWith(sleep: null));
    });
    _set((x) => x.copyWith(sleep: SleepTimer.min(minutes, DateTime.now().add(Duration(minutes: minutes)))));
  }

  void setSleepChapter() {
    _sleepTimer?.cancel();
    _set((x) => x.copyWith(sleep: SleepTimer.chapter(x.ref?.book, x.ref?.chapter)));
  }

  void clearSleep() => setSleepMinutes(null);

  // --- Внутреннее ----------------------------------------------------------------------------

  void _stopEngines() {
    _gen++;
    _switching = false;
    _player?.pause();
  }

  /// Закрыли аудио: подписки снимаем, плеер освобождаем (держать декодер и поток позиции без дела незачем) —
  /// при следующем запуске _ensurePlayer создаст новый
  void _releasePlayer() {
    final p = _player;
    if (p == null) return;
    _player = null;
    _loadedUrl = null;
    _timingPack = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    p.dispose().catchError((Object e) => debugPrint('плеер не освободился: $e'));
  }

  void _unawaitedPlay(AudioPlayer p) {
    p.play().catchError((Object e) => _fail(e));
  }

  Future<AudioPlayer> _ensurePlayer() async {
    final hit = _player;
    if (hit != null) return hit;
    final p = _player = AudioPlayer();
    await p.setVolume(s.volume);
    _subs.add(p.positionStream.listen(_onPosition));
    _subs.add(p.processingStateStream.listen((st) {
      if (st == ProcessingState.completed) _onCompleted();
      final busy = st == ProcessingState.loading || st == ProcessingState.buffering;
      if (s.active && s.playing && s.loading != busy && !_switching) _set((x) => x.copyWith(loading: busy));
    }));
    // Звонок или другое приложение остановили звук — кнопка показывает паузу
    _subs.add(p.playingStream.listen((playing) {
      if (!playing && s.active && s.playing && !_switching && p.processingState != ProcessingState.completed && _timing != null) {
        _set((x) => x.copyWith(playing: false));
      }
    }));
    if (_handler == null) {
      try {
        _handler = await AudioService.init(
          builder: () => AoAudioHandler(this),
          config: AudioServiceConfig(
            androidNotificationChannelId: 'app.aobible.audio',
            androidNotificationChannelName: t('Аудиокнига'),
            androidNotificationOngoing: true,
            androidNotificationIcon: 'mipmap/ic_launcher',
          ),
        );
      } catch (e) {
        debugPrint('audio_service недоступен: $e'); // играем и без уведомления
      }
    }
    return p;
  }

  Future<void> _playFrom(VerseRef ref) async {
    final a = s;
    // Таймер «до конца главы»: остановиться, когда началась другая глава
    final sl = a.sleep;
    if (sl != null && sl.kind == 'chapter' && (ref.chapter != sl.chapter || ref.book != sl.book)) {
      _set((x) => x.copyWith(sleep: null, playing: false));
      await _player?.pause();
      return;
    }
    _set((x) => x.copyWith(ref: ref));
    if (a.source == null) return _set((x) => x.copyWith(playing: false));
    await _playRecorded(ref);
  }

  Future<void> _playRecorded(VerseRef ref) async {
    final my = ++_gen;
    final src = s.source!;
    final key = '${ref.book}.${ref.chapter}';
    try {
      final p = await _ensurePlayer();
      if (_timingKey != key || _timingPack != src) {
        _set((x) => x.copyWith(loading: true));
        final pack = await loadPack(src);
        final ch = pack?.chapters[key];
        if (my != _gen) return;
        if (ch == null) {
          _set((x) => x.copyWith(loading: false, playing: false, error: t('Для этой главы нет аудиозаписи.')));
          return;
        }
        if (_loadedUrl != ch.url) {
          _switching = true;
          _loadedUrl = null;
          final local = await OfflineAudio.localPath(ch.url); // скачанная книга — из памяти телефона
          if (my != _gen) return;
          if (local != null) {
            await p.setFilePath(local);
          } else {
            await p.setUrl(ch.url);
          }
          if (my != _gen) return;
          _loadedUrl = ch.url;
        }
        _timing = ch;
        _timingKey = key;
        _timingPack = src;
        _emitTime(0);
        _publishItem(pack!);
      }
      final ch = _timing!;
      _switching = true;
      await p.setSpeed(s.rate);
      await p.seek(Duration(milliseconds: (ch.startFor(ref.verse) * 1000).round()));
      if (my != _gen) return;
      _switching = false;
      _unawaitedPlay(p);
      _set((x) => x.copyWith(loading: false, error: null));
    } catch (e) {
      if (my == _gen) await _fail(e);
    }
  }

  Future<void> _fail(Object e) async {
    _switching = false;
    var msg = t('Запись не загрузилась. Проверьте интернет.');
    try {
      await InternetAddress.lookup('aobible.app').timeout(const Duration(seconds: 3));
    } catch (_) {
      msg = t('Нет интернета. Чтобы слушать без сети, скачайте книгу заранее: Настройки → «Аудио».');
    }
    _timingKey = null;
    _loadedUrl = null;
    _set((x) => x.copyWith(loading: false, playing: false, error: msg));
  }

  void _emitTime(double posAbs) {
    final p = _player, ch = _timing;
    if (p == null || ch == null) return;
    final (start, len) = ch.span((p.duration ?? Duration.zero).inMilliseconds / 1000);
    final pos = (posAbs - start).clamp(0, len == 0 ? double.infinity : len).toDouble();
    final old = time.value;
    // Подписчиков (ползунок и время) будим раз в секунду, а не на каждое событие позиции
    if (pos.floor() == old.pos.floor() && len == old.len) return;
    time.value = TimeSnap(pos, len);
  }

  void _syncVerse(double posAbs) {
    final ch = _timing, r = s.ref;
    if (ch == null || r == null) return;
    final key = _timingKey!.split('.');
    final cur = ch.verseAt(posAbs);
    if (cur != null && cur != r.verse) _set((x) => x.copyWith(ref: VerseRef(key[0], int.parse(key[1]), cur)));
  }

  void _onPosition(Duration d) {
    final ch = _timing;
    if (ch == null || !s.active || _switching) return;
    final sec = d.inMilliseconds / 1000;
    _emitTime(sec);
    // Глава кончилась внутри общего файла — переходим к следующей
    if (ch.end != null && sec >= ch.end! - 0.05) {
      _chapterEnded();
      return;
    }
    _syncVerse(sec);
  }

  // Конец файла. Если глава вырезана из общего файла, к следующей мы уже перешли по позиции — не повторяем
  Future<void> _onCompleted() async {
    if (!s.playing || s.ref == null || _switching) return;
    if (DateTime.now().difference(_lastAdvance) < const Duration(seconds: 2)) return;
    await _chapterEnded();
  }

  Future<void> _chapterEnded() async {
    if (_advancing || !s.playing || s.ref == null || _timingKey == null) return;
    _advancing = true;
    _lastAdvance = DateTime.now();
    try {
      final k = _timingKey!.split('.');
      final book = k[0], chapter = int.parse(k[1]);
      final vs = _shape(book).verses[chapter] ?? const <int>[];
      final next = _neighbourVerse(VerseRef(book, chapter, vs.isEmpty ? 1 : vs.last), 1);
      if (next == null) {
        await pause();
        return;
      }
      if (s.sleep?.kind == 'chapter') {
        _set((x) => x.copyWith(sleep: null));
        await pause();
        return;
      }
      // Следующая глава в том же файле и сразу за этой — просто продолжаем, без перемотки
      final pack = await loadPack(_timingPack!);
      final ch = pack?.chapters['${next.book}.${next.chapter}'];
      final cur = _timing;
      if (ch != null && cur != null && ch.url == cur.url && ch.start != null && (ch.start! - (cur.end ?? -9)).abs() < 1) {
        _timing = ch;
        _timingKey = '${next.book}.${next.chapter}';
        time.value = const TimeSnap(0, 0);
        _set((x) => x.copyWith(ref: next));
        return;
      }
      _stopEngines();
      _set((x) => x.copyWith(ref: next));
      await _playFrom(next);
    } finally {
      _advancing = false;
    }
  }

  // --- Соседние стихи и главы ----------------------------------------------------------------

  BookShape _shape(String book) {
    final m = s.moduleId ?? '';
    return _shapes['$m|$book'] ??= _buildShape(m, book);
  }

  BookShape _buildShape(String moduleId, String book) {
    final out = <int, List<int>>{};
    try {
      for (final it in loadBook(moduleId, book).items) {
        if (it.kind == ItemKind.verse) (out[it.chapter] ??= []).add(it.verse);
      }
    } catch (_) {
      // книги нет в переводе
    }
    return BookShape(out);
  }

  List<String> get _books => bookList(s.moduleId ?? '').map((b) => b['id'] as String).toList();

  VerseRef? _neighbourVerse(VerseRef r, int dir) => neighbourVerse(r, dir, _books, _shape);
  VerseRef? _neighbourChapter(VerseRef r, int dir) => neighbourChapter(r, dir, _books, _shape);

  // --- Уведомление и экран блокировки --------------------------------------------------------

  void _publishItem(AudioPack pack) {
    final h = _handler, r = s.ref;
    if (h == null || r == null) return;
    h.mediaItem.add(MediaItem(
      id: '${pack.id}|${r.book}.${r.chapter}',
      title: '${Books.instance.meta(r.book).name} ${r.chapter}',
      album: pack.title,
      artist: ModuleStore.instance.get(s.moduleId ?? '')?.name,
      duration: time.value.len > 0 ? Duration(seconds: time.value.len.round()) : null,
    ));
  }

  void _publish() {
    final h = _handler, a = s;
    if (h == null || !a.active) return;
    final pos = Duration(seconds: time.value.pos.round());
    h.playbackState.add(PlaybackState(
      controls: [MediaControl.skipToPrevious, a.playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext, MediaControl.stop],
      systemActions: const {MediaAction.seek, MediaAction.skipToNext, MediaAction.skipToPrevious},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: a.loading ? AudioProcessingState.loading : AudioProcessingState.ready,
      playing: a.playing,
      updatePosition: pos,
      speed: a.rate,
    ));
    final item = h.mediaItem.value;
    final r = a.ref;
    if (item != null && r != null && !item.id.endsWith('|${r.book}.${r.chapter}')) {
      final pack = _timingPack;
      h.mediaItem.add(item.copyWith(id: '${pack ?? ''}|${r.book}.${r.chapter}', title: '${Books.instance.meta(r.book).name} ${r.chapter}'));
    }
  }
}

/// Кнопки уведомления и экрана блокировки: ▶/⏸, глава назад/вперёд, стоп, перемотка по главе
class AoAudioHandler extends BaseAudioHandler with SeekHandler {
  AoAudioHandler(this._e);
  final AudioEngine _e;

  @override
  Future<void> play() => _e.resume();
  @override
  Future<void> pause() => _e.pause();
  @override
  Future<void> stop() => _e.stop();
  @override
  Future<void> skipToNext() => _e.stepChapter(1);
  @override
  Future<void> skipToPrevious() => _e.stepChapter(-1);
  @override
  Future<void> seek(Duration position) => _e.seekChapter(position.inMilliseconds / 1000);
}

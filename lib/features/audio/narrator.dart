// Диктор: когда для главы нет записи живого чтеца, главу читает нейросетевой голос «Дмитрий» (Piper ru_RU-dmitri-medium,
// CC0) через sherpa-onnx (Apache-2.0). Голос скачивается по желанию (~36 МБ) и работает на телефоне без интернета.
// Здесь: установка голоса, синтез в отдельном потоке (Isolate), решение «читать / предложить / не читать».
// Само чтение стих за стихом — в AudioEngine (тот же плеер, что у записей).
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/books.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'audio_engine.dart';

/// Значение AudioState.source, когда читает диктор
const narratorSource = 'narrator';

const voiceUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-dmitri-medium-fp16.tar.bz2';
const voiceSizeMb = 36;

/// Включено ли «Читать диктором, когда нет записи» (по умолчанию да)
bool get narratorEnabled => prefs.getBool('narratorOn') ?? true;
set narratorEnabled(bool v) => prefs.setBool('narratorOn', v);

/// Что делать, когда записи нет: читать сразу, предложить скачать голос или только сообщить
enum NarratorPlan { read, offer, none }

NarratorPlan narratorPlanFor({required bool enabled, required String language, required bool installed}) {
  if (!enabled || language != 'ru') return NarratorPlan.none; // голос только русский: чужой язык он прочтёт нечленораздельно
  return installed ? NarratorPlan.read : NarratorPlan.offer;
}

/// Движок спрашивает диктора, когда записи нет. true — чтение началось или показано предложение голоса.
Future<bool> narrateFallback({required int pane, required String moduleId, required VerseRef from}) async {
  final plan = narratorPlanFor(
    enabled: narratorEnabled,
    language: ModuleStore.instance.get(moduleId)?.language ?? 'ru',
    installed: NarratorVoice.I.installed.value,
  );
  switch (plan) {
    case NarratorPlan.none:
      return false;
    case NarratorPlan.offer:
      AudioEngine.I.offerNarrator(pane, moduleId, from);
      return true;
    case NarratorPlan.read:
      await AudioEngine.I.startNarrated(pane, moduleId, from);
      return true;
  }
}

/// Текст стиха для голоса: без знаков ударения и лишних пробелов; пусто, если читать нечего
String narrationText(String s) {
  final x = s.replaceAll('́', '').replaceAll('­', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(x) ? x : '';
}

/// WAV (16 бит, моно) из отсчётов синтеза
Uint8List pcm16Wav(Float32List samples, int rate) {
  final n = samples.length;
  final out = ByteData(44 + n * 2);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + n * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // моно
  out.setUint32(24, rate, Endian.little);
  out.setUint32(28, rate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  out.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    out.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

// --- Распаковка архива голоса (вызывается в отдельном потоке) -----------------------------------

/// Распаковывает .tar.bz2 потоком (в памяти держится окно, а не весь архив) в [outDir]; пути с «..» отбрасываются
void extractVoiceArchive(String archivePath, String outDir) {
  final input = InputFileStream(archivePath);
  try {
    final root = Directory(outDir)..createSync(recursive: true);
    final base = root.absolute.path;
    TarDecoder().decodeStream(
      BZip2Decoder().decodeLazy(input),
      keepEntries: false,
      callback: (f) {
        final name = f.name.replaceAll('\\', '/');
        if (name.startsWith('/') || name.split('/').contains('..')) return;
        final path = '$base${Platform.pathSeparator}$name';
        if (f.isFile) {
          File(path)
            ..createSync(recursive: true)
            ..writeAsBytesSync(f.content);
        } else {
          Directory(path).createSync(recursive: true);
        }
      },
    );
  } finally {
    input.closeSync();
  }
}

// Отдельная функция: замыкание внутри метода захватило бы NarratorVoice, а его в другой поток не отправить
Future<void> _unpackInIsolate(String archivePath, String outDir) => Isolate.run(() => extractVoiceArchive(archivePath, outDir));

/// Папка, где лежат tokens.txt и модель (в архиве голос внутри одной папки)
Directory? findModelDir(Directory d) {
  if (File('${d.path}${Platform.pathSeparator}tokens.txt').existsSync()) return d;
  for (final e in d.listSync().whereType<Directory>()) {
    final r = findModelDir(e);
    if (r != null) return r;
  }
  return null;
}

// --- Синтез ----------------------------------------------------------------------------------

abstract class SynthBackend {
  /// Озвучить [text] в WAV-файл [outPath]; false — не вышло
  Future<bool> synth(String text, String outPath);
  Future<void> close();
}

typedef Fetcher = Future<void> Function(Uri url, File to, void Function(int got, int total) onProgress, bool Function() cancelled);

class NarratorVoice {
  NarratorVoice._();
  static final I = NarratorVoice._();

  // Точки подмены для тестов
  static Future<Directory> Function() rootDir = () async => Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}narrator');
  static Future<Directory> Function() tempDir = () async => Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}narrator');
  static Fetcher fetcher = _httpFetch;
  static Future<SynthBackend> Function(String modelDir) openBackend = _openIsolateBackend;

  final installed = ValueNotifier<bool>(false);
  final progress = ValueNotifier<double?>(null); // доля скачанного; null — размер неизвестен или идёт распаковка
  final busy = ValueNotifier<String?>(null); // 'download' | 'unpack' | null
  final bytes = ValueNotifier<int>(0); // сколько занимает голос на телефоне

  Future<void>? _installing;
  bool _cancelled = false;
  Future<SynthBackend>? _opening;

  Future<String> _voiceDir() async => '${(await rootDir()).path}${Platform.pathSeparator}voice';

  /// Проверить, стоит ли голос (при запуске и после установки/удаления)
  Future<void> refresh() async {
    final d = Directory(await _voiceDir());
    var ok = false;
    var size = 0;
    if (d.existsSync()) {
      final sep = Platform.pathSeparator;
      ok = File('${d.path}${sep}tokens.txt').existsSync() && _hasModel(d) && Directory('${d.path}${sep}espeak-ng-data').existsSync();
      if (ok) {
        for (final f in d.listSync(recursive: true).whereType<File>()) {
          size += f.lengthSync();
        }
      }
    }
    bytes.value = size;
    installed.value = ok;
  }

  bool _hasModel(Directory d) => d.listSync().whereType<File>().any((f) => f.path.endsWith('.onnx'));

  /// Скачать и распаковать голос. Повторный вызов во время загрузки ждёт ту же загрузку.
  Future<void> install() => _installing ??= _install().whenComplete(() => _installing = null);

  void cancel() => _cancelled = true;

  Future<void> _install() async {
    final root = await rootDir();
    root.createSync(recursive: true);
    final sep = Platform.pathSeparator;
    final arc = File('${root.path}${sep}voice.tar.bz2.part');
    final tmp = Directory('${root.path}${sep}voice.tmp');
    _cancelled = false;
    progress.value = 0;
    busy.value = 'download';
    try {
      var last = -1.0;
      await fetcher(Uri.parse(voiceUrl), arc, (got, total) {
        final v = total > 0 ? got / total : null;
        if (v == null || v - last >= 0.005) {
          last = v ?? last;
          progress.value = v;
        }
      }, () => _cancelled);
      busy.value = 'unpack';
      progress.value = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      await _unpackInIsolate(arc.path, tmp.path);
      final model = findModelDir(tmp);
      if (model == null) throw Exception('в архиве нет голоса');
      final target = Directory(await _voiceDir());
      if (target.existsSync()) target.deleteSync(recursive: true);
      model.renameSync(target.path);
      await refresh();
      if (!installed.value) throw Exception('голос не распознан');
    } finally {
      if (arc.existsSync()) arc.deleteSync(); // архив после распаковки не нужен
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      busy.value = null;
      progress.value = null;
    }
  }

  Future<void> remove() async {
    await closeBackend();
    final d = Directory(await _voiceDir());
    if (d.existsSync()) d.deleteSync(recursive: true);
    await refresh();
  }

  /// Озвучить текст (модель создаётся при первом обращении и держится до closeBackend)
  Future<bool> synth(String text, String outPath) async {
    final b = await (_opening ??= _open());
    return b.synth(text, outPath);
  }

  Future<SynthBackend> _open() async {
    try {
      return await openBackend(await _voiceDir());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  /// Чтение закончено: освободить модель (она занимает около 100 МБ)
  Future<void> closeBackend() async {
    final pending = _opening;
    _opening = null;
    if (pending == null) return;
    try {
      await (await pending).close();
    } catch (_) {
      // не открылся — закрывать нечего
    }
  }
}

Future<void> _httpFetch(Uri url, File to, void Function(int, int) onProgress, bool Function() cancelled) async {
  final c = http.Client();
  IOSink? sink;
  try {
    final res = await c.send(http.Request('GET', url));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: url);
    sink = to.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      if (cancelled()) throw Exception('отменено');
      sink.add(chunk);
      got += chunk.length;
      onProgress(got, res.contentLength ?? 0);
    }
    await sink.flush();
  } finally {
    await sink?.close();
    c.close();
  }
}

// --- Поток-синтезатор --------------------------------------------------------------------------

class _IsolateBackend implements SynthBackend {
  _IsolateBackend(this._cmd, this._rp, this._iso);
  final SendPort _cmd;
  final ReceivePort _rp;
  final Isolate _iso;
  final _pending = <int, Completer<bool>>{};
  int _id = 0;
  bool _closed = false;

  void _onMessage(Object? m) {
    if (m is List && m.isNotEmpty && m[0] == 'done') _pending.remove(m[1])?.complete(m[2] == true);
  }

  void _failAll() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _pending.clear();
  }

  @override
  Future<bool> synth(String text, String outPath) {
    if (_closed) return Future.value(false);
    final c = Completer<bool>();
    final id = _id++;
    _pending[id] = c;
    _cmd.send([id, text, outPath]);
    return c.future;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cmd.send('close');
    _failAll();
    _rp.close();
    // даём потоку освободить модель, потом принудительно
    Timer(const Duration(seconds: 2), () => _iso.kill(priority: Isolate.immediate));
  }
}

Future<SynthBackend> _openIsolateBackend(String modelDir) async {
  final rp = ReceivePort();
  final exit = ReceivePort();
  final ready = Completer<SendPort>();
  _IsolateBackend? backend;
  rp.listen((m) {
    if (m is List && m.isNotEmpty && m[0] == 'ready' && !ready.isCompleted) {
      ready.complete(m[1] as SendPort);
    } else if (m is List && m.isNotEmpty && m[0] == 'error' && !ready.isCompleted) {
      ready.completeError(Exception(m[1]));
    } else {
      backend?._onMessage(m);
    }
  });
  final iso = await Isolate.spawn(_synthMain, [rp.sendPort, modelDir], onExit: exit.sendPort, errorsAreFatal: true);
  exit.listen((_) {
    exit.close();
    if (!ready.isCompleted) ready.completeError(Exception('синтезатор остановился'));
    backend?._failAll();
  });
  final cmd = await ready.future;
  return backend = _IsolateBackend(cmd, rp, iso);
}

/// Точка входа потока: модель создаётся один раз, дальше отвечает на запросы [id, текст, путь]
Future<void> _synthMain(List<Object?> args) async {
  final out = args[0] as SendPort;
  final dir = args[1] as String;
  sherpa.OfflineTts tts;
  final port = ReceivePort();
  try {
    await sherpa.initBindingsAsync();
    final sep = Platform.pathSeparator;
    final model = Directory(dir).listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.onnx'));
    tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(model: model.path, tokens: '$dir${sep}tokens.txt', dataDir: '$dir${sep}espeak-ng-data'),
        numThreads: 2,
        debug: false,
      ),
    ));
  } catch (e) {
    out.send(['error', '$e']);
    return;
  }
  out.send(['ready', port.sendPort]);
  await for (final m in port) {
    if (m == 'close') {
      tts.free();
      port.close();
      break;
    }
    final req = m as List;
    var ok = false;
    try {
      final a = tts.generate(text: req[1] as String, sid: 0, speed: 1.0);
      if (a.samples.isNotEmpty) {
        File(req[2] as String).writeAsBytesSync(pcm16Wav(a.samples, a.sampleRate));
        ok = true;
      }
    } catch (_) {
      ok = false;
    }
    out.send(['done', req[0], ok]);
  }
}

// Диктор: установка голоса (сеть подменена), распаковка архива, подготовка текста, WAV, решение «читать / предложить».
// Настоящий синтез sherpa_onnx здесь не запускается — вместо него поддельный движок.
import 'dart:io';
import 'dart:typed_data';

import 'package:aobible/features/audio/narrator.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _voiceArchive({bool withModel = true}) {
  final a = Archive();
  void add(String name, List<int> data) => a.add(ArchiveFile(name, data.length, data));
  if (withModel) {
    add('vits-piper-ru_RU-dmitri-medium-fp16/ru_RU-dmitri-medium.onnx', List.filled(1000, 7));
    add('vits-piper-ru_RU-dmitri-medium-fp16/tokens.txt', 'a 1\nb 2\n'.codeUnits);
    add('vits-piper-ru_RU-dmitri-medium-fp16/espeak-ng-data/voices/ru', 'x'.codeUnits);
  } else {
    add('readme.txt', 'нет голоса'.codeUnits);
  }
  add('../evil.txt', 'x'.codeUnits); // выход из папки отбрасывается
  return Uint8List.fromList(BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(a)));
}

class _FakeBackend implements SynthBackend {
  final texts = <String>[];
  bool closed = false;
  @override
  Future<bool> synth(String text, String outPath) async {
    texts.add(text);
    File(outPath).writeAsBytesSync(pcm16Wav(Float32List.fromList([0, 0.5, -0.5]), 22050));
    return true;
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('narr_test');
    NarratorVoice.rootDir = () async => Directory('${tmp.path}/root');
    NarratorVoice.tempDir = () async => Directory('${tmp.path}/tmp');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('текст для голоса: без ударений и лишних пробелов, пустое — пусто', () {
    expect(narrationText('В нача́ле  сотвори́л\n Бог'), 'В начале сотворил Бог');
    expect(narrationText('  —  '), '');
    expect(narrationText(''), '');
  });

  test('WAV: заголовок и отсчёты', () {
    final w = pcm16Wav(Float32List.fromList([0, 1, -1, 2]), 22050);
    final d = ByteData.sublistView(w);
    expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
    expect(d.getUint32(24, Endian.little), 22050);
    expect(d.getUint32(40, Endian.little), 8);
    expect(w.length, 44 + 8);
    expect(d.getInt16(46, Endian.little), 32767);
    expect(d.getInt16(48, Endian.little), -32767);
    expect(d.getInt16(50, Endian.little), 32767); // выше 1 обрезается
  });

  test('читать, предлагать голос или молчать', () {
    expect(narratorPlanFor(enabled: true, language: 'ru', installed: true), NarratorPlan.read);
    expect(narratorPlanFor(enabled: true, language: 'ru', installed: false), NarratorPlan.offer);
    expect(narratorPlanFor(enabled: false, language: 'ru', installed: true), NarratorPlan.none);
    expect(narratorPlanFor(enabled: true, language: 'en', installed: true), NarratorPlan.none);
  });

  test('распаковка: файлы на месте, «..» отброшены', () {
    final arc = File('${tmp.path}/a.tar.bz2')..writeAsBytesSync(_voiceArchive());
    extractVoiceArchive(arc.path, '${tmp.path}/out');
    final model = findModelDir(Directory('${tmp.path}/out'))!;
    expect(File('${model.path}/tokens.txt').existsSync(), true);
    expect(File('${model.path}/ru_RU-dmitri-medium.onnx').lengthSync(), 1000);
    expect(File('${model.path}/espeak-ng-data/voices/ru').existsSync(), true);
    expect(File('${tmp.path}/evil.txt').existsSync(), false);
  });

  test('установка: ход загрузки, архив удалён, голос виден, удаление', () async {
    final v = NarratorVoice.I;
    await v.refresh();
    expect(v.installed.value, false);
    final bytes = _voiceArchive();
    final seen = <double?>[];
    v.progress.addListener(() => seen.add(v.progress.value));
    NarratorVoice.fetcher = (url, to, onProgress, cancelled) async {
      expect(url.toString(), voiceUrl);
      to.writeAsBytesSync(bytes);
      onProgress(bytes.length ~/ 2, bytes.length);
      onProgress(bytes.length, bytes.length);
    };
    await v.install();
    expect(v.installed.value, true);
    expect(v.busy.value, null);
    expect(v.bytes.value, greaterThan(1000));
    expect(seen.any((x) => x != null && x > 0.4 && x < 0.6), true);
    expect(Directory('${tmp.path}/root').listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last).toList(), ['voice']); // ни архива, ни voice.tmp
    await v.remove();
    expect(v.installed.value, false);
    expect(Directory('${tmp.path}/root/voice').existsSync(), false);
  });

  test('сбой сети: голос не установлен, состояние чистое', () async {
    final v = NarratorVoice.I;
    NarratorVoice.fetcher = (url, to, onProgress, cancelled) async => throw const SocketException('нет сети');
    await expectLater(v.install(), throwsA(isA<SocketException>()));
    expect(v.installed.value, false);
    expect(v.busy.value, null);
    expect(v.progress.value, null);
    // и архив без голоса не считается установкой
    final bad = _voiceArchive(withModel: false);
    NarratorVoice.fetcher = (url, to, onProgress, cancelled) async => to.writeAsBytesSync(bad);
    await expectLater(v.install(), throwsA(isA<Exception>()));
    expect(v.installed.value, false);
  });

  test('синтез идёт через подменённый движок и закрывается', () async {
    final v = NarratorVoice.I;
    final fake = _FakeBackend();
    var opened = 0;
    NarratorVoice.openBackend = (dir) async {
      opened++;
      return fake;
    };
    final out = '${tmp.path}/v.wav';
    expect(await v.synth('Привет', out), true);
    expect(await v.synth('Мир', out), true);
    expect(opened, 1); // модель создаётся один раз
    expect(fake.texts, ['Привет', 'Мир']);
    expect(File(out).lengthSync(), 44 + 6);
    await v.closeBackend();
    expect(fake.closed, true);
  });
}

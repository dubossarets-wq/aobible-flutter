// Фон под текстом (App.jsx «Своя картинка под текстом», userBg.js, .has-user-bg .reader::before/::after в styles.css).
// Картинка — готовое фото с сайта или своё — лежит файлом на устройстве (в веб-версии IndexedDB). Настройки:
// bgImage (метка времени выбора, 0 — нет фона), bgPhoto (id готового фото или null — своя), bgVeil (% цвета страницы
// поверх картинки, по умолчанию 72), bgBlur (размытие, px). Виджет ReaderBackground рисует картинку, размытие и вуаль.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/settings.dart';
import '../plans/net_cache.dart' show siteFile;
import 'colors.dart';

/// Папка для картинки (тесты подставляют свою; по умолчанию — служебная папка приложения)
Directory? userBgDir;

/// Файлы сайта (готовые фото): сеть с копией на диске; в тестах подменяется
Future<Uint8List?> Function(String path) loadSiteBytes = siteFile;

const _maxSide = 1600;

class UserBg {
  UserBg._();

  /// Растёт при каждой смене картинки — ReaderBackground перечитывает файл
  static final version = ValueNotifier<int>(0);
  static Uint8List? _cache;
  static bool _loaded = false;

  static Future<File> _file() async {
    final dir = userBgDir ?? Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}user_bg');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}bg.img');
  }

  /// Сохранить картинку; слишком большую сперва уменьшаем до 1600 px по большей стороне (userBg.js, shrink)
  static Future<void> save(Uint8List bytes) async {
    final small = await _shrink(bytes);
    await (await _file()).writeAsBytes(small, flush: true);
    _cache = small;
    _loaded = true;
    version.value++;
  }

  /// Уже прочитанная картинка (или null) — чтобы фон не мигал при перерисовке
  static Uint8List? get cached => _loaded ? _cache : null;

  static Future<Uint8List?> load() async {
    if (_loaded) return _cache;
    try {
      final f = await _file();
      _cache = f.existsSync() ? await f.readAsBytes() : null;
    } catch (_) {
      _cache = null;
    }
    _loaded = true;
    return _cache;
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // файла нет — и хорошо
    }
    _cache = null;
    _loaded = true;
    version.value++;
  }

  static Future<Uint8List> _shrink(Uint8List bytes) async {
    final ui.ImageDescriptor d;
    try {
      d = await ui.ImageDescriptor.encoded(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      throw const FormatException('bad-image');
    }
    final big = d.width > _maxSide || d.height > _maxSide;
    if (!big) {
      d.dispose();
      return bytes;
    }
    final k = _maxSide / (d.width > d.height ? d.width : d.height);
    final codec = await d.instantiateCodec(targetWidth: (d.width * k).round(), targetHeight: (d.height * k).round());
    final img = (await codec.getNextFrame()).image;
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    codec.dispose();
    d.dispose();
    if (data == null) throw const FormatException('bad-image');
    return data.buffer.asUint8List();
  }
}

/// Метка выбранной картинки (0 — фона нет)
int bgStamp(Settings s) => (s.j['bgImage'] as num?)?.toInt() ?? 0;
String? bgPhotoId(Settings s) => s.j['bgPhoto'] as String?;
double bgVeil(Settings s) => ((s.j['bgVeil'] as num?) ?? 72).toDouble();
double bgBlur(Settings s) => ((s.j['bgBlur'] as num?) ?? 0).toDouble();

/// Картинка под текстом: само фото (размытое на bgBlur px, чуть увеличенное, чтобы края не светились) и поверх —
/// цвет страницы с непрозрачностью bgVeil %. Без фона (bgImage = 0) и пока файл не прочитан — ничего не рисует,
/// видна обычная страница. Вставляется под текст читалки: Stack(children: [Positioned.fill(child: ReaderBackground()), …]).
class ReaderBackground extends ConsumerWidget {
  const ReaderBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(settingsProvider.select((s) => (bgStamp(s), bgVeil(s), bgBlur(s), effectivePalette(s).bg)));
    final (stamp, veil, blur, page) = cfg;
    if (stamp == 0) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: UserBg.version,
      builder: (context, _, _) => FutureBuilder<Uint8List?>(
        future: UserBg.load(),
        initialData: UserBg.cached,
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) return const SizedBox.shrink();
          Widget img = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.low);
          if (blur > 0) img = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: img);
          return IgnorePointer(
            child: ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                Transform.scale(scale: 1.04, child: img),
                ColoredBox(color: page.withValues(alpha: (veil / 100).clamp(0, 1))),
              ]),
            ),
          );
        },
      ),
    );
  }
}

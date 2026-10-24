// Картинки и списки с сайта (обложки планов, фото для «Стиха дня»): через общий загрузчик core/net.dart (с зеркалом
// и корнями Let's Encrypt для старых Android), с копией на диске — после первого раза работают без сети.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/net.dart';

final _mem = <String, Future<Uint8List?>>{};
Directory? _dir;

Future<File> _file(String path) async {
  _dir ??= Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}site_cache')..createSync(recursive: true);
  return File('${_dir!.path}${Platform.pathSeparator}${path.replaceAll(RegExp(r'[/\:]'), '_')}');
}

/// Файл сайта: сначала сеть (и копия на диск), при неудаче — копия; null — нет ни того ни другого
Future<Uint8List?> siteFile(String path, {bool preferCache = true}) {
  return _mem.putIfAbsent(path, () async {
    File? f;
    try {
      f = await _file(path);
      if (preferCache && f.existsSync()) return await f.readAsBytes();
    } catch (_) {}
    try {
      final bytes = await download(path);
      try {
        await f?.writeAsBytes(bytes);
      } catch (_) {}
      return bytes;
    } catch (_) {
      try {
        if (f != null && f.existsSync()) return await f.readAsBytes();
      } catch (_) {}
      _mem.remove(path); // не вышло — в следующий раз попробуем снова
      return null;
    }
  });
}

Future<Map<String, dynamic>?> siteJson(String path) async {
  final b = await siteFile(path, preferCache: false);
  if (b == null) return null;
  try {
    return (jsonDecode(utf8.decode(b)) as Map).cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

/// Картинка с сайта (путь относительно корня сайта)
class SiteImage extends StatelessWidget {
  const SiteImage(this.path, {super.key, this.fit = BoxFit.cover, this.fallback});
  final String path;
  final BoxFit fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: siteFile(path),
        builder: (_, s) => s.data == null ? (fallback ?? const SizedBox.shrink()) : Image.memory(s.data!, fit: fit, gaplessPlayback: true),
      );
}

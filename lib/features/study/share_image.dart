// «Поделиться» картинкой с подписью (иллюстрация к стиху, карта) и местом на карте (название, координаты, ссылки).
// Порт ShareTools.swift (iPhone): картинка уходит файлом, подпись — текстом; нет сети — уходит одна подпись.
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

String _safeName(String s) => s.replaceAll(RegExp(r'[^\wА-Яа-яЁё\-]+'), '_').replaceAll(RegExp(r'_+'), '_');

String imageExtOf(String url) {
  final p = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  for (final e in ['png', 'jpg', 'jpeg', 'webp', 'gif']) {
    if (p.endsWith('.$e')) return e;
  }
  return 'jpg';
}

/// Отправить уже загруженную картинку с подписью
Future<void> shareImageBytes(Uint8List bytes, {required String name, required String text, String ext = 'png'}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}${_safeName(name)}.$ext');
  await f.writeAsBytes(bytes, flush: true);
  final mime = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], text: text, title: name));
}

/// Скачать картинку по ссылке (уже открытая берётся из кэша системы) и отправить с подписью.
/// Не вышло скачать — уходит одна подпись
Future<void> shareRemoteImage(String url, {required String name, required String text}) async {
  try {
    final r = await http.get(Uri.parse(url), headers: const {'User-Agent': 'Kolos/1.0 (https://aobible.app)'}).timeout(const Duration(seconds: 25));
    if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
      return await shareImageBytes(r.bodyBytes, name: name, text: text, ext: imageExtOf(url));
    }
  } catch (_) {
    // нет сети — только подпись
  }
  await SharePlus.instance.share(ShareParams(text: text, title: name));
}

/// Текст для отправки места: название, нынешнее название, координаты и ссылки на карты (открываются у любого получателя)
String placeShareText({required String name, required String modern, required double lat, required double lng}) {
  final apple = Uri.https('maps.apple.com', '/', {'ll': '$lat,$lng', 'q': name});
  final google = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});
  return [
    name,
    if (modern.isNotEmpty) modern,
    '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
    'Apple Maps: $apple',
    'Google Maps: $google',
  ].join('\n');
}

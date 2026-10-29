// Книги без интернета (аналог offlineAudio.js): записи глав скачиваются в папку приложения audio/,
// проигрыватель сначала ищет файл там. Список скачанного — в prefs «offlineAudio» (тот же формат, что в веб-версии):
// { 'аудиомодуль|книга': { at, files, bytes } }.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/i18n.dart';
import '../../core/net.dart' show newHttpClient;
import '../../core/settings.dart';
import 'audio_data.dart';
import 'audio_logic.dart';

/// Остановка скачивания
class CancelToken {
  bool cancelled = false;
}

class OfflineAudio {
  static Directory? _dir;

  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    return _dir = await Directory('${base.path}${Platform.pathSeparator}audio').create(recursive: true);
  }

  /// Для тестов и если папка известна заранее
  static void useDir(Directory d) => _dir = d;

  static Map<String, dynamic> list() {
    try {
      return (jsonDecode(prefs.getString('offlineAudio') ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, dynamic> m) => prefs.setString('offlineAudio', jsonEncode(m));

  static bool isBookOffline(String audioId, String book) => list().containsKey('$audioId|$book');

  /// Имя файла по адресу записи (FNV-1a — одинаково при каждом запуске)
  static String fileName(String url) {
    var h1 = 0x811c9dc5, h2 = 0x01234567;
    for (final b in utf8.encode(url)) {
      h1 = ((h1 ^ b) * 0x01000193) & 0xffffffff;
      h2 = ((h2 + b) * 0x2f0b4a27 ^ (h2 >> 7)) & 0xffffffff;
    }
    final ext = url.toLowerCase().contains('.m4a') ? 'm4a' : url.toLowerCase().contains('.ogg') ? 'ogg' : 'mp3';
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}.$ext';
  }

  /// Путь скачанной записи или null (тогда играем из сети)
  static Future<String?> localPath(String url) async {
    try {
      final f = File('${(await dir()).path}${Platform.pathSeparator}${fileName(url)}');
      return await f.exists() && await f.length() > 0 ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Скачать все записи книги. onProgress(готово, всего, байт). Возвращает размер.
  static Future<int> downloadBook(AudioPack pack, String book, {void Function(int done, int total, int bytes)? onProgress, CancelToken? cancel}) async {
    final urls = pack.urlsOf(book);
    if (urls.isEmpty) throw Exception(t('К этой книге нет аудиозаписей.'));
    final d = await dir();
    final client = await newHttpClient();
    var bytes = 0;
    try {
      for (var i = 0; i < urls.length; i++) {
        if (cancel?.cancelled ?? false) throw Exception(t('Остановлено'));
        final target = File('${d.path}${Platform.pathSeparator}${fileName(urls[i])}');
        if (await target.exists() && await target.length() > 0) {
          bytes += await target.length();
        } else {
          final part = File('${target.path}.part');
          final req = await client.getUrl(Uri.parse(urls[i]));
          final res = await req.close();
          if (res.statusCode != 200) {
            await res.drain<void>();
            throw Exception(t('Запись не скачалась (ошибка {status}). Проверьте интернет.', {'status': '${res.statusCode}'}));
          }
          final sink = part.openWrite();
          try {
            await for (final chunk in res) {
              if (cancel?.cancelled ?? false) throw Exception(t('Остановлено'));
              sink.add(chunk);
            }
          } catch (_) {
            await sink.close();
            if (await part.exists()) await part.delete();
            rethrow;
          }
          await sink.close();
          await part.rename(target.path);
          bytes += await target.length();
        }
        onProgress?.call(i + 1, urls.length, bytes);
      }
    } on SocketException {
      throw Exception(t('Запись не скачалась (ошибка {status}). Проверьте интернет.', {'status': '0'}));
    } finally {
      client.close();
    }
    await _save({...list(), '${pack.id}|$book': {'at': DateTime.now().millisecondsSinceEpoch, 'files': urls.length, 'bytes': bytes}});
    return bytes;
  }

  /// Удалить скачанную книгу (файлы, общие с другой скачанной книгой, остаются)
  static Future<void> removeBook(String audioId, String book) async {
    final all = {...list()}..remove('$audioId|$book');
    await _save(all);
    final keep = <String>{};
    for (final k in all.keys) {
      final p = k.split('|');
      final pack = await loadPack(p[0]);
      if (pack != null) keep.addAll(pack.urlsOf(p[1]));
    }
    final mine = await loadPack(audioId);
    if (mine == null) return;
    final d = await dir();
    for (final u in mine.urlsOf(book)) {
      if (keep.contains(u)) continue;
      final f = File('${d.path}${Platform.pathSeparator}${fileName(u)}');
      if (await f.exists()) await f.delete();
    }
  }
}

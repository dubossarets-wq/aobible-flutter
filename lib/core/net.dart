// Сеть. Модули — с aobible.app, при недоступности — с зеркала на GitHub Pages.
// Android 7.0 не знает корень Let's Encrypt (ISRG Root X1 есть с 7.1.1), а им подписаны оба адреса:
// добавляем корни X1/X2 (assets/certs, с letsencrypt.org) к системным — иначе старые планшеты не подключаются.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

const remote = 'https://aobible.app/';
const mirror = 'https://dubossarets-wq.github.io/ao-bible/';

HttpClient? _client;
bool _useMirror = false;

Future<HttpClient> _http() async {
  if (_client != null) return _client!;
  final ctx = SecurityContext(withTrustedRoots: true);
  for (final f in ['assets/certs/isrg_root_x1.pem', 'assets/certs/isrg_root_x2.pem']) {
    try {
      ctx.setTrustedCertificatesBytes((await rootBundle.load(f)).buffer.asUint8List());
    } catch (_) {
      // такой корень уже есть в системе — не страшно
    }
  }
  return _client = HttpClient(context: ctx)..connectionTimeout = const Duration(seconds: 20);
}

class NetError implements Exception {
  NetError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Скачать файл (путь относительно сайта, например «modules/catalog.json»); onProgress(0..1)
Future<Uint8List> download(String path, {void Function(double)? onProgress}) async {
  Future<Uint8List> get(String base) async {
    final client = await _http();
    final req = await client.getUrl(Uri.parse(base + path));
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final res = await req.close();
    if (res.statusCode != 200) throw NetError('Сервер ответил ошибкой ${res.statusCode}');
    final total = res.contentLength;
    final builder = BytesBuilder(copy: false);
    var got = 0;
    await for (final chunk in res) {
      builder.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress?.call(got / total);
    }
    return builder.takeBytes();
  }

  if (_useMirror) return get(mirror);
  try {
    return await get(remote);
  } on NetError {
    rethrow;
  } catch (_) {
    final bytes = await get(mirror);
    _useMirror = true;
    return bytes;
  }
}

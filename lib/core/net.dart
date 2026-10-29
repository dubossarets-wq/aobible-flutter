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
SecurityContext? _context;

/// Подпись запросов как у браузера на Android: «Dart/3.x (dart:io)» защита сайта (Cloudflare) с некоторых мобильных сетей
/// принимает за робота и отвечает проверкой вместо файла
const appUserAgent = 'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36 AOBible/2';

Future<SecurityContext> _ctx() async {
  if (_context != null) return _context!;
  final ctx = SecurityContext(withTrustedRoots: true);
  for (final f in ['assets/certs/isrg_root_x1.pem', 'assets/certs/isrg_root_x2.pem']) {
    try {
      ctx.setTrustedCertificatesBytes((await rootBundle.load(f)).buffer.asUint8List());
    } catch (_) {
      // такой корень уже есть в системе — не страшно
    }
  }
  return _context = ctx;
}

/// Новый клиент для своих загрузок (аудио без интернета, модули по ссылке): те же корни Let's Encrypt и подпись,
/// что у основного — иначе на Android 7.0 и в «строгих» сетях они не скачиваются
Future<HttpClient> newHttpClient() async => HttpClient(context: await _ctx())
  ..connectionTimeout = const Duration(seconds: 20)
  ..userAgent = appUserAgent;

Future<HttpClient> _http() async => _client ??= await newHttpClient();

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
    // загрузка «встала» посередине (плохая связь, сеть душит адрес) — ошибка, а не вечное ожидание
    await for (final chunk in res.timeout(const Duration(seconds: 30))) {
      builder.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress?.call(got / total);
    }
    return builder.takeBytes();
  }

  if (_useMirror) return get(mirror);
  try {
    return await get(remote);
  } catch (first) {
    // aobible.app недоступен, ответил ошибкой или оборвал загрузку — тот же файл с зеркала на GitHub Pages;
    // не вышло и там — наружу обе причины (их видно на экране первой загрузки)
    try {
      final bytes = await get(mirror);
      _useMirror = true;
      return bytes;
    } catch (second) {
      throw NetError('aobible.app: $first; github.io: $second');
    }
  }
}

// Экран не гаснет на «Кафедре» — на всех платформах. Нативная часть: канал aobible/screen в MainActivity (Android)
// и в AppDelegate (iOS, isIdleTimerDisabled).
import 'package:flutter/services.dart';

const _channel = MethodChannel('aobible/screen');

Future<void> keepScreenOn(bool on) async {
  try {
    await _channel.invokeMethod('keepOn', on);
  } catch (_) {
    // канала нет (Windows, тесты) — читаем без этого
  }
}

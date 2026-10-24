// Экран не гаснет на «Кафедре». Нужна нативная часть: канал aobible/screen в MainActivity (см. отчёт — фрагмент Kotlin)
// или пакет wakelock_plus; пока канала нет — просто ничего не происходит.
import 'package:flutter/services.dart';

const _channel = MethodChannel('aobible/screen');

Future<void> keepScreenOn(bool on) async {
  try {
    await _channel.invokeMethod('keepOn', on);
  } catch (_) {
    // канала нет (или не Android) — читаем без этого
  }
}

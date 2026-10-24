// Итоговые цвета: тема + «свои цвета» (colorOverrides, по одному) — как themeColors() в src/core/settings.js.
// Ядро берёт цвета из Settings.palette (без своих цветов); чтобы свои цвета заработали везде, getter palette
// должен вызывать paletteWith(базовая, colorOverrides) — см. отчёт.
import 'package:flutter/material.dart';

import '../../core/settings.dart';

/// Ключи цветов, которые можно менять по одному, и их подписи (COLOR_KEYS в веб-версии)
const colorKeys = <(String, String)>[
  ('accent', 'Акцент интерфейса'),
  ('bar', 'Верхняя панель'),
  ('barText', 'Надписи на верхней панели'),
  ('bg', 'Фон страницы'),
  ('text', 'Текст'),
  ('muted', 'Бледный текст'),
  ('panel', 'Окна и карточки'),
  ('line', 'Линии и рамки'),
  ('verseNum', 'Номера стихов'),
  ('heading', 'Заголовки разделов'),
  ('strong', 'Номера Стронга'),
];

Map<String, dynamic> overridesOf(Settings s) => (s.j['colorOverrides'] as Map?)?.cast<String, dynamic>() ?? const {};

Color? parseHex(Object? v) {
  if (v is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) return null;
  return Color(0xFF000000 | int.parse(v.substring(1), radix: 16));
}

String toHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Базовая палитра с наложенными своими цветами
Palette paletteWith(Palette b, Map<String, dynamic> o) {
  Color pick(String k, Color d) => parseHex(o[k]) ?? d;
  return Palette(
    b.label,
    dark: b.dark,
    bg: pick('bg', b.bg),
    text: pick('text', b.text),
    muted: pick('muted', b.muted),
    accent: pick('accent', b.accent),
    panel: pick('panel', b.panel),
    onAccent: b.onAccent,
    bar: pick('bar', b.bar),
    barText: pick('barText', b.barText),
    line: pick('line', b.line),
    hl: b.hl,
    verseNum: pick('verseNum', b.verseNum),
  );
}

/// Цвета, что сейчас на экране (с учётом своих)
Palette effectivePalette(Settings s) => paletteWith(s.palette, overridesOf(s));

/// Цвет заголовков разделов и номеров Стронга: по умолчанию — акцент
Color headingColor(Settings s) => parseHex(overridesOf(s)['heading']) ?? effectivePalette(s).accent;
Color strongColor(Settings s) => parseHex(overridesOf(s)['strong']) ?? effectivePalette(s).accent;

/// Цвет конкретного ключа (для тонкой настройки)
Color colorFor(Settings s, String key) {
  if (key == 'heading') return headingColor(s);
  if (key == 'strong') return strongColor(s);
  final p = effectivePalette(s);
  return switch (key) {
    'accent' => p.accent,
    'bar' => p.bar,
    'barText' => p.barText,
    'bg' => p.bg,
    'text' => p.text,
    'muted' => p.muted,
    'panel' => p.panel,
    'line' => p.line,
    'verseNum' => p.verseNum,
    _ => p.accent,
  };
}

Color baseColorFor(Settings s, String key) => colorFor(Settings({'theme': s.get<String>('theme')}), key);

/// Светлый ли цвет — чтобы подобрать читаемые надписи и галочку
bool isLight(Color c) => 0.299 * (c.r * 255) + 0.587 * (c.g * 255) + 0.114 * (c.b * 255) > 160;

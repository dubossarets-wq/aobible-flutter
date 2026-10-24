// Шрифты чтения (FONTS из src/core/settings.js) и стиль текста по настройкам.
// Файлы шрифтов Google Fonts (лицензия SIL OFL, тексты лицензий рядом) лежат в assets/fonts; в pubspec.yaml
// они описаны в разделе fonts (см. отчёт). «Системный» — шрифт устройства, Georgia — запасной serif Android.
import 'package:flutter/material.dart';

import '../../core/settings.dart';

class FontDef {
  const FontDef(this.label, this.family, {this.variable = false, this.fallback = const []});
  final String label;
  final String? family; // имя семейства во Flutter; null — системный
  final bool variable; // один файл с осью толщины: wght задаём через fontVariations
  final List<String> fallback;
}

const fontDefs = <String, FontDef>{
  'system': FontDef('Системный', null),
  'PT Serif': FontDef('PT Serif', 'PT Serif', fallback: ['serif']),
  'Literata': FontDef('Literata', 'Literata', variable: true, fallback: ['serif']),
  'Noto Serif': FontDef('Noto Serif', 'Noto Serif', variable: true, fallback: ['serif']),
  'Lora': FontDef('Lora', 'Lora', variable: true, fallback: ['serif']),
  'PT Sans': FontDef('PT Sans', 'PT Sans'),
  'IBM Plex Sans': FontDef('IBM Plex Sans', 'IBM Plex Sans', variable: true),
  'Georgia': FontDef('Georgia', 'Georgia', fallback: ['Noto Serif', 'Times New Roman', 'serif']),
};

FontDef fontOf(Settings s) => fontDefs[s.get<String>('fontFamily')] ?? fontDefs['system']!;

FontWeight weightOf(double w) => FontWeight.values[((w.clamp(100, 900) / 100).round() - 1)];

/// Стиль текста Библии по настройкам: шрифт, толщина, размер. height/цвет задаёт вызывающий.
/// Для читалки (verse_view.dart): style = readerTextStyle(settings).copyWith(color: pal.text, height: …)
TextStyle readerTextStyle(Settings s, {double? size, FontDef? font, double? weight}) {
  final f = font ?? fontOf(s);
  final w = weight ?? s.d('fontWeight');
  return TextStyle(
    fontFamily: f.family,
    fontFamilyFallback: f.fallback.isEmpty ? null : f.fallback,
    fontSize: size ?? s.d('fontSize'),
    fontWeight: weightOf(w),
    fontVariations: f.variable ? [FontVariation('wght', w)] : null,
  );
}

TextAlign textAlignOf(Settings s) => s.get<String>('textAlign') == 'justify' ? TextAlign.justify : TextAlign.left;

/// Включён ли пункт меню «Ещё» (настройка menu; по умолчанию — как в веб-версии)
bool menuFlag(Settings s, String key) {
  final m = (s.j['menu'] as Map?) ?? const {};
  return (m[key] ?? (Settings.defaults['menu'] as Map)[key]) == true;
}

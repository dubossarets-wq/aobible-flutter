// Настройки и темы — значения по умолчанию те же, что в веб-версии (src/core/settings.js).
// Хранятся одним JSON в SharedPreferences; меняются через Riverpod — перерисовывается только то, что зависит.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/shell/colors.dart' show paletteWith;

class Palette {
  const Palette(this.label, {required this.bg, required this.text, required this.muted, required this.accent, required this.panel, required this.onAccent, required this.bar, required this.barText, required this.line, required this.hl, required this.verseNum, this.dark = false});
  final String label;
  final Color bg, text, muted, accent, panel, onAccent, bar, barText, line, hl, verseNum;
  final bool dark;
}

Color _c(int v) => Color(0xFF000000 | v);

final themes = <String, Palette>{
  'light': Palette('Светлая', bg: _c(0xffffff), text: _c(0x121212), muted: _c(0x5f5f5f), accent: _c(0x1c1c1e), panel: _c(0xffffff), onAccent: _c(0xffffff), bar: _c(0xffffff), barText: _c(0x121212), line: _c(0xe7e7e7), hl: _c(0xfbe7a1), verseNum: _c(0x6e6e6e)),
  'warm': Palette('Тёплая', bg: _c(0xf6f5f2), text: _c(0x1d1c1a), muted: _c(0x68655e), accent: _c(0x8c5e28), panel: _c(0xffffff), onAccent: _c(0xffffff), bar: _c(0x38363a), barText: _c(0xf3f1ec), line: _c(0xe3e0d9), hl: _c(0xf6e3a8), verseNum: _c(0x55524c)),
  'sepia': Palette('Сепия', bg: _c(0xf3e9d7), text: _c(0x3b2f22), muted: _c(0x6e604c), accent: _c(0x8b5a24), panel: _c(0xfaf3e6), onAccent: _c(0xffffff), bar: _c(0x4a3d2f), barText: _c(0xf6ecda), line: _c(0xe2d4bb), hl: _c(0xebd189), verseNum: _c(0x6b5a44)),
  'mint': Palette('Мята', bg: _c(0xf2faf6), text: _c(0x14261f), muted: _c(0x4b665b), accent: _c(0x1b7a5c), panel: _c(0xffffff), onAccent: _c(0xffffff), bar: _c(0xe2f2ea), barText: _c(0x14261f), line: _c(0xd3e8dc), hl: _c(0xf5e3a0), verseNum: _c(0x4b665b)),
  'lavender': Palette('Лаванда', bg: _c(0xf6f3fc), text: _c(0x221a33), muted: _c(0x5b5373), accent: _c(0x6346c2), panel: _c(0xffffff), onAccent: _c(0xffffff), bar: _c(0xebe4f8), barText: _c(0x221a33), line: _c(0xe2daf2), hl: _c(0xf3e3a6), verseNum: _c(0x5b5373)),
  'sunset': Palette('Закат', bg: _c(0xfff6f0), text: _c(0x2a1a12), muted: _c(0x6b5243), accent: _c(0xb4451f), panel: _c(0xffffff), onAccent: _c(0xffffff), bar: _c(0xffe5d4), barText: _c(0x2a1a12), line: _c(0xf1dccd), hl: _c(0xfde2a0), verseNum: _c(0x6b5243)),
  'contrast': Palette('Контраст', bg: _c(0xffffff), text: _c(0x000000), muted: _c(0x303030), accent: _c(0x0037b3), panel: _c(0xffffff), onAccent: _c(0xffffff), bar: _c(0x000000), barText: _c(0xffffff), line: _c(0x5c5c5c), hl: _c(0xffe14d), verseNum: _c(0x000000)),
  'dark': Palette('Тёмная', dark: true, bg: _c(0x161617), text: _c(0xdedbd4), muted: _c(0x8d8a84), accent: _c(0xd9a35c), panel: _c(0x212123), onAccent: _c(0x161617), bar: _c(0x0c0c0d), barText: _c(0xe8e5de), line: _c(0x2e2e31), hl: _c(0x5b4a1c), verseNum: _c(0xa7a39b)),
  'ocean': Palette('Океан', dark: true, bg: _c(0x0f1a2a), text: _c(0xdfe7f1), muted: _c(0x93a3b8), accent: _c(0x5cb8f0), panel: _c(0x16243a), onAccent: _c(0x0f1a2a), bar: _c(0x0a1422), barText: _c(0xe6eef8), line: _c(0x24344d), hl: _c(0x1f4a6b), verseNum: _c(0x8ea2bb)),
  'black': Palette('Чёрная', dark: true, bg: _c(0x000000), text: _c(0xe4e4e4), muted: _c(0x9a9a9a), accent: _c(0xe8b86a), panel: _c(0x0f0f10), onAccent: _c(0x000000), bar: _c(0x000000), barText: _c(0xf0f0f0), line: _c(0x28282a), hl: _c(0x4a3b12), verseNum: _c(0x8f8f8f)),
};

class Settings {
  const Settings(this.j);
  final Map<String, dynamic> j;

  static const defaults = <String, dynamic>{
    'theme': 'light',
    'fontSize': 19.0,
    'lineHeight': 1.45,
    'verseSpacing': 0.55,
    'showVerseNumbers': true,
    'showStrongs': false,
    'showHeadings': true,
    'chapterTitleSize': 2.1,
    'verseNumSize': 0.6,
    'headingSize': 0.8,
    'syncScroll': true,
    'splitLayout': 'auto',
    'splitRatio': 0.5,
    'primaryModule': 'rst-plus',
    // Оформление и меню (функция «Оболочка», lib/features/shell) — ключи и значения как в веб-версии
    'fontFamily': 'system',
    'fontWeight': 400,
    'textWidth': 44.0, // em, на широком экране
    'textAlign': 'left', // left | justify
    'strongSize': 0.5, // em
    'strongPos': 'sup', // sup | inline | sub
    'verseNumPos': 'sup', // sup | inline
    'uiFontSize': 15.0, // px — меню, окна, кнопки
    'barHeight': 54.0, // px — верхняя панель
    'animations': true,
    'focusMode': false,
    'bookMode': false,
    'continuousVerses': false,
    'showXrefButtons': true,
    'showIllustrations': true,
    'colorOverrides': <String, dynamic>{}, // свои цвета поверх темы: { accent: '#…', bar: '#…', strong: '#…' }
    'commentaryFontSize': 19.0,
    'ttsFallback': false,
    'menu': <String, dynamic>{'help': true, 'lastBookmark': true, 'sermons': true, 'plans': true, 'listen': true, 'maps': true, 'focus': false, 'book': false, 'split': true},
  };

  T get<T>(String k) => (j[k] ?? defaults[k]) as T;
  double d(String k) => ((j[k] ?? defaults[k]) as num).toDouble();
  /// Тема со своими цветами поверх (настройка colorOverrides) — для читалки, окон и MaterialApp
  Palette get palette => paletteWith(basePalette, (j['colorOverrides'] as Map?)?.cast<String, dynamic>() ?? const {});
  Palette get basePalette => themes[get<String>('theme')] ?? themes['light']!;
  Settings copyWith(Map<String, dynamic> patch) => Settings({...j, ...patch});
}

late SharedPreferences prefs;

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final raw = prefs.getString('settings');
    return Settings(raw == null ? {} : (jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  void set(Map<String, dynamic> patch) {
    state = state.copyWith(patch);
    prefs.setString('settings', jsonEncode(state.j));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

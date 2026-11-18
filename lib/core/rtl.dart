// Письмо справа налево: иврит, арабский, персидский, урду, идиш и др. Язык модуля — по коду (в каталоге бывают
// двухбуквенные и трёхбуквенные коды ISO 639), текст — по первому «сильному» знаку (стих может быть на любом языке).
import 'package:flutter/painting.dart' show TextDirection;

/// Языки, которые читаются справа налево (коды ISO 639-1 и 639-3)
const rtlLanguages = <String>{
  'he', 'heb', 'hbo', 'iw', 'yi', 'ydd', 'ar', 'arb', 'arz', 'apc', 'ary', 'acm', 'afb', 'ajp', 'apd', 'arq', 'ars', 'aeb', 'acw',
  'fa', 'pes', 'prs', 'glk', 'ur', 'urd', 'ps', 'pbt', 'pst', 'sd', 'snd', 'ug', 'uig', 'ckb', 'ku-arab', 'dv', 'div', 'syr',
  'syc', 'aii', 'arc', 'nqo', 'bal', 'bgn', 'lrc', 'mzn', 'pnb', 'skr', 'ks', 'kas', 'ota', 'sam',
};

/// Читается ли язык справа налево
bool isRtlLang(String? code) {
  if (code == null) return false;
  final c = code.toLowerCase();
  return rtlLanguages.contains(c) || rtlLanguages.contains(c.split(RegExp('[-_]')).first);
}

/// Иврит (для шрифта «Noto Serif Hebrew»)
bool isHebrewLang(String? code) => const {'he', 'heb', 'hbo', 'iw'}.contains((code ?? '').toLowerCase().split('-').first);

final _rtlChar = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿\u{10800}-\u{10FFF}\u{1E800}-\u{1EFFF}]', unicode: true);
final _ltrChar = RegExp(r'[A-Za-zÀ-ɏͰ-ϿЀ-ԯऀ-῿぀-鿿가-힯]', unicode: true);

/// Направление текста по первому знаку письма: еврейские, арабские и другие буквы справа налево — rtl, остальное — ltr
TextDirection textDirOf(String s) {
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (_rtlChar.hasMatch(c)) return TextDirection.rtl;
    if (_ltrChar.hasMatch(c)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

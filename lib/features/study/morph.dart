// Расшифровка морфологических кодов на русском (порт src/core/morph.js веб-версии):
//  • коды Стронга TVM для иврита (RST+, например TH8804) — по сетке FHL (ctb.fhl.net/heb.html);
//  • коды Робинсона для греческого (модуль byz-rp2018, например V-PAI-1S) и коды OSHB для иврита и арамейского
//    (модуль oshb, например HC/Vqw3ms) — по таблицам morph_data.dart.
// Для неизвестных кодов показываем сам код без догадок. Термины — по-русски, при показе переводятся t(термин).
import 'dart:convert';

import '../../core/i18n.dart';
import 'morph_data.dart';

// Фразы для сборщика переводов (в веб-версии — N_()): все они уже есть в словарях assets/i18n
const _forms = ['перфект', 'имперфект', 'повелительное наклонение', 'инфинитив', 'действительное причастие', 'страдательное причастие', 'причастие'];
const _grid = <String, List<int?>>{
  'Кал (Qal)': [8804, 8799, 8798, 8800, 8802, 8803, 8801],
  'Пиэль (Piel)': [8765, 8762, 8761, 8763, null, null, 8764],
  'Пуаль (Pual)': [8795, 8792, null, null, null, null, 8794],
  'Нифаль (Niphal)': [8738, 8735, 8734, 8736, null, null, 8737],
  'Хифиль (Hiphil)': [8689, 8686, 8685, 8687, null, null, 8688],
  'Хофаль (Hophal)': [8717, 8714, null, 8715, null, null, 8716],
  'Хитпаэль (Hithpael)': [8694, 8691, 8690, 8692, null, null, 8693],
  'Полель (Polel)': [8790, 8787, null, 8788, null, null, 8789],
  'Пеэль/Пеиль (Peel/Peil)': [null, null, null, 8756, null, null, null],
  'Поэль (Poel)': [null, 8779, null, 8780, null, null, 8781],
  'Поаль (Poal)': [8776, null, null, null, null, null, null],
  'Пилпель (Pilpel)': [8773, 8770, 8769, 8771, null, null, 8772],
  'Пилель (Pilel)': [8768, 8766, null, null, null, null, null],
  'Пулаль (Pulal)': [8797, null, null, null, null, null, null],
  'Хитпоэль (Hithpoel)': [null, 8704, 8703, null, null, null, 8706],
  'Хитполель (Hithpolel)': [8712, 8709, null, null, null, null, null],
  'Хитпалпель (Hithpalpel)': [null, 8698, null, null, null, null, null],
  'Шафель (Shaphel)': [8806, null, null, null, null, null, null],
};

Map<int, (String, String)>? _tvm;
Map<int, (String, String)> get _tvmMap {
  if (_tvm != null) return _tvm!;
  final m = <int, (String, String)>{};
  _grid.forEach((stem, codes) {
    for (var i = 0; i < codes.length; i++) {
      final c = codes[i];
      if (c != null) m[c] = (stem, _forms[i]);
    }
  });
  return _tvm = m;
}

Map<String, dynamic>? _data;
Map<String, dynamic> get _d => _data ??= jsonDecode(morphDataJson) as Map<String, dynamic>;
Map<String, dynamic>? _greekTvm;
Map<String, dynamic> get _gtvm => _greekTvm ??= jsonDecode(greekTvmJson) as Map<String, dynamic>;

typedef _Slot = (String name, String key, Map<String, dynamic>? value);

Map<String, dynamic> _slotTable(Map<String, dynamic> section, String name, [String? lang]) {
  final byLang = section['slotsByLanguage'] as Map?;
  if (byLang != null && byLang.containsKey(name)) return ((byLang[name] as Map)[lang] as Map?)?.cast<String, dynamic>() ?? const {};
  return ((section['slots'] as Map)[name] as Map?)?.cast<String, dynamic>() ?? const {};
}

List<_Slot>? _matchForm(Map<String, dynamic> section, Map<String, dynamic> form, String body, [String? lang]) {
  final ph = section['placeholder'] as String?;
  var pos = 0;
  final out = <_Slot>[];
  for (final name in (form['slots'] as List).cast<String>()) {
    if (pos == body.length) {
      if (section['allowShort'] == true) break;
      return null;
    }
    if (name == '-') {
      if (body[pos] != '-') return null;
      pos++;
      continue;
    }
    if (ph != null && body[pos] == ph) {
      out.add((name, ph, null));
      pos++;
      continue;
    }
    final table = _slotTable(section, name, lang);
    String? key;
    for (var n = (body.length - pos).clamp(0, 4); n > 0; n--) {
      if (table.containsKey(body.substring(pos, pos + n))) {
        key = body.substring(pos, pos + n);
        break;
      }
    }
    if (key == null) return null;
    out.add((name, key, (table[key] as Map).cast<String, dynamic>()));
    pos += key.length;
  }
  if (pos != body.length) return null;
  final when = (form['when'] as Map?)?.cast<String, dynamic>() ?? const {};
  for (final e in when.entries) {
    final got = out.where((s) => s.$1 == e.key).firstOrNull?.$2;
    if (got != null && got != ph && !(e.value as List).contains(got)) return null;
  }
  return out;
}

class _Seg {
  _Seg(this.pos, {this.info, this.slots = const [], this.error = false});
  final String pos;
  final Map<String, dynamic>? info;
  final List<_Slot> slots;
  final bool error;
  List<Map<String, dynamic>> suffixes = const [];
}

_Seg _parseBody(Map<String, dynamic> section, String posCode, String body, [String? lang]) {
  final info = ((section['pos'] as Map)[posCode] as Map?)?.cast<String, dynamic>();
  if (info == null) return _Seg(posCode, error: true);
  for (final form in (info['forms'] as List).cast<Map>()) {
    final slots = _matchForm(section, form.cast<String, dynamic>(), body, lang);
    if (slots != null) return _Seg(posCode, info: info, slots: slots);
  }
  return _Seg(posCode, info: info, error: true);
}

List<_Seg> _parseGreek(String code) {
  final g = (_d['greek'] as Map).cast<String, dynamic>();
  final sep = g['separator'] as String;
  final suffixTable = (g['suffixes'] as Map).cast<String, dynamic>();
  final parts = code.split(sep);
  final suffixes = <String>[];
  while (parts.length > 1 && suffixTable.containsKey(parts.last)) {
    suffixes.insert(0, parts.removeLast());
  }
  final seg = _parseBody(g, parts[0], parts.skip(1).join(sep));
  seg.suffixes = [for (final s in suffixes) (suffixTable[s] as Map).cast<String, dynamic>()];
  return [seg];
}

List<_Seg>? _parseHebrew(String code) {
  final h = (_d['hebrew'] as Map).cast<String, dynamic>();
  final lang = code[0];
  if (!(h['languages'] as Map).containsKey(lang)) return null;
  return [
    for (final s in code.substring(1).split(h['segmentSeparator'] as String)) s.isEmpty ? _Seg('', error: true) : _parseBody(h, s[0], s.substring(1), lang),
  ];
}

String? _describeParsed(List<_Seg>? segs) {
  if (segs == null || segs.any((s) => s.error)) return null;
  return segs.map((s) {
    final parts = [s.info!['ru'], ...s.slots.where((x) => x.$3 != null).map((x) => x.$3!['ru']), ...s.suffixes.map((x) => x['ru'])];
    return parts.map((x) => t(x as String)).join(', ');
  }).join(' + ');
}

/// Расшифровка кода; null — не знаем (показываем сам код)
String? describeMorph(String code) {
  final tvm = RegExp(r'^T?([HG])(\d+)$').firstMatch(code);
  if (tvm != null) {
    final n = int.parse(tvm.group(2)!);
    if (tvm.group(1) == 'H') {
      final v = _tvmMap[n];
      return v == null ? null : '${t(v.$1)}, ${t(v.$2)}';
    }
    // В коде TVM нет лица, числа и падежа — разбираем только время, залог и наклонение
    final rob = _gtvm['$n'] as String?;
    if (rob == null) return null;
    final g = (_d['greek'] as Map).cast<String, dynamic>();
    final dash = rob.indexOf('-');
    final slots = _matchForm(g, {'slots': ['tense', 'voice', 'mood']}, dash < 0 ? '' : rob.substring(dash + 1));
    if (slots == null) return null;
    return [((g['pos'] as Map)['V'] as Map)['ru'], ...slots.where((x) => x.$3 != null).map((x) => x.$3!['ru'])].map((x) => t(x as String)).join(', ');
  }
  try {
    final g = (_d['greek'] as Map).cast<String, dynamic>();
    final hebrew = RegExp(r'^[HA][A-Za-z0-9/]*$').hasMatch(code) && !code.contains('-') && !(g['pos'] as Map).containsKey(code);
    return _describeParsed(hebrew ? _parseHebrew(code) : _parseGreek(code));
  } catch (_) {
    return null;
  }
}

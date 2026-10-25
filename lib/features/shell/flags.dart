// Круглые флажки языков — перенос src/components/Flag.jsx один в один: упрощённые рисунки 32×32 (середина флага),
// круг и тонкую обводку делает виджет Flag. Эмодзи-флаги не годятся: Windows их не рисует (видны буквы «RU»).
import 'dart:math' as math;

String _n(double v) => v.toStringAsFixed(2);

// Пятиконечная звезда: вершины для polygon
String _star(double cx, double cy, double r, [double rot = 0]) {
  final pts = <String>[];
  for (var i = 0; i < 10; i++) {
    final a = (rot - 90 + i * 36) * math.pi / 180;
    final rr = i.isOdd ? r * 0.382 : r;
    pts.add('${_n(cx + rr * math.cos(a))},${_n(cy + rr * math.sin(a))}');
  }
  return pts.join(' ');
}

// Полосы: горизонтальные (h) или вертикальные (v)
String _stripes(String dir, List<String> colors, [List<double>? parts]) {
  final p = parts ?? [for (final _ in colors) 1.0];
  final sum = p.fold<double>(0, (a, b) => a + b);
  var at = 0.0;
  final out = StringBuffer();
  for (var i = 0; i < colors.length; i++) {
    final size = 32 * p[i] / sum;
    out.write(dir == 'h' ? '<rect x="0" y="$at" width="32" height="${size + 0.1}" fill="${colors[i]}"/>' : '<rect x="$at" y="0" width="${size + 0.1}" height="32" fill="${colors[i]}"/>');
    at += size;
  }
  return out.toString();
}

// Триграммы флага Кореи: 1 — сплошная черта, 0 — разорванная
String _trigram(List<int> bits, double x, double y, double rot) {
  final b = StringBuffer('<g transform="translate($x $y) rotate($rot)" fill="#000">');
  for (var i = 0; i < bits.length; i++) {
    final yy = -2.6 + i * 1.9;
    b.write(bits[i] == 1 ? '<rect x="-3.2" y="$yy" width="6.4" height="1.2"/>' : '<rect x="-3.2" y="$yy" width="2.9" height="1.2"/><rect x="0.3" y="$yy" width="2.9" height="1.2"/>');
  }
  return (b..write('</g>')).toString();
}

String _indiaSpokes() {
  final b = StringBuffer();
  for (var i = 0; i < 12; i++) {
    final a = i * math.pi / 12;
    b.write('<path d="M${16 - 4 * math.cos(a)} ${16 - 4 * math.sin(a)}L${16 + 4 * math.cos(a)} ${16 + 4 * math.sin(a)}" stroke="#000080" stroke-width="0.35"/>');
  }
  return b.toString();
}

final Map<String, String Function()> _flags = {
  'ru': () => _stripes('h', ['#fff', '#0039a6', '#d52b1e']),
  'ua': () => _stripes('h', ['#0057b7', '#ffd700']),
  'ro': () => _stripes('v', ['#002b7f', '#fcd116', '#ce1126']),
  'gb': () => '<rect width="32" height="32" fill="#012169"/>'
      '<path d="M0 0L32 32M32 0L0 32" stroke="#fff" stroke-width="6"/>'
      '<path d="M0 0L32 32M32 0L0 32" stroke="#c8102e" stroke-width="2"/>'
      '<path d="M16 0V32M0 16H32" stroke="#fff" stroke-width="10"/>'
      '<path d="M16 0V32M0 16H32" stroke="#c8102e" stroke-width="6"/>',
  'es': () => _stripes('h', ['#aa151b', '#f1bf00', '#aa151b'], [1, 2, 1]),
  'br': () => '<rect width="32" height="32" fill="#009b3a"/>'
      '<polygon points="1,16 16,4.5 31,16 16,27.5" fill="#fedf00"/>'
      '<circle cx="16" cy="16" r="7" fill="#002776"/>'
      '<path d="M9.3 14.4q7.2-1.9 13.5 3.6" stroke="#fff" stroke-width="1.3" fill="none"/>',
  'fr': () => _stripes('v', ['#002654', '#fff', '#ce1126']),
  'de': () => _stripes('h', ['#000', '#dd0000', '#ffce00']),
  'it': () => _stripes('v', ['#009246', '#fff', '#ce2b37']),
  'pl': () => _stripes('h', ['#fff', '#dc143c']),
  'by': () {
    final b = StringBuffer(_stripes('h', ['#c8313e', '#4aa657'], [2, 1]))..write('<rect width="5" height="32" fill="#fff"/>');
    for (final y in [2, 7.3, 12.6, 17.9, 23.2, 28.5]) {
      b.write('<path d="M2.5 ${y - 2}L4.3 ${y}L2.5 ${y + 2}L0.7 ${y}Z" fill="#c8313e"/>');
    }
    return b.toString();
  },
  'bg': () => _stripes('h', ['#fff', '#00966e', '#d62612']),
  'rs': () => '${_stripes('h', ['#c6363c', '#0c4076', '#fff'])}'
      '<path d="M7 9.5h7v6.5q0 4-3.5 5.5Q7 20 7 16Z" fill="#c6363c" stroke="#fff" stroke-width="0.8"/>'
          '<path d="M10.5 10.5v10M7.5 14.5h6" stroke="#fff" stroke-width="1.1"/>',
  'cz': () => '${_stripes('h', ['#fff', '#d7141a'])}<polygon points="-8,0 16,16 -8,32" fill="#11457e"/>',
  'ge': () {
    final b = StringBuffer('<rect width="32" height="32" fill="#fff"/><path d="M16 0V32M0 16H32" stroke="#ff0000" stroke-width="5"/>');
    for (final (x, y) in [(7.5, 7.5), (24.5, 7.5), (7.5, 24.5), (24.5, 24.5)]) {
      b.write('<path d="M$x ${y - 3}V${y + 3}M${x - 3} ${y}H${x + 3}" stroke="#ff0000" stroke-width="1.7"/>');
    }
    return b.toString();
  },
  'am': () => _stripes('h', ['#d90012', '#0033a0', '#f2a800']),
  'kr': () => '<rect width="32" height="32" fill="#fff"/>'
      '<g transform="rotate(33.7 16 16)"><circle cx="16" cy="16" r="7.5" fill="#0047a0"/>'
      '<path d="M8.5 16a7.5 7.5 0 0 1 15 0a3.75 3.75 0 0 1-7.5 0a3.75 3.75 0 0 0-7.5 0Z" fill="#cd2e3a"/></g>'
      '${_trigram([1, 1, 1], 6.6, 7.4, -56.3)}${_trigram([0, 1, 0], 25.4, 7.4, 56.3)}'
      '${_trigram([1, 0, 1], 6.6, 24.6, 56.3)}${_trigram([0, 0, 0], 25.4, 24.6, -56.3)}',
  'cn': () => '<rect width="32" height="32" fill="#ee1c25"/>'
      '<polygon points="${_star(9, 10, 5)}" fill="#ffde00"/><polygon points="${_star(16, 4.5, 1.6, 23)}" fill="#ffde00"/>'
      '<polygon points="${_star(19, 7.8, 1.6, 46)}" fill="#ffde00"/><polygon points="${_star(19, 12, 1.6, 70)}" fill="#ffde00"/>'
      '<polygon points="${_star(16, 15.2, 1.6, 21)}" fill="#ffde00"/>',
  'jp': () => '<rect width="32" height="32" fill="#fff"/><circle cx="16" cy="16" r="9.6" fill="#bc002d"/>',
  'id': () => _stripes('h', ['#ce1126', '#fff']),
  'in': () => '${_stripes('h', ['#ff9933', '#fff', '#138808'])}'
      '<circle cx="16" cy="16" r="4.2" fill="none" stroke="#000080" stroke-width="0.9"/><circle cx="16" cy="16" r="1" fill="#000080"/>${_indiaSpokes()}',
  'tz': () => '<rect width="32" height="32" fill="#1eb53a"/><polygon points="32,0 32,32 0,32" fill="#00a3dd"/>'
      '<path d="M-2 34L34 -2" stroke="#fcd116" stroke-width="12"/><path d="M-2 34L34 -2" stroke="#000" stroke-width="8"/>',
};

/// SVG флага по коду страны (как в Lang.flag) или null, если такого рисунка нет
String? flagSvg(String code) {
  final draw = _flags[code];
  return draw == null ? null : '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">${draw()}</svg>';
}

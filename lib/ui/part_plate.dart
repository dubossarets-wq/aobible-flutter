// Цельная скруглённая плашка выбора части стиха (partShape.js веб-версии): в читалке и в блоке проповеди.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Прямоугольники строк по боксам выделения (несколько кусков одной строки — в один), сверху вниз
List<Rect> lineRects(List<TextBox> boxes) {
  final lines = <Rect>[];
  for (final b in boxes) {
    final r = b.toRect();
    if (r.width < 1 || r.height < 1) continue;
    final i = lines.indexWhere((l) => ((l.top + l.bottom) / 2 - (r.top + r.bottom) / 2).abs() < r.height / 2);
    if (i >= 0) {
      lines[i] = lines[i].expandToInclude(r);
    } else {
      lines.add(r);
    }
  }
  lines.sort((x, y) => x.top.compareTo(y.top));
  return lines;
}

// Цельная плашка: один контур по прямоугольникам строк. Строки стыкуются посередине промежутка (без зазоров и
// наложений), потом каждая вершина контура скругляется дугой радиуса r: выпуклые — наружу, вогнутые («ступеньки»
// между строками разной длины) — внутрь. Закрашивается один раз, поэтому двойных тонов нет.
Path partPlatePath(List<Rect> src, double r, double pad) {
  final ls = [
    for (final l in src) [l.left - pad, l.top, l.right + pad, l.bottom]
  ];
  for (var i = 1; i < ls.length; i++) {
    final y = (ls[i - 1][3] + ls[i][1]) / 2;
    ls[i - 1][3] = y;
    ls[i][1] = y;
  }
  ls.first[1] -= pad;
  ls.last[3] += pad;
  // обход по часовой стрелке: вправо вниз, затем влево вверх
  final pts = <Offset>[];
  for (final l in ls) {
    pts.add(Offset(l[2], l[1]));
    pts.add(Offset(l[2], l[3]));
  }
  for (final l in ls.reversed) {
    pts.add(Offset(l[0], l[3]));
    pts.add(Offset(l[0], l[1]));
  }
  // убрать совпадающие и лежащие на одной прямой вершины
  var v = <Offset>[];
  for (final q in pts) {
    if (v.isEmpty || (v.last - q).distance > 0.01) v.add(q);
  }
  if (v.length > 1 && (v.first - v.last).distance < 0.01) v.removeLast();
  bool again = true;
  while (again && v.length > 3) {
    again = false;
    for (var i = 0; i < v.length; i++) {
      final p0 = v[(i + v.length - 1) % v.length], p1 = v[i], p2 = v[(i + 1) % v.length];
      final cr = (p1.dx - p0.dx) * (p2.dy - p1.dy) - (p1.dy - p0.dy) * (p2.dx - p1.dx);
      if (cr.abs() < 0.01) {
        v.removeAt(i);
        again = true;
        break;
      }
    }
  }
  final path = Path();
  final n = v.length;
  for (var i = 0; i < n; i++) {
    final p0 = v[(i + n - 1) % n], p1 = v[i], p2 = v[(i + 1) % n];
    final d1 = (p0 - p1).distance, d2 = (p2 - p1).distance;
    final rad = [r, d1 / 2, d2 / 2].reduce((x, y) => x < y ? x : y);
    final a1 = p1 + (p0 - p1) / d1 * rad, a2 = p1 + (p2 - p1) / d2 * rad;
    final cross = (p1.dx - p0.dx) * (p2.dy - p1.dy) - (p1.dy - p0.dy) * (p2.dx - p1.dx);
    if (i == 0) {
      path.moveTo(a1.dx, a1.dy);
    } else {
      path.lineTo(a1.dx, a1.dy);
    }
    path.arcToPoint(a2, radius: Radius.circular(rad), clockwise: cross > 0);
  }
  path.close();
  return path;
}

/// Рисует плашку под абзацем [textKey] (Text/RichText) для символов [a]..[b]; ставится в Stack под сам текст
class PartPlate extends CustomPainter {
  PartPlate(this.textKey, this.a, this.b, this.color);
  final GlobalKey textKey;
  final int a, b;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    RenderParagraph? para;
    void find(RenderObject o) {
      if (para != null) return;
      if (o is RenderParagraph) {
        para = o;
        return;
      }
      o.visitChildren(find);
    }

    final ro = textKey.currentContext?.findRenderObject();
    if (ro != null) find(ro);
    final p = para;
    if (p == null || !p.hasSize || b <= a) return;
    final lines = lineRects(p.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b)));
    if (lines.isEmpty) return;
    canvas.drawPath(partPlatePath(lines, 6, 2), Paint()..color = color); // r 6, inflate 2, как в читалке
  }

  @override
  bool shouldRepaint(PartPlate old) => true;
}

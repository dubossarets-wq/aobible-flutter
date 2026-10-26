// Геометрия плашки выбора части стиха: одна гладкая фигура без зазоров и зубцов на стыках строк.
import 'dart:ui';

import 'package:aobible/ui/part_plate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Path plate(List<Rect> l) => partPlatePath(l, 6, 0);
  bool at(Path p, double x, double y) => p.contains(Offset(x, y));

  test('одна строка: середина закрашена, углы скруглены, за краем пусто', () {
    final p = plate([const Rect.fromLTRB(10, 0, 100, 20)]);
    expect(at(p, 50, 10), true);
    expect(at(p, 10.5, 0.5), false); // скруглённый угол
    expect(at(p, 9, 10), false);
    expect(at(p, 101, 10), false);
  });

  test('верхняя строка длиннее нижней: ступенька со вогнутым скруглением, без выступа справа сверху', () {
    final p = plate([const Rect.fromLTRB(10, 0, 200, 20), const Rect.fromLTRB(10, 20, 100, 40)]);
    expect(at(p, 50, 20), true); // стык строк без зазора
    expect(at(p, 150, 19), true);
    expect(at(p, 150, 21), false); // под выступающей частью верхней строки
    expect(at(p, 100.5, 20.5), true); // вогнутое скругление добавляет материал в углу ступеньки
    expect(at(p, 110, 30), false);
    expect(at(p, 199.5, 19.5), false); // правый нижний угол верхней строки скруглён
    expect(at(p, 195, 15), true);
  });

  test('верхняя строка короче нижней и равная', () {
    final shorter = plate([const Rect.fromLTRB(10, 0, 100, 20), const Rect.fromLTRB(10, 20, 200, 40)]);
    expect(at(shorter, 50, 20), true);
    expect(at(shorter, 150, 19), false);
    expect(at(shorter, 150, 21), true);
    expect(at(shorter, 100.5, 19.5), true); // вогнутое скругление сверху нижней строки
    final equal = plate([const Rect.fromLTRB(10, 0, 100, 20), const Rect.fromLTRB(10, 20, 100, 40)]);
    expect(at(equal, 99, 20), true);
    expect(at(equal, 10, 20), true);
    expect(at(equal, 101, 20), false);
  });

  test('три строки и выделение с середины строки', () {
    final p = plate([const Rect.fromLTRB(120, 0, 200, 20), const Rect.fromLTRB(10, 20, 200, 40), const Rect.fromLTRB(10, 40, 90, 60)]);
    expect(at(p, 150, 10), true);
    expect(at(p, 50, 10), false); // слева от начала выделения
    expect(at(p, 50, 30), true);
    expect(at(p, 150, 50), false);
    expect(at(p, 50, 50), true);
    expect(at(p, 150, 20), true);
    expect(at(p, 50, 40), true);
    expect(at(p, 119.5, 19.5), true); // вогнутое скругление слева от начала верхней строки
    expect(at(p, 100, 5), false);
  });
}

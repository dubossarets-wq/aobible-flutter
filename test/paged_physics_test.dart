// Режим «Страницы»: страница переворачивается лёгким сдвигом пальца (пятая часть страницы), а не половиной.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aobible/ui/paged_chapter.dart';

void main() {
  testWidgets('сдвиг на четверть страницы листает, на десятую — нет', (tester) async {
    var page = 0;
    final ctl = PageController();
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 600,
        child: PageView.builder(
          controller: ctl,
          pageSnapping: false,
          physics: EasyPagePhysics(start: () => page, parent: const ClampingScrollPhysics()),
          itemCount: 5,
          onPageChanged: (k) => page = k,
          itemBuilder: (_, k) => Center(child: Text('стр $k')),
        ),
      ),
    ));
    final w = tester.getSize(find.byType(PageView)).width;
    // 10 % страницы (палец влево = следующая) — остаёмся
    await tester.drag(find.byType(PageView), Offset(-w * 0.10, 0));
    await tester.pumpAndSettle();
    expect(page, 0);
    // 25 % — следующая
    await tester.drag(find.byType(PageView), Offset(-w * 0.25, 0));
    await tester.pumpAndSettle();
    expect(page, 1);
    // обратно 25 % — предыдущая
    await tester.drag(find.byType(PageView), Offset(w * 0.25, 0));
    await tester.pumpAndSettle();
    expect(page, 0);
  });
}

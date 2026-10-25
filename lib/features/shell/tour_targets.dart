// Цели подсветки в инструкции (tours.js: target()). В веб-версии место ищется по CSS-селектору; здесь — по id:
//   1) tourResolvers[id] — функция, которая сама вернёт прямоугольник на экране (если ключом не обойтись);
//   2) tourKey(id) — GlobalKey, который главный экран / читалка вешает на нужный виджет;
//   3) запасной поиск по дереву виджетов (подсказки значков шапки, подписи нижних вкладок, окна и панели других функций).
// Нужные ключи и функции перечислены в отчёте (какие id куда повесить). Без них подсветки нет, но урок идёт: затемнён весь экран.
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../ui/kit.dart' show AobSheet;
import '../study/sheet.dart' show SheetScaffold;

/// Ключи целей: tourKey('tb-ref') вешают на виджет через `key:`; на экране он должен быть один (первая панель)
final tourKeys = <String, GlobalKey>{};
GlobalKey tourKey(String id) => tourKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tour:$id'));

/// Функции-прямоугольники: читалка может зарегистрировать, например, 'verse' — первый видимый стих первой панели
final tourResolvers = <String, Rect? Function()>{};

Rect? rectOfElement(Element? e) {
  if (e == null || !e.mounted) return null;
  final ro = e.renderObject;
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
  try {
    return ro.localToGlobal(Offset.zero) & ro.size;
  } catch (_) {
    return null;
  }
}

/// Обойти дерево виджетов; test получает элемент, возвращает true — взять. first — первый найденный, иначе последний (верхний)
Element? findElement(bool Function(Element e) test, {bool first = true}) {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;
  Element? hit;
  var done = false;
  void visit(Element e) {
    if (done) return;
    if (test(e)) {
      hit = e;
      if (first) {
        done = true;
        return;
      }
    }
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
  return hit;
}

// Найденный элемент помним 0,4 с: поиск по дереву — не на каждый кадр
final _cache = <String, (Element, DateTime)>{};

Element? _cached(String id, bool Function(Element e) test, {bool first = true}) {
  final c = _cache[id];
  if (c != null && c.$1.mounted && DateTime.now().difference(c.$2).inMilliseconds < 400) return c.$1;
  final e = findElement(test, first: first);
  if (e == null) {
    _cache.remove(id);
  } else {
    _cache[id] = (e, DateTime.now());
  }
  return e;
}

/// Подсказка (Tooltip) по образцу: «{ref}. Выбрать место» → любое значение вместо {ref}
RegExp _tipRe(String template) {
  final parts = template.split(RegExp(r'\{\w+\}')).map(RegExp.escape);
  return RegExp('^${parts.join('.*')}\$', dotAll: true);
}

/// last — взять последний найденный (верхний слой / вторая панель), а не первый
Rect? byTooltip(String template, {bool prefix = false, bool last = false}) {
  final re = prefix ? RegExp('^${RegExp.escape(template)}') : _tipRe(template);
  final e = _cached('tip:$template$prefix$last', (e) => e.widget is Tooltip && re.hasMatch(((e.widget as Tooltip).message ?? '')), first: !last);
  return rectOfElement(e);
}

/// Есть ли у элемента предок, для которого test верен
bool _inside(Element e, bool Function(Widget w) test) {
  var found = false;
  e.visitAncestorElements((a) {
    if (test(a.widget)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Поле ввода вместе с рамкой вокруг него (.ref-form, input): поднимаемся от TextField, пока предок не выше 64 px
Rect? _fieldBox(Element? tf) {
  final first = rectOfElement(tf);
  if (tf == null || first == null) return null;
  var best = first;
  tf.visitAncestorElements((a) {
    final ar = rectOfElement(a);
    if (ar == null || ar.height > 64 || ar.height < best.height - 0.5) return false;
    if (ar.contains(best.topLeft) && ar.contains(best.bottomRight)) best = ar;
    return true;
  });
  return best;
}

/// Пересечение с открытым окном: длинная сетка не должна выходить за экран
Rect? _clipToSheet(Rect? r) {
  final s = sheetRect();
  if (r == null || s == null) return r;
  final c = r.intersect(s);
  return c.width <= 0 || c.height <= 0 ? null : c;
}

/// Подпись внизу экрана (вкладки нижней панели): Text с точным текстом в нижней четверти
Rect? byBottomText(String text) {
  final h = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.height / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  final e = _cached('btm:$text', (e) {
    final w = e.widget;
    if (w is! Text || (w.data ?? w.textSpan?.toPlainText()) != text) return false;
    final r = rectOfElement(e);
    return r != null && r.top > h * 0.72;
  });
  final r = rectOfElement(e);
  return r == null ? null : Rect.fromLTRB(r.left - 16, r.top - 30, r.right + 16, r.bottom + 12);
}

/// Виджет по имени класса (для окон и панелей других функций, у которых нет ключа)
Rect? byType(String name, {bool first = true}) {
  final e = _cached('type:$name$first', (e) => e.widget.runtimeType.toString() == name, first: first);
  return rectOfElement(e);
}

bool hasType(String name) => findElement((e) => e.widget.runtimeType.toString() == name) != null;

/// Открыто ли окно (AobSheet) и его прямоугольник; верхнее окно — последнее в порядке обхода
// Окна функций — AobSheet (kit.dart), окна «изучения» (словарь, параллельные места, подстрочник…) — SheetScaffold
bool _isSheet(Widget w) => w is AobSheet || w is SheetScaffold;
bool sheetOpen() => findElement((e) => _isSheet(e.widget)) != null;
Rect? sheetRect() => rectOfElement(_cached('sheet', (e) => _isSheet(e.widget), first: false));

/// Есть ли на экране текст (по полному совпадению)
bool hasText(String text) => findElement((e) => e.widget is Text && ((e.widget as Text).data ?? '') == text) != null;

Rect? _byKey(String id) {
  final ctx = tourKeys[id]?.currentContext;
  return rectOfElement(ctx is Element ? ctx : null);
}

/// Прямоугольник цели на экране или null (цели нет)
Rect? targetRect(String id) {
  final fn = tourResolvers[id];
  if (fn != null) {
    final r = fn();
    if (r != null) return r;
  }
  final k = _byKey(id);
  if (k != null) return k;
  switch (id) {
    case 'tb-ref':
      return byTooltip(t('{ref}. Выбрать место'));
    case 'tb-module':
      return byTooltip(t('Перевод: {name}. Сменить перевод'));
    case 'tb-hist':
      return byTooltip(t('Назад по истории'));
    case 'tb-split':
      return byTooltip(t('Читать параллельно')) ?? byTooltip(t('Закрыть вторую панель'));
    case 'tb-module-2':
      // .pane-slot.second .tb-module: кнопка перевода второй панели (она в дереве последняя), иначе первой
      return byTooltip(t('Перевод: {name}. Сменить перевод'), last: true);
    case 'nav-grid':
      // .sheet .num-grid / .book-cat: сетка книг, глав или стихов в окне «Перейти»
      return _clipToSheet(rectOfElement(_cached('nav-grid', (e) => e.widget is Wrap && _inside(e, (w) => w.runtimeType.toString() == 'NavigatorSheet'))));
    case 'ref-form':
      // .sheet .ref-form: строка «Книга или ссылка» со стрелкой
      return _fieldBox(_cached('ref-form', (e) => e.widget is TextField && _inside(e, (w) => w.runtimeType.toString() == 'NavigatorSheet')));
    case 'sheet-input':
      // .sheet input: поле ввода в верхнем окне (поиск)
      return _fieldBox(_cached('sheet-input', (e) => e.widget is TextField && _inside(e, _isSheet), first: false));
    case 'sheet-close':
      // .sheet [aria-label="Закрыть"] || .map-pane: крестик верхнего окна, а у карты — «Закрыть карту»
      return byTooltip(t('Закрыть'), last: true) ?? byTooltip(t('Закрыть карту'));
    case 'tb-split-close':
      // второй части нет — подсвечено открытое окно (как «($('.pane-slot.second') ? tb-split : $('.sheet'))»)
      return byTooltip(t('Закрыть вторую панель')) ?? sheetRect();
    case 'tb-search':
      return byTooltip(t('Поиск'));
    case 'tb-more':
      return byTooltip(t('Ещё'), prefix: true);
    case 'tab-search':
      return byBottomText(t('Поиск'));
    case 'tab-plans':
      return byBottomText(t('Планы'));
    case 'tab-saved':
      return byBottomText(t('Закладки'));
    case 'tab-more':
      return byBottomText(t('Ещё'));
    case 'selection-bar':
      return byType('_SelectionBar');
    case 'listen-fab':
      return byType('ListenFab');
    case 'audio-bar':
      final b = byType('AudioBar');
      return b == null || b.height <= 1 ? null : b; // пока не играет — виджет нулевого размера
    case 'word-pop':
      return byType('_Popover');
    case 'scroller':
      return byType('ReaderPane');
    case 'verse':
      // запасной вариант: верхняя часть читалки, где обычно первый стих
      final s = byType('ReaderPane');
      return s == null ? null : Rect.fromLTWH(s.left + 8, s.top + 70, s.width - 16, 84);
    case 'sheet':
      return sheetRect();
  }
  return null;
}

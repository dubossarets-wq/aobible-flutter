// Строка действий под выделенным стихом (.sel-inline в BibleReader.jsx → SelectionInline):
// круглая тёмная «Слушать» · «В проповедь» · «Часть стиха» (только для одного стиха) · «Подстрочник».
// Читалка пока не умеет ставить виджет под стих: нужна точка VerseDecor.below (виджет под текстом стиха, пока он
// выделен) — см. отчёт. Как только она появится, verseDecor возвращает buildSelectionInline(...) последнему выделенному стиху.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../ui/kit.dart';
import '../hub.dart';

/// onDone — снять выделение; onPart — начать выбор части стиха (если читалка это умеет, иначе кнопки нет)
Widget buildSelectionInline(BuildContext context, WidgetRef ref, {required int pane, required String moduleId, required List<VerseRef> refs, required VoidCallback onDone, VoidCallback? onPart}) {
  final pal = paletteOf(ref);
  final first = refs.first;
  final narrow = MediaQuery.sizeOf(context).width <= 430; // на узком экране значки в кнопках скрыты

  // .sel-inline .btn: фон panel, рамка line, скругление 9, отступы 10×6, шрифт 13,8 (0,86rem), значок 16
  Widget btn(IconData icon, String label, VoidCallback f) => Expanded(
        child: Material(
          color: pal.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius * 0.75), side: BorderSide(color: pal.line)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: f,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (!narrow) ...[Icon(icon, size: 16, color: pal.text), const SizedBox(width: 4)],
                Flexible(child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 13.8, fontWeight: FontWeight.w500, color: pal.text))),
              ]),
            ),
          ),
        ),
      );

  final gap = const SizedBox(width: 6);
  final items = <Widget>[
    if (Hub.listenFrom != null)
      Tooltip(
        message: t('Слушать'),
        child: Semantics(
          label: t('Слушать с этого стиха'),
          child: Material(
            color: pal.accent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Hub.listenFrom!(context, ref, pane, first);
                onDone();
              },
              child: SizedBox(width: 44, height: 44, child: Icon(LucideIcons.headphones, size: 20, color: pal.onAccent)),
            ),
          ),
        ),
      ),
    if (Hub.addToSermon != null)
      btn(LucideIcons.scrollText, t('В проповедь'), () {
        Hub.addToSermon!(context, ref, refs, moduleId);
        onDone();
      }),
    if (refs.length == 1 && onPart != null) btn(LucideIcons.textSelect, t('Часть стиха'), onPart),
    if (Hub.openInterlinear != null)
      btn(LucideIcons.wholeWord, t('Подстрочник'), () {
        Hub.openInterlinear!(context, ref, first, moduleId);
        onDone();
      }),
  ];
  return Padding(
    // margin: .2em 0 1em
    padding: const EdgeInsets.only(top: 4, bottom: 15),
    child: Row(children: [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) gap, items[i]],
    ]),
  );
}

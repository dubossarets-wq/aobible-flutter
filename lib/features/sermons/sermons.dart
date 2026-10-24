// Функция «Проповеди»: список и редактор (пункт «Проповеди» в «Ещё»), «Кафедра», добавление выделенных стихов (Hub.addToSermon).
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../hub.dart';
import '../plans/ui_kit.dart';
import 'sermon_add.dart';
import 'sermons_sheet.dart';

void register() {
  Hub.addToSermon = (context, ref, refs, moduleId) => showPage(context, (_) => SermonAddSheet(pane: 0, refs: refs, moduleId: moduleId), height: 0.7);
  Hub.moreItems.add(MoreItem(
    id: 'sermons',
    icon: Icons.article_outlined,
    label: t('Проповеди'),
    order: 20,
    run: (context, ref, pane) => showPage(context, (_) => SermonsSheet(pane: pane)),
  ));
}

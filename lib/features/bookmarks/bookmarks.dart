// Закладки, заметки, любимые, выделения, подборки; панель действий над выделенными стихами;
// «Мои данные»; перенос данных из старого приложения. Подключение к читалке — через Hub.
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../hub.dart';
import 'decor.dart';
import 'legacy.dart';
import 'manager.dart';
import 'mydata_page.dart';
import 'selection_bar.dart';

void register() {
  Hub.selectionBar = buildSelectionBar;
  Hub.verseDecorators.add(verseDecor);
  Hub.openBookmarks = openBookmarksPage;
  Hub.afterStart.add(migrateFromOldApp);
  Hub.moreItems.add(MoreItem(id: 'mydata', icon: Icons.save_alt, label: t('Мои данные'), order: 80, run: openMyData));
}

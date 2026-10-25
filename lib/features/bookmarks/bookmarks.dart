// Закладки, заметки, любимые, выделения, подборки; панель действий над выделенными стихами;
// «Мои данные»; перенос данных из старого приложения. Подключение к читалке — через Hub.

import '../../core/i18n.dart';
import '../../ui/kit.dart' show LucideIcons;
import '../hub.dart';
import 'decor.dart';
import 'gestures.dart';
import 'legacy.dart';
import 'manager.dart';
import 'mydata_page.dart';
import 'selection_bar.dart';

void register() {
  Hub.selectionBar = buildSelectionBar;
  Hub.verseDecorators.add(verseDecor);
  Hub.openBookmarks = openBookmarksPage;
  Hub.onVerseDoubleTap = onVerseDoubleTap;
  Hub.addFavoritePart = addFavoritePart;
  Hub.moreItems.addAll(moreItems());
  // register() вызывается заново при смене языка: задания запуска не дублируем. Копия — раньше переноса из старого приложения
  Hub.afterStart
    ..remove(bootBackup)
    ..remove(migrateFromOldApp)
    ..add(bootBackup)
    ..add(migrateFromOldApp);
  Hub.moreItems.add(MoreItem(id: 'mydata', icon: LucideIcons.hardDrive, label: t('Мои данные'), order: 80, run: openMyData));
}

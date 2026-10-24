// «Изучение»: выборка над словом и словарные статьи Стронга, подстрочник, параллельные места, комментарии,
// иллюстрации к стихам, сравнение переводов. Подключение к читалке — только через Hub (hub.dart).
import '../hub.dart';
import 'compare_sheet.dart';
import 'decorators.dart';
import 'interlinear_sheet.dart';
import 'study_data.dart';
import 'word_popover.dart';

Future<void> _prepare(dynamic ref) => StudyData.ensure();

/// Можно вызывать повторно (после смены языка): списки не дублируются
void register() {
  Hub.onWordTap = onWordTap;
  Hub.openInterlinear = openInterlinearSheet;
  Hub.compareTranslations = openCompare;
  Hub.verseDecorators
    ..remove(studyDecorator)
    ..add(studyDecorator);
  // Модули, установленные до этой версии, получают таблицы в фоне при запуске
  Hub.afterStart
    ..remove(_prepare)
    ..add(_prepare);
}

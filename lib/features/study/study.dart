// «Изучение»: выборка над словом и словарные статьи Стронга, подстрочник, параллельные места, комментарии,
// иллюстрации к стихам, сравнение переводов. Подключение к читалке — только через Hub (hub.dart).
import '../../core/panes.dart';
import '../hub.dart';
import 'compare_sheet.dart';
import 'concordance_sheet.dart';
import 'decorators.dart';
import 'dictionary_sheet.dart';
import 'commentary_sheet.dart';
import 'interlinear_sheet.dart';
import 'verse_guide.dart';
import 'xrefs_sheet.dart';
import 'study_data.dart';
import 'word_popover.dart';

Future<void> _prepare(dynamic ref) => StudyData.ensure();

/// Можно вызывать повторно (после смены языка): списки не дублируются
void register() {
  Hub.onWordTap = onWordTap;
  Hub.openInterlinear = openInterlinearSheet;
  Hub.compareTranslations = openCompare;
  // Окна панели выделения: у них номер панели и стих; перевод для параллельных мест берём у панели
  Hub.openCommentary = (context, ref, pane, at) => openCommentary(context, pane: pane, at: at);
  Hub.openXrefs = (context, ref, pane, at) => openXrefs(context, pane: pane, moduleId: _moduleOf(ref, pane), at: at);
  Hub.openVerseGuide = openVerseGuide;
  // «Статья словаря» в поиске: onArticle запоминает запрос, статья открывается здесь — на всю высоту, как в веб-версии
  Hub.strongSearchCard = (context, ref, pane, strongNum, filter, onOpen, onArticle) => StrongSearchCard(
        num: strongNum,
        filter: filter,
        onOpen: onOpen,
        onArticle: onArticle == null
            ? null
            : () {
                onArticle();
                openDictionary(context, DictRequest(text: strongNum, strongs: [strongNum], morph: const [], ref: ref.read(panesProvider)[pane].ref, pane: pane, autoOpen: true), full: true);
              },
      );
  Hub.verseDecorators
    ..remove(studyDecorator)
    ..add(studyDecorator);
  // Модули, установленные до этой версии, получают таблицы в фоне при запуске
  Hub.afterStart
    ..remove(_prepare)
    ..add(_prepare);
}

String _moduleOf(dynamic ref, int pane) {
  final panes = ref.read(panesProvider) as List<PaneState>;
  return panes[pane < panes.length ? pane : 0].moduleId;
}

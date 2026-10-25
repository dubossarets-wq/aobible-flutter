// Подключение функций: каждая — своя папка lib/features/<имя>/ со своей register().
// Новая функция — одна строка здесь; ядро о ней ничего не знает (см. hub.dart).
import 'audio/audio.dart' as audio;
import 'bookmarks/bookmarks.dart' as bookmarks;
import 'maps/maps.dart' as maps;
import 'plans/plans.dart' as plans;
import 'sermons/sermons.dart' as sermons;
import 'shell/shell.dart' as shell;
import 'study/study.dart' as study;

void registerFeatures() {
  audio.register();
  bookmarks.register();
  maps.register();
  plans.register();
  sermons.register();
  shell.register();
  study.register();
}

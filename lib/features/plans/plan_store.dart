// Активные планы — общее хранилище для окна планов, учёта прочитанного и напоминаний (prefs «plans»).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import 'net_cache.dart';
import 'plan_logic.dart';

class PlansNotifier extends Notifier<List<Plan>> {
  @override
  List<Plan> build() => loadPlans();

  void set(List<Plan> next) {
    state = next;
    savePlans(next);
  }

  void add(Plan p) => set([p, ...state]);
  void remove(String uid) => set([for (final p in state) if (p['uid'] != uid) p]);
  void replace(Plan np) => set([for (final p in state) p['uid'] == np['uid'] ? np : p]);

  bool markUnits(String uid, int day, List<String> keys) {
    final r = markUnitsIn(state, uid, day, keys);
    if (!identical(r.plans, state)) set(r.plans);
    return r.finished;
  }

  /// Глава дочитана в обычном чтении — засчитать в планы. Возвращает названия планов (засчитано / день завершён)
  ({List<String> credited, List<String> finished}) creditChapter(String book, int chapter) {
    final r = creditChapterIn(state, book, chapter);
    if (r.credited.isNotEmpty) set(r.plans);
    return (credited: r.credited, finished: r.finished);
  }
}

final plansProvider = NotifierProvider<PlansNotifier, List<Plan>>(PlansNotifier.new);

// --- Готовые планы: список и файлы с сайта (plans/index.json, plans/<файл>.json) -----------------------

class PlanMeta {
  PlanMeta(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'] as String;
  String get name => j['name'] as String? ?? id;
  String get file => j['file'] as String;
  int get days => (j['days'] as num?)?.toInt() ?? 0;
  String? get short => j['short'] as String?;
  String? get description => j['description'] as String?;
}

Future<List<PlanMeta>>? _index;

/// Список планов — один раз за сеанс
Future<List<PlanMeta>> fetchPlanIndex() => _index ??= () async {
      final j = await siteJson('plans/index.json');
      if (j == null) {
        _index = null; // не вышло — попробуем при следующем открытии
        throw Exception(t('Список планов недоступен'));
      }
      return [for (final p in (j['plans'] as List? ?? const [])) PlanMeta((p as Map).cast<String, dynamic>())];
    }();

Future<Map<String, dynamic>> fetchPlan(String file) async {
  final j = await siteJson('plans/$file');
  if (j == null) throw Exception(t('План не загрузился'));
  return j;
}

/// Свой план: что читать
class PlanScope {
  const PlanScope(this.id, this.label, this.books);
  final String id, label;
  final List<String> Function() books;
}

final planScopes = <PlanScope>[
  PlanScope('all', 'Вся Библия', () => [for (final b in Books.instance.all) if (b.testament != 'AP') b.id]),
  PlanScope('ot', 'Ветхий Завет', () => [for (final b in Books.instance.all) if (b.testament == 'OT') b.id]),
  PlanScope('nt', 'Новый Завет', () => [for (final b in Books.instance.all) if (b.testament == 'NT') b.id]),
  PlanScope('gospels', 'Евангелия', () => ['Matt', 'Mark', 'Luke', 'John']),
  PlanScope('ps', 'Псалтирь', () => ['Ps']),
];

/// Главы по книгам одного перевода — запоминаем: «Свой план → Параллельно» пересчитывает дни при каждом нажатии,
/// а запрос по всем книгам Заветов на главном потоке заметен. Содержимое модуля за сеанс не меняется
/// (при переустановке меняется версия каталога — она часть ключа).
final _chapterCache = <String, List<({String ref, int n})>>{};

List<({String ref, int n})> _bookChapters(InstalledModule mod, String book) {
  final key = '${mod.id}|${mod.meta['catalogVersion']}|$book';
  return _chapterCache[key] ??= [
    for (final r in ModuleStore.instance.db(mod.id).select('SELECT chapter, COUNT(*) AS n FROM verses WHERE book = ? GROUP BY chapter ORDER BY chapter', [book]))
      (ref: '$book.${r['chapter']}', n: r['n'] as int),
  ];
}

InstalledModule? _planModule() {
  final mods = ModuleStore.instance.bibles;
  return mods.where((m) => m.id == 'rst-plus').firstOrNull ?? mods.firstOrNull;
}

/// Главы выбранных книг поровну по дням (по числу стихов — чтобы дни были ровными)
List<List<String>> makeCustomPlan(List<String> bookIds, int days) => splitChapters(chapterList(bookIds), days);

/// Главы книг по порядку: [(ref: 'Isa.1', n: стихов)] — по основному переводу
List<({String ref, int n})> chapterList(List<String> bookIds) {
  final mod = _planModule();
  if (mod == null) return [];
  return [for (final id in bookIds) ..._bookChapters(mod, id)];
}

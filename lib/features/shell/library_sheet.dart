// Библиотека модулей (ModuleLibrary.jsx): установленные и каталог, поиск, фильтры по виду и языку (языки без модулей
// не показываем), скачать / обновить / удалить, основной перевод, вкладка «Импорт» (library_import.dart), свой каталог
// («Источник каталога»), включение и выключение небиблейских модулей (переключатель и свайп).
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoButtonSize;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../hub.dart';
import '../maps/maps_sheet.dart' show openMapsSheet;
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/ios_style.dart';
import '../../ui/kit.dart';
import 'colors.dart';
import 'intl_data.dart';
import 'library_import.dart';
import 'sheet.dart';

Future<void> openLibrary(BuildContext context, {String tab = 'installed'}) => showAppSheet(context, (_) => LibrarySheet(tab: tab, outer: context));

/// Виды модулей по порядку показа (MODULE_SECTIONS)
const moduleSections = <(String, String)>[
  ('bible', 'Переводы'), ('commentary', 'Комментарии'), ('dictionary', 'Словари'), ('maps', 'Карты'),
  ('illustrations', 'Иллюстрации'), ('audio', 'Аудиокниги'), ('crossrefs', 'Параллельные места'),
];
const moduleTypeNames = <String, String>{
  'bible': 'Перевод Библии', 'commentary': 'Комментарий', 'dictionary': 'Словарь', 'maps': 'Карты',
  'crossrefs': 'Параллельные места', 'audio': 'Аудиокнига', 'illustrations': 'Иллюстрации',
};
// Языки модулей: порядок показа — русский, затем живые языки по числу говорящих, в конце древние языки Писания
const _langNames = <String, String>{
  'ru': 'Русский', 'en': 'English', 'zh': 'Китайский', 'hi': 'Хинди', 'es': 'Испанский', 'ar': 'Арабский', 'fr': 'Французский',
  'pt': 'Португальский', 'id': 'Индонезийский', 'de': 'Немецкий', 'ja': 'Японский', 'tr': 'Турецкий', 'sw': 'Суахили',
  'vi': 'Вьетнамский', 'tl': 'Тагальский', 'ko': 'Корейский', 'fa': 'Персидский', 'it': 'Итальянский', 'pl': 'Польский',
  'uk': 'Українська', 'ro': 'Румынский', 'nl': 'Нидерландский', 'el': 'Новогреческий', 'sv': 'Шведский', 'cs': 'Чешский',
  'sr': 'Сербский', 'sq': 'Албанский', 'hy': 'Армянский', 'hr': 'Хорватский', 'da': 'Датский', 'nb': 'Норвежский',
  'be': 'Белорусский', 'eo': 'Эсперанто', 'he': 'Иврит', 'grc': 'Греческий', 'la': 'Латынь', 'cu': 'Церковнославянский', 'syr': 'Сирийский',
};
final _order = {for (final (i, k) in _langNames.keys.indexed) k: i};
int langRank(String code) => _order[code] ?? _order.length + (code.isEmpty ? 1 : 0);

/// Название языка: в русском интерфейсе — по-русски, в остальных — на самом языке (если он среди языков приложения)
String langName(String code) {
  if (code.isEmpty) return t('Другие');
  // не русский интерфейс — название на языке интерфейса, как Intl.DisplayNames в веб-версии
  if (currentLang != 'ru') {
    final s = langDisplayNames[currentLang]?[code];
    if (s != null) return s;
  }
  // русские названия — только в русском интерфейсе; иначе — на языке интерфейса по таблице сайта (или по-английски)
  return (currentLang == 'ru' ? _langNames[code] : null) ?? langNameFor(code, currentLang) ?? _langNames[code] ?? code.toUpperCase();
}

/// Ряд языков (LangChips.jsx): «Все», первые max языков кнопками, выбранный из списка — кнопкой рядом,
/// остальные (их сотни — каталог bible.helloao.org) — кнопкой «Ещё языки» со списком по алфавиту
List<Widget> langChips(BuildContext context, Palette pal, {required List<String> codes, required String? value, required String? allValue, required String allLabel, required String Function(String) name, required ValueChanged<String?> onChanged, Map<String, int>? counts, int max = 8, bool compact = false}) {
  final head = codes.take(max).toList();
  final rest = codes.skip(max).toList()..sort((a, b) => name(a).compareTo(name(b)));
  return [
    AobChip(compact: compact, label: allLabel, on: value == allValue, onTap: () => onChanged(allValue)),
    for (final c in [...head, if (value != null && value != allValue && !head.contains(value)) value])
      AobChip(compact: compact, label: name(c), on: value == c, count: counts?[c], onTap: () => onChanged(c)),
    if (rest.isNotEmpty)
      AobChip(compact: compact, label: t('Ещё языки'), count: rest.length, icon: LucideIcons.chevronDown, onTap: () async {
        final v = await showDialog<String>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: pal.panel,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 8), child: Text(t('Ещё языки'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text))),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rest.length,
                    itemBuilder: (_, i) => InkWell(
                      onTap: () => Navigator.pop(ctx, rest[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                        child: Row(children: [
                          Expanded(child: Text(name(rest[i]), style: TextStyle(fontSize: 15, color: pal.text))),
                          if (counts?[rest[i]] case final n?) Text('$n', style: TextStyle(fontSize: 13, color: pal.muted)),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        );
        if (v != null) onChanged(v);
      }),
  ];
}

String fmtSize(int bytes) => bytes >= 1048576 ? '${(bytes / 1048576).toStringAsFixed(bytes >= 10485760 ? 0 : 1)} ${t('МБ')}' : '${(bytes / 1024).round().clamp(1, 1 << 30)} ${t('КБ')}';

/// Строка списка: описание модуля из каталога и/или установленного
class _Item {
  _Item(this.json, {this.installed, this.cat});
  final Map<String, dynamic> json;
  final InstalledModule? installed;
  final CatalogEntry? cat;
  String get id => json['id'] as String;
  String get type => json['type'] as String? ?? 'bible';
  String get name => json['name'] as String? ?? id;
  String get title => json['title'] as String? ?? '';
  String get language => json['language'] as String? ?? '';
  String? str(String k) => json[k]?.toString().isNotEmpty == true ? json[k].toString() : null;
  int get size => (json['sizeGz'] ?? json['size'] ?? 0) is int ? (json['sizeGz'] ?? json['size'] ?? 0) as int : 0;
  bool get unavailable => json['unavailable'] == true;
}

// Цвет --danger из styles.css
Color _danger(Palette p) => p.dark ? const Color(0xffef8a78) : const Color(0xffb4412f);

/// Закрашенная звезда (Star с fill="currentColor"): в наборе значков есть только контурная
class _FilledStar extends StatelessWidget {
  const _FilledStar({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(20, 20), painter: _StarPainter(color));
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const pts = [(12.0, 2.0), (15.09, 8.26), (22.0, 9.27), (17.0, 14.14), (18.18, 21.02), (12.0, 17.77), (5.82, 21.02), (7.0, 14.14), (2.0, 9.27), (8.91, 8.26)];
    final k = size.width / 24;
    final path = Path()..moveTo(pts[0].$1 * k, pts[0].$2 * k);
    for (final p in pts.skip(1)) {
      path.lineTo(p.$1 * k, p.$2 * k);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2 * k..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}

/// Кнопка действия в строке модуля (.row-act): круг 44, значок 20
class _Act extends StatelessWidget {
  const _Act({required this.child, this.tip, this.onTap});
  final Widget child;
  final String? tip;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final w = SizedBox(
      width: 44,
      height: 44,
      child: Material(type: MaterialType.transparency, shape: const CircleBorder(), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Center(child: child))),
    );
    return tip == null ? w : Tooltip(message: tip!, child: w);
  }
}

/// Идёт загрузка (.mod-busy): на месте кнопки — кольцо прогресса и проценты цветом акцента
class ModBusy extends StatelessWidget {
  const ModBusy({super.key, required this.pal, required this.value});
  final Palette pal;
  final double value;
  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Semantics(
      label: t('Загрузка {pct}%', {'pct': '$pct'}),
      child: SizedBox(
        height: 44,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: value.clamp(0.0, 1.0), strokeWidth: 2.4, color: pal.accent, backgroundColor: pal.line)),
          const SizedBox(width: 6),
          Text('$pct%', style: TextStyle(color: pal.accent, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 2),
        ]),
      ),
    );
  }
}

/// Кнопка-капсула в строке модуля: «Скачать» — заливка акцентом, «Обновить» — рамкой; высота 30, поле нажатия 44
class ModPill extends StatelessWidget {
  const ModPill({super.key, required this.label, required this.pal, this.tip, this.onTap, this.outline = false});
  final String label;
  final Palette pal;
  final String? tip;
  final VoidCallback? onTap;
  final bool outline;
  @override
  Widget build(BuildContext context) {
    final w = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Center(
          widthFactor: 1,
          child: Material(
            color: outline ? Colors.transparent : pal.accent,
            shape: StadiumBorder(side: BorderSide(color: pal.accent)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: SizedBox(
                  height: 30,
                  child: Center(widthFactor: 1, child: Transform.translate(offset: const Offset(0, -1), child: Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13.5, height: 1.2, leadingDistribution: TextLeadingDistribution.even, fontWeight: FontWeight.w600, color: outline ? pal.accent : pal.onAccent)))),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tip == null ? w : Tooltip(message: tip!, child: w);
  }
}

class LibrarySheet extends ConsumerStatefulWidget {
  const LibrarySheet({super.key, this.tab = 'installed', this.outer});
  final String tab;
  final BuildContext? outer; // экран под окном: «Перейти» открывает там вторую панель или окно модуля
  @override
  ConsumerState<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends ConsumerState<LibrarySheet> {
  late String _tab = widget.tab;
  String _filter = 'all', _lang = 'all', _q = '';
  final _more = <String, int>{}; // сколько строк раздела показано (по 60, «Показать ещё» — ещё 200)
  final _search = TextEditingController();
  List<CatalogEntry>? _catalog;
  String? _catErr;
  String _source = ''; // свой каталог (адрес); пусто — встроенный
  final _url = TextEditingController();
  bool _srcOpen = false;
  final Map<String, (double, String)> _busy = {};
  String? _open;
  String? _was; // карточка, которая сейчас сворачивается: её подробности живут до конца анимации

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _search.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalog = null;
      _catErr = null;
    });
    try {
      final c = _source.isEmpty ? await loadCatalog() : await ModuleStore.instance.catalog(url: _source);
      if (mounted) setState(() => _catalog = c);
    } catch (e) {
      if (mounted) setState(() => _catErr = _source.isEmpty ? '${t('Не удалось подключиться к серверу. Проверьте интернет.')}\n$e' : '$e');
    }
  }

  Future<void> _install(CatalogEntry c) async {
    setState(() => _busy[c.id] = (0, t('Подготовка…')));
    try {
      await ModuleStore.instance.install(c, onProgress: (p, l) {
        if (mounted) setState(() => _busy[c.id] = (p, t(l)));
      });
      if (mounted) toast(context, c.json['online'] != null ? t('{name} добавлен', {'name': c.name}) : t('{name} установлен', {'name': c.name}));
    } catch (e) {
      if (mounted) toast(context, '${c.name}: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
    }
  }

  // «Перейти»: перевод — во второй панели (рядом с первой), комментарий — к стиху первой панели, карты — окном
  static const _goTypes = {'bible', 'commentary', 'maps'};
  void _go(InstalledModule m) {
    final outer = widget.outer;
    Navigator.pop(context);
    if (outer == null || !outer.mounted) return;
    final panes = ref.read(panesProvider.notifier);
    if (m.type == 'bible') {
      if (ref.read(panesProvider).length < 2) {
        panes.toggleSplit(moduleId: m.id);
      } else {
        panes.setModule(1, m.id);
      }
    } else if (m.type == 'commentary') {
      Hub.openCommentary?.call(outer, ref, 0, livePositions[0]?.value ?? ref.read(panesProvider).first.ref);
    } else if (m.type == 'maps') {
      openMapsSheet(outer, ref, 0);
    }
  }

  Future<void> _remove(_Item m) async {
    await ModuleStore.instance.remove(m.id);
    if (mounted) {
      setState(() {});
      toast(context, t('{name} удалён', {'name': m.name}));
    }
  }

  void _primary(_Item m) {
    ref.read(settingsProvider.notifier).set({'primaryModule': m.id});
    toast(context, t('{name} — основной перевод', {'name': m.name}));
  }

  // строка для поиска собирается один раз на модуль (и язык интерфейса): каталог — полторы тысячи модулей
  static final _hay = Expando<(String, String)>();
  bool _matches(_Item m, String q) {
    if (q.isEmpty) return true;
    var h = _hay[m.json];
    if (h == null || h.$1 != currentLang) {
      _hay[m.json] = h = (currentLang, [m.name, m.title, m.str('description'), m.str('author'), langName(m.language)].whereType<String>().join(' ').toLowerCase().replaceAll('ё', 'е'));
    }
    return h.$2.contains(q);
  }

  bool _updatable(_Item m) {
    final c = m.cat, i = m.installed;
    return c != null && i != null && !c.unavailable && c.version.isNotEmpty && i.meta['catalogVersion'] != null && c.version != i.meta['catalogVersion'].toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = effectivePalette(s);
    final store = ModuleStore.instance;
    final byCat = {for (final c in _catalog ?? <CatalogEntry>[]) c.id: c};
    final base = _tab == 'installed'
        ? [for (final i in store.allInstalled) _Item({...?byCat[i.id]?.json, ...i.meta}, installed: i, cat: byCat[i.id])]
        : [for (final c in _catalog ?? <CatalogEntry>[]) _Item(c.json, installed: store.get(c.id), cat: c)];
    final q = _q.trim().toLowerCase().replaceAll('ё', 'е');
    // Числа у языков — с учётом выбранного вида и строки поиска; языков без модулей не показываем
    final langItems = base.where((m) => (_filter == 'all' || m.type == _filter) && _matches(m, q)).toList();
    final isImport = _tab == 'import';
    final lang = _lang != 'all' && !langItems.any((m) => m.language == _lang) ? 'all' : _lang;
    final list = base.where((m) => (lang == 'all' || m.language == lang) && _matches(m, q)).toList()..sort((a, b) => langRank(a.language).compareTo(langRank(b.language)));
    final counts = {for (final e in moduleSections) e.$1: list.where((m) => m.type == e.$1).length};
    final langCount = <String, int>{};
    for (final m in langItems) {
      langCount[m.language] = (langCount[m.language] ?? 0) + 1;
    }
    // чипы — слева направо по числу модулей (больше — левее); при равенстве — прежний порядок
    final langCodes = langCount.keys.toList()..sort((a, b) => (langCount[b] ?? 0) != (langCount[a] ?? 0) ? (langCount[b] ?? 0).compareTo(langCount[a] ?? 0) : langRank(a).compareTo(langRank(b)) != 0 ? langRank(a).compareTo(langRank(b)) : a.compareTo(b));
    final sections = [...moduleSections]..sort((a, b) => (counts[b.$1] ?? 0).compareTo(counts[a.$1] ?? 0));

    // .filter-chips: одна строка, прокручивается вбок
    // у края, за которым есть ещё плашки, — затухание вместо обрезки
    Widget chips(List<Widget> items) => SizedBox(height: 32, child: FadeRow(padding: const EdgeInsets.symmetric(horizontal: 16), children: items));

    // Группы по типам: выбранный тип (или все), только непустые — при любом сочетании типа, языка и поиска
    // переводы по сети (API.Bible) — отдельным разделом сразу после скачиваемых
    bool inGroup(String type, _Item m) => type == 'online' ? m.type == 'bible' && m.json['online'] != null : m.type == type && !(type == 'bible' && m.json['online'] != null);
    final groups = [
      for (final e in [for (final e in moduleSections) ...(e.$1 == 'bible' ? [e, ('online', 'Переводы по сети')] : [e])])
        if ((_filter == 'all' || e.$1 == _filter || (e.$1 == 'online' && _filter == 'bible')) && list.any((m) => inGroup(e.$1, m))) (e.$1, e.$2, list.where((m) => inGroup(e.$1, m)).toList()),
    ];
    final empty = !isImport && groups.isEmpty && !(_tab == 'catalog' && _catalog == null);

    return AppSheet(
      title: t('Библиотека модулей'),
      // вкладки, поиск и фильтры закреплены; поля 16 у вкладок и поиска, чипы сами отступают
      fixed: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AobTabs<String>(
            tabs: [('installed', t('Установленные'), null), ('catalog', t('Каталог'), null), ('import', t('Импорт'), null)],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
          if (!isImport) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AobInput(controller: _search, hint: t('Поиск: Лопухин, Стронг, KJV…'), onChanged: (v) => setState(() => _q = v)),
            ),
            const SizedBox(height: 10),
            chips([
              AobChip(compact: true, label: t('Все'), on: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
              for (final e in sections) AobChip(compact: true, label: t(e.$2), on: _filter == e.$1, count: counts[e.$1] == 0 ? null : counts[e.$1], onTap: () => setState(() => _filter = e.$1)),
            ]),
            if (langCodes.length >= 2) ...[
              const SizedBox(height: 8),
              chips([
                ...langChips(context, pal, compact: true, codes: langCodes, value: lang, allValue: 'all', allLabel: t('Все языки'), name: langName, counts: langCount, max: 10, onChanged: (v) => setState(() => _lang = v ?? 'all')),
              ]),
            ],
          ],
        ]),
      ),
      children: [
        if (isImport) ImportTab(onDone: () => setState(() => _tab = 'installed')),
        if (_tab == 'catalog' && _catErr != null) ...[
          Text(_catErr!, style: TextStyle(color: _danger(pal), height: 1.4)),
          Align(alignment: Alignment.centerLeft, child: AobButton(block: true, icon: LucideIcons.refreshCw, label: t('Повторить'), small: true, onTap: _loadCatalog)),
        ],
        if (_tab == 'catalog' && _catalog == null && _catErr == null) Loading(t('Загружаю каталог…')),
        if (empty)
          // .empty: значок 28 с тонкой линией, заголовок, пояснение
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
            child: Column(children: [
              Icon(ico(LucideIcons.bookOpen), size: 28, color: pal.muted),
              const SizedBox(height: 8),
              // выборка (тип, язык, поиск) пуста, а модули есть — «Ничего не найдено», а не «Модулей нет»
              Text(base.isNotEmpty ? t('Ничего не найдено.') : t('Модулей нет'), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
              if (base.isEmpty) ...[
                const SizedBox(height: 8),
                Text(_tab == 'installed' ? t('Скачайте из каталога или импортируйте JSON-файл.') : t('В каталоге пока нет модулей.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14.4, height: 1.45, color: pal.muted)),
              ],
            ]),
          ),
        if (!isImport)
        for (final g in groups)
          if (g.$3.isNotEmpty)
            // группа: подзаголовок (мелко, серо, 20 от края окна) и строки от края до края, как другие списки
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: iosStyleOf(ref) ? EdgeInsets.fromLTRB(4 + iosHeaderLeft, 14, 4, 8) : const EdgeInsets.fromLTRB(4, 4, 4, 2),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: t(g.$2)),
                  TextSpan(text: '  ${g.$3.length}', style: TextStyle(fontSize: iosStyleOf(ref) ? 15 : 11.5, fontWeight: FontWeight.w400)),
                ]), style: iosStyleOf(ref) ? TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.muted) : TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.muted)),
              ),
              // длинный раздел (сотни переводов каталога) — сначала первые 60 строк, остальные — «Показать ещё»
              // стиль iPhone: строки группы — в одной скруглённой карточке
              if (iosStyleOf(ref))
                Container(
                  margin: EdgeInsets.symmetric(horizontal: iosEdge - 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final (i, m) in g.$3.take(_more[g.$1] ?? 60).indexed) _row(m, s, pal, last: i == g.$3.length - 1 || i == (_more[g.$1] ?? 60) - 1),
                  ]),
                )
              else
              for (final (i, m) in g.$3.take(_more[g.$1] ?? 60).indexed) _row(m, s, pal, last: i == g.$3.length - 1),
              if (g.$3.length > (_more[g.$1] ?? 60))
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: AobButton(block: true, small: true, label: t('Показать ещё {n}', {'n': '${math.min(200, g.$3.length - (_more[g.$1] ?? 60))}'}), onTap: () => setState(() => _more[g.$1] = (_more[g.$1] ?? 60) + 200)),
                ),
            ]),
        if (_tab == 'catalog') _sourceFold(pal),
      ],
    );
  }

  Widget _row(_Item m, Settings s, Palette pal, {required bool last}) {
    final installed = m.installed;
    final busy = _busy[m.id];
    final isPrimary = installed != null && s.get<String>('primaryModule') == installed.id;
    final updatable = _updatable(m);
    final open = _open == m.id;
    Widget action;
    if (busy != null) {
      // идёт загрузка: на месте кнопки — кольцо прогресса и проценты цветом акцента
      action = ModBusy(pal: pal, value: busy.$1);
    } else if (_tab == 'catalog' && m.unavailable) {
      action = _Act(tip: t('Нет свободной электронной версии'), child: Icon(ico(LucideIcons.ban), size: 18, color: pal.muted));
    } else if (updatable) {
      action = ModPill(pal: pal, outline: true, label: t('Обновить'), tip: t('Есть новая версия'), onTap: () => _install(m.cat!));
    } else if (_tab == 'installed' && installed?.type == 'bible' && installed?.features['helper'] != true) {
      action = _Act(
        tip: isPrimary ? t('Основной перевод') : t('Сделать основным'),
        onTap: isPrimary ? null : () => _primary(m),
        child: isPrimary ? _FilledStar(color: pal.accent) : Icon(ico(LucideIcons.star), size: 20, color: pal.muted),
      );
    } else if (_tab == 'installed' && installed != null && installed.type != 'bible') {
      // включить / выключить: выключенный не участвует в словарях, комментариях и картах
      final on = ModuleStore.instance.isEnabled(installed.id);
      action = RowSwitch(
        value: on,
        tip: on ? t('Включён') : t('Отключён'),
        onChanged: (v) async {
          await ModuleStore.instance.setEnabled(installed.id, v);
          if (mounted) setState(() {});
        },
      );
    } else if (installed != null) {
      // установлен — тихая подпись с галочкой, без яркого цвета
      action = Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ico(LucideIcons.check), size: 14, color: pal.muted),
          const SizedBox(width: 4),
          Text(m.json['online'] != null ? t('Добавлен') : t('Установлен'), style: TextStyle(fontSize: 13, color: pal.muted)),
        ]),
      );
    } else if (m.json['online'] != null) {
      // перевод по сети (API.Bible): не скачивается — добавляется
      action = ModPill(pal: pal, label: t('Добавить'), tip: t('Добавить {name}', {'name': m.name}), onTap: () => _install(m.cat ?? CatalogEntry(m.json)));
    } else {
      action = ModPill(
        pal: pal,
        label: t('Скачать'),
        tip: m.size > 0 ? '${t('Скачать')} · ${fmtSize(m.size)}' : null,
        onTap: () => _install(m.cat ?? CatalogEntry(m.json)),
      );
    }
    // «Перейти» у установленного перевода, комментария, карт — рядом со звездой или переключателем
    final go = installed != null && busy == null && _goTypes.contains(installed.type) && installed.features['helper'] != true
        ? Padding(
            padding: const EdgeInsets.only(right: 4),
            child: iosStyleOf(ref)
                ? CupertinoButton.tinted(sizeStyle: CupertinoButtonSize.small, onPressed: () => _go(installed), child: Text(t('Перейти')))
                : ModPill(pal: pal, outline: true, label: t('Перейти'), tip: t('Перейти к {name}', {'name': m.name}), onTap: () => _go(installed)),
          )
        : null;
    // полное название — если оно не повторяет короткое; ниже мелко язык и размер для скачивания
    final title = m.title.isNotEmpty && m.title != m.name ? m.title : null;
    // «Новый» — модуль появился в каталоге за последние 7 дней (поле added каталога)
    final addedAt = DateTime.tryParse('${m.cat?.json['added'] ?? m.json['added'] ?? ''}');
    final isNew = addedAt != null && DateTime.now().difference(addedAt).inDays < 7;
    final meta = [if (m.language.isNotEmpty) langName(m.language), if (m.json['online'] != null) t('по сети') else if (installed == null && m.size > 0) fmtSize(m.size)].join(' · ');
    void toggle() => setState(() {
          _was = _open;
          _open = open ? null : m.id;
        });
    final off = _tab == 'installed' && installed != null && installed.type != 'bible' && !ModuleStore.instance.isEnabled(installed.id);
    // строка от края до края окна (подсветка и линия), отступ содержимого 20 — как PrefRow
    final ios = iosStyleOf(ref);
    Widget edge(Widget w) => ios ? w : bleed(w);
    return Opacity(opacity: off ? 0.72 : 1, child: edge(Container(
      decoration: ios
          ? null
          : BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: pal.line))),
      foregroundDecoration: ios && !last ? BoxDecoration(border: Border(bottom: BorderSide(color: pal.line, width: 0.5))) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
            child: Row(children: [
              Expanded(
                child: Opacity(
                  opacity: m.unavailable ? 0.6 : 1,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(m.name, style: TextStyle(fontSize: 15.5, height: 1.3, fontWeight: FontWeight.w700, color: pal.text))),
                      if (isNew)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(999)),
                          child: Text(t('Новый@@модуль'), style: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, color: pal.onAccent, leadingDistribution: TextLeadingDistribution.even)),
                        ),
                    ]),
                    if (title != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.8, height: 1.35, color: pal.text.withValues(alpha: 0.82)))),
                    if (meta.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.muted))),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              ?go,
              action,
              // стрелка подробностей: маленькая и тихая, при раскрытии переворачивается
              SizedBox(width: 32, height: 44, child: Center(child: AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(ico(LucideIcons.chevronDown), size: 16, color: pal.muted.withValues(alpha: 0.75))))),
            ]),
          ),
        ),
        // подробности раскрываются плавно; собираем их только у открытой и сворачивающейся строки — строк в списке сотни
        Reveal(open: open, child: open || _was == m.id ? _details(m, pal, isPrimary, updatable, busy != null) : const SizedBox(width: double.infinity)),
      ]),
    )));
  }

  /// «Источник каталога»: свой адрес aob-catalog, возврат к встроенному, обновление списка
  Widget _sourceFold(Palette pal) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LibFold(
          title: t('Источник каталога'),
          open: _srcOpen,
          onToggle: () => setState(() => _srcOpen = !_srcOpen),
          children: [
            Text(
              '${_source.isEmpty ? '${t('Сейчас — встроенный каталог.')} ' : '${t('Сейчас — {url}.', {'url': _source})} '}${t('Можно подключить свой каталог aob-catalog: https://…/catalog.json (нужен CORS).')}',
              style: TextStyle(fontSize: 13.1, color: pal.muted, height: 1.4),
            ),
            Row(children: [
              Expanded(child: AobInput(controller: _url, icon: null, hint: 'https://…/catalog.json', onSubmitted: (_) => _connect())),
              const SizedBox(width: 8),
              AobButton(label: t('Подключить'), onTap: _connect),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_source.isNotEmpty)
                AobButton(
                  small: true,
                  label: t('Встроенный каталог'),
                  onTap: () {
                    _url.clear();
                    _source = '';
                    _loadCatalog();
                  },
                ),
              AobButton(small: true, icon: LucideIcons.refreshCw, label: t('Обновить список'), onTap: _loadCatalog),
            ]),
          ],
        ),
      );

  void _connect() {
    _source = _url.text.trim();
    _loadCatalog();
  }

  String? _stats(_Item m) {
    final s = m.json['stats'];
    if (s is! Map) return null;
    int n(String k) => (s[k] as num?)?.toInt() ?? 0;
    return switch (m.type) {
      'bible' => t('{books} кн., {verses} стихов', {'books': '${n('books')}', 'verses': fmtNum(n('verses'))}),
      'dictionary' || 'commentary' => t('{n} статей', {'n': fmtNum(n('entries'))}),
      'maps' => n('places') > 0 ? t('{n} мест', {'n': '${n('places')}'}) : t('{n} карт', {'n': '${n('maps')}'}),
      'audio' => t('{n} глав', {'n': '${n('chapters')}'}),
      _ => t('ссылки для {n} стихов', {'n': fmtNum(n('verses'))}),
    };
  }

  Widget _details(_Item m, Palette pal, bool isPrimary, bool updatable, bool busy) {
    final installed = m.installed;
    final facts = <(String, String)>[
      (t('Вид'), t(moduleTypeNames[m.type] ?? m.type) + (m.str('dictionaryKind') != null ? ' · ${m.str('dictionaryKind') == 'strongs' ? t('по номерам Стронга') : t('по словам')}' : '')),
      if (_stats(m) != null || m.size > 0) (t('Объём'), [?_stats(m), if (m.size > 0) fmtSize(m.size)].join(' · ')),
      if (m.language.isNotEmpty) (t('Язык'), langName(m.language)),
      if (m.json['online'] != null) (t('Чтение'), t('по сети (API.Bible): главы приходят, когда вы их открываете')),
      if (m.str('version') != null) (t('Версия'), m.str('version')!),
      if (m.str('license') != null) (t('Лицензия'), m.str('license')!),
      if (m.str('author') != null) (t('Автор'), m.str('author')!),
      if (m.str('source') != null) (t('Источник'), m.str('source')!),
    ];
    // подробности: поля 20 по бокам, как у строки
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.str('description') != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(m.str('description')!, style: TextStyle(fontSize: 14.4, color: pal.text, height: 1.45))),
        // .mod-facts: две колонки, подписи бледные, 13.1
        Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: const {1: FlexColumnWidth()},
          children: [
            for (final f in facts)
              TableRow(children: [
                Padding(padding: const EdgeInsets.only(right: 12, bottom: 3), child: Text(f.$1, style: TextStyle(color: pal.muted, fontSize: 13.1))),
                Padding(padding: const EdgeInsets.only(bottom: 3), child: SelectableText(f.$2, style: TextStyle(fontSize: 13.1, color: pal.text))),
              ]),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 4),
          Text(_busy[m.id]!.$2, style: TextStyle(fontSize: 13.1, color: pal.muted)),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: _busy[m.id]!.$1, minHeight: 5, color: pal.accent, backgroundColor: pal.line)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (installed?.type == 'bible' && installed?.features['helper'] != true && !isPrimary) AobButton(small: true, icon: LucideIcons.star, label: t('Сделать основным'), onTap: () => _primary(m)),
          if (installed == null && !m.unavailable && m.json['online'] != null)
            AobButton(small: true, kind: BtnKind.primary, icon: LucideIcons.plus, label: t('Добавить'), onTap: busy ? null : () => _install(m.cat ?? CatalogEntry(m.json))),
          if (installed == null && !m.unavailable && m.json['online'] == null)
            AobButton(small: true, kind: BtnKind.primary, icon: LucideIcons.download, label: '${t('Скачать')}${m.size > 0 ? ' · ${fmtSize(m.size)}' : ''}', onTap: busy ? null : () => _install(m.cat ?? CatalogEntry(m.json))),
          if (installed != null && m.cat != null && !m.cat!.unavailable && m.json['online'] == null)
            AobButton(small: true, icon: LucideIcons.refreshCw, label: updatable ? t('Обновить') : t('Переустановить'), onTap: busy ? null : () => _install(m.cat!)),
          if (installed != null) ConfirmButton(small: true, icon: LucideIcons.trash2, label: t('Удалить'), confirmText: t('Удалить'), onConfirm: () => _remove(m)),
        ]),
      ]),
    );
  }
}


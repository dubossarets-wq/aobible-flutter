// Библиотека модулей (ModuleLibrary.jsx): установленные и каталог, поиск, фильтры по виду и языку (языки без модулей
// не показываем), скачать / обновить / удалить, основной перевод, вкладка «Импорт» (library_import.dart), свой каталог
// («Источник каталога»), включение и выключение небиблейских модулей (переключатель и свайп).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'colors.dart';
import 'intl_data.dart';
import 'library_import.dart';
import 'sheet.dart';

Future<void> openLibrary(BuildContext context, {String tab = 'installed'}) => showAppSheet(context, (_) => LibrarySheet(tab: tab));

/// Виды модулей по порядку показа (MODULE_SECTIONS)
const moduleSections = <(String, String)>[
  ('bible', 'Переводы'), ('commentary', 'Комментарии'), ('dictionary', 'Словари'), ('maps', 'Карты'),
  ('illustrations', 'Иллюстрации'), ('audio', 'Аудиокниги'), ('crossrefs', 'Параллельные места'),
];
const moduleTypeNames = <String, String>{
  'bible': 'Перевод Библии', 'commentary': 'Комментарий', 'dictionary': 'Словарь', 'maps': 'Карты',
  'crossrefs': 'Параллельные места', 'audio': 'Аудиокнига', 'illustrations': 'Иллюстрации',
};
// Значки видов — как TYPE_ICON в веб-версии (у остальных видов — BookText)
const _typeIcon = <String, IconData>{
  'bible': LucideIcons.bookOpen, 'commentary': LucideIcons.messageSquareText, 'dictionary': LucideIcons.bookText, 'maps': LucideIcons.map,
  'crossrefs': LucideIcons.link2, 'audio': LucideIcons.headphones,
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
final _order = _langNames.keys.toList();
int langRank(String code) => _order.contains(code) ? _order.indexOf(code) : _order.length + (code.isEmpty ? 1 : 0);

/// Название языка: в русском интерфейсе — по-русски, в остальных — на самом языке (если он среди языков приложения)
String langName(String code) {
  if (code.isEmpty) return t('Другие');
  // не русский интерфейс — название на языке интерфейса, как Intl.DisplayNames в веб-версии
  if (currentLang != 'ru') {
    final s = langDisplayNames[currentLang]?[code];
    if (s != null) return s;
  }
  return _langNames[code] ?? code.toUpperCase();
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

// Цвета --ok и --danger из styles.css
Color _ok(Palette p) => p.dark ? const Color(0xff7cc68a) : const Color(0xff2f6339);
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

class LibrarySheet extends ConsumerStatefulWidget {
  const LibrarySheet({super.key, this.tab = 'installed'});
  final String tab;
  @override
  ConsumerState<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends ConsumerState<LibrarySheet> {
  late String _tab = widget.tab;
  String _filter = 'all', _lang = 'all', _q = '';
  final _search = TextEditingController();
  List<CatalogEntry>? _catalog;
  String? _catErr;
  String _source = ''; // свой каталог (адрес); пусто — встроенный
  final _url = TextEditingController();
  bool _srcOpen = false;
  final Map<String, (double, String)> _busy = {};
  String? _open;

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
      if (mounted) toast(context, t('{name} установлен', {'name': c.name}));
    } catch (e) {
      if (mounted) toast(context, '${c.name}: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(c.id));
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

  bool _matches(_Item m, String q) => q.isEmpty || [m.name, m.title, m.str('description'), m.str('author'), langName(m.language)].any((x) => x != null && x.toLowerCase().replaceAll('ё', 'е').contains(q));

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
    final langCodes = langCount.keys.toList()..sort((a, b) => langRank(a).compareTo(langRank(b)) != 0 ? langRank(a).compareTo(langRank(b)) : a.compareTo(b));

    // .filter-chips: одна строка, прокручивается вбок
    // у края, за которым есть ещё плашки, — затухание вместо обрезки
    Widget chips(List<Widget> items) => SizedBox(height: 34, child: FadeRow(padding: const EdgeInsets.symmetric(horizontal: 16), children: items));

    // Группы по типам: выбранный тип (или все), только непустые — при любом сочетании типа, языка и поиска
    final groups = [
      for (final e in moduleSections)
        if ((_filter == 'all' || e.$1 == _filter) && list.any((m) => m.type == e.$1)) (e.$1, e.$2, list.where((m) => m.type == e.$1).toList()),
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
            const SizedBox(height: 12),
            chips([
              AobChip(label: t('Все'), on: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
              for (final e in moduleSections) AobChip(label: t(e.$2), on: _filter == e.$1, count: counts[e.$1] == 0 ? null : counts[e.$1], onTap: () => setState(() => _filter = e.$1)),
            ]),
            if (langCodes.length >= 2) ...[
              const SizedBox(height: 12),
              chips([
                AobChip(label: t('Все языки'), on: lang == 'all', onTap: () => setState(() => _lang = 'all')),
                for (final c in langCodes) AobChip(label: langName(c), on: lang == c, count: langCount[c], onTap: () => setState(() => _lang = c)),
              ]),
            ],
          ],
        ]),
      ),
      children: [
        if (isImport) ImportTab(onDone: () => setState(() => _tab = 'installed')),
        if (_tab == 'catalog' && _catErr != null) ...[
          Text(_catErr!, style: TextStyle(color: _danger(pal), height: 1.4)),
          Align(alignment: Alignment.centerLeft, child: AobButton(icon: LucideIcons.refreshCw, label: t('Повторить'), small: true, onTap: _loadCatalog)),
        ],
        if (_tab == 'catalog' && _catalog == null && _catErr == null) Loading(t('Загружаю каталог…')),
        if (empty)
          // .empty: значок 28 с тонкой линией, заголовок, пояснение
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
            child: Column(children: [
              Icon(LucideIcons.bookOpen, size: 28, color: pal.muted),
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
            // .nav-group: заголовок h4 и список в рамке; зазор 8
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: t(g.$2)),
                  TextSpan(text: '  ${g.$3.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
                ]), style: TextStyle(fontSize: 13.76, fontWeight: FontWeight.w600, color: pal.muted)),
              ),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
                child: Column(children: [
                  for (final (i, m) in g.$3.indexed) _row(m, s, pal, first: i == 0),
                ]),
              ),
            ]),
        if (_tab == 'catalog') _sourceFold(pal),
      ],
    );
  }

  Widget _row(_Item m, Settings s, Palette pal, {required bool first}) {
    final installed = m.installed;
    final busy = _busy[m.id];
    final isPrimary = installed != null && s.get<String>('primaryModule') == installed.id;
    final updatable = _updatable(m);
    final open = _open == m.id;
    Widget action;
    if (busy != null) {
      // .row-act.busy: вертушка и проценты цветом акцента
      action = Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [Spin(color: pal.accent), const SizedBox(width: 4), Text('${(busy.$1 * 100).round()}%', style: TextStyle(color: pal.accent, fontSize: 12.5))]),
      );
    } else if (_tab == 'catalog' && m.unavailable) {
      action = _Act(tip: t('Нет свободной электронной версии'), child: Icon(LucideIcons.ban, size: 20, color: pal.muted));
    } else if (updatable) {
      action = _Act(tip: t('Есть новая версия'), onTap: () => _install(m.cat!), child: Icon(LucideIcons.refreshCw, size: 20, color: pal.accent));
    } else if (_tab == 'installed' && installed?.type == 'bible' && installed?.features['helper'] != true) {
      action = _Act(
        tip: isPrimary ? t('Основной перевод') : t('Сделать основным'),
        onTap: isPrimary ? null : () => _primary(m),
        child: isPrimary ? _FilledStar(color: pal.accent) : Icon(LucideIcons.star, size: 20, color: pal.muted),
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
      action = _Act(tip: t('Установлен'), child: Icon(LucideIcons.circleCheck, size: 20, color: _ok(pal)));
    } else {
      action = _Act(
        tip: '${t('Скачать')}${m.size > 0 ? ' · ${fmtSize(m.size)}' : ''}',
        onTap: () => _install(m.cat ?? CatalogEntry(m.json)),
        child: Icon(LucideIcons.download, size: 20, color: pal.accent),
      );
    }
    final sub = [if (m.language.isNotEmpty) langName(m.language), m.title.isNotEmpty ? m.title : t(moduleTypeNames[m.type] ?? m.type)].join(' · ');
    void toggle() => setState(() => _open = open ? null : m.id);
    final off = _tab == 'installed' && installed != null && installed.type != 'bible' && !ModuleStore.instance.isEnabled(installed.id);
    return Opacity(opacity: off ? 0.72 : 1, child: Container(
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: pal.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(children: [
            // .mod-main: значок вида цвета акцента, название и ниже язык · описание
            Expanded(
              child: InkWell(
                onTap: toggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(children: [
                    Icon(_typeIcon[m.type] ?? LucideIcons.bookText, size: 20, color: pal.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Opacity(
                        opacity: m.unavailable ? 0.6 : 1,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.name, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 15.7, fontWeight: FontWeight.w700, color: pal.text)),
                          const SizedBox(height: 1),
                          Text(sub, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 13.1, color: pal.muted)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            action,
            // .row-chev: 40×44, при раскрытии переворачивается
            InkWell(
              onTap: toggle,
              child: SizedBox(width: 40, height: 44, child: Center(child: AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(LucideIcons.chevronDown, size: 20, color: pal.muted)))),
            ),
            const SizedBox(width: 4),
          ]),
        ),
        if (open) _details(m, pal, isPrimary, updatable, busy != null),
      ]),
    ));
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
      if (m.language.isNotEmpty) (t('Язык'), m.language.toUpperCase()),
      if (m.str('version') != null) (t('Версия'), m.str('version')!),
      if (m.str('license') != null) (t('Лицензия'), m.str('license')!),
      if (m.str('author') != null) (t('Автор'), m.str('author')!),
      if (m.str('source') != null) (t('Источник'), m.str('source')!),
    ];
    // .mod-more: поля 0 14 12 46, зазор 10
    return Padding(
      padding: const EdgeInsets.fromLTRB(46, 0, 14, 12),
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
          if (installed == null && !m.unavailable)
            AobButton(small: true, kind: BtnKind.primary, icon: LucideIcons.download, label: '${t('Скачать')}${m.size > 0 ? ' · ${fmtSize(m.size)}' : ''}', onTap: busy ? null : () => _install(m.cat ?? CatalogEntry(m.json))),
          if (installed != null && m.cat != null && !m.cat!.unavailable)
            AobButton(small: true, icon: LucideIcons.refreshCw, label: updatable ? t('Обновить') : t('Переустановить'), onTap: busy ? null : () => _install(m.cat!)),
          if (installed != null) ConfirmButton(small: true, icon: LucideIcons.trash2, label: t('Удалить'), confirmText: t('Удалить'), onConfirm: () => _remove(m)),
        ]),
      ]),
    );
  }
}


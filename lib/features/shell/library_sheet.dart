// Библиотека модулей (ModuleLibrary.jsx): установленные и каталог, поиск, фильтры по виду и языку (языки без модулей
// не показываем), скачать / обновить / удалить, основной перевод. Не перенесено: импорт из файла и свой каталог
// (в ModuleStore пока нет разбора файлов и переключения адреса), включение/отключение небиблейских модулей.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'colors.dart';
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
const _typeIcon = <String, IconData>{
  'bible': Icons.menu_book_outlined, 'commentary': Icons.chat_bubble_outline, 'dictionary': Icons.abc, 'maps': Icons.map_outlined,
  'crossrefs': Icons.link, 'audio': Icons.headphones_outlined, 'illustrations': Icons.image_outlined,
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
  if (currentLang != 'ru') {
    final l = langs.where((x) => x.code == code).firstOrNull;
    if (l != null) return l.name;
  }
  return _langNames[code] ?? code.toUpperCase();
}

String fmtSize(int bytes) => bytes >= 1048576 ? '${(bytes / 1048576).toStringAsFixed(bytes >= 10485760 ? 0 : 1)} ${t('МБ')}' : '${(bytes / 1024).round()} ${t('КБ')}';

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

class LibrarySheet extends ConsumerStatefulWidget {
  const LibrarySheet({super.key, this.tab = 'installed'});
  final String tab;
  @override
  ConsumerState<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends ConsumerState<LibrarySheet> {
  late String _tab = widget.tab;
  String _filter = 'all', _lang = 'all', _q = '';
  List<CatalogEntry>? _catalog;
  String? _catErr;
  final Map<String, (double, String)> _busy = {};
  String? _open;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalog = null;
      _catErr = null;
    });
    try {
      final c = await ModuleStore.instance.catalog();
      if (mounted) setState(() => _catalog = c);
    } catch (e) {
      if (mounted) setState(() => _catErr = '${t('Не удалось подключиться к серверу. Проверьте интернет.')}\n$e');
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
        ? [for (final i in store.installed) _Item({...?byCat[i.id]?.json, ...i.meta}, installed: i, cat: byCat[i.id])]
        : [for (final c in _catalog ?? <CatalogEntry>[]) _Item(c.json, installed: store.get(c.id), cat: c)];
    final q = _q.trim().toLowerCase().replaceAll('ё', 'е');
    // Числа у языков — с учётом выбранного вида и строки поиска; языков без модулей не показываем
    final langItems = base.where((m) => (_filter == 'all' || m.type == _filter) && _matches(m, q)).toList();
    final lang = _lang != 'all' && !langItems.any((m) => m.language == _lang) ? 'all' : _lang;
    final list = base.where((m) => (lang == 'all' || m.language == lang) && _matches(m, q)).toList()..sort((a, b) => langRank(a.language).compareTo(langRank(b.language)));
    final counts = {for (final e in moduleSections) e.$1: list.where((m) => m.type == e.$1).length};
    final langCount = <String, int>{};
    for (final m in langItems) {
      langCount[m.language] = (langCount[m.language] ?? 0) + 1;
    }
    final langCodes = langCount.keys.toList()..sort((a, b) => langRank(a).compareTo(langRank(b)) != 0 ? langRank(a).compareTo(langRank(b)) : a.compareTo(b));

    Widget chip(String label, bool on, VoidCallback tap, {int? n}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(label: Text(n != null && n > 0 ? '$label  $n' : label), selected: on, onSelected: (_) => tap(), visualDensity: VisualDensity.compact),
        );

    final groups = [for (final e in moduleSections) if (lang == 'all' && _filter == 'all' ? list.any((m) => m.type == e.$1) : e.$1 == _filter) (e.$1, e.$2, list.where((m) => m.type == e.$1).toList())];

    return AppSheet(
      title: t('Библиотека модулей'),
      full: true,
      fixed: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: Column(children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [ButtonSegment(value: 'installed', label: Text(t('Установленные'))), ButtonSegment(value: 'catalog', label: Text(t('Каталог')))],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('Поиск: Лопухин, Стронг, KJV…'), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              chip(t('Все'), _filter == 'all', () => setState(() => _filter = 'all')),
              for (final e in moduleSections) chip(t(e.$2), _filter == e.$1, () => setState(() => _filter = e.$1), n: counts[e.$1]),
            ]),
          ),
          if (langCodes.length >= 2)
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                chip(t('Все языки'), lang == 'all', () => setState(() => _lang = 'all')),
                for (final c in langCodes) chip(langName(c), lang == c, () => setState(() => _lang = c), n: langCount[c]),
              ]),
            ),
        ]),
      ),
      children: [
        if (_tab == 'catalog' && _catErr != null) ...[
          Text(_catErr!, style: const TextStyle(color: Colors.redAccent)),
          Center(child: TextButton.icon(onPressed: _loadCatalog, icon: const Icon(Icons.refresh), label: Text(t('Повторить')))),
        ],
        if (_tab == 'catalog' && _catalog == null && _catErr == null)
          Padding(padding: const EdgeInsets.all(24), child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text(t('Загружаю каталог…'))]))),
        if (list.isEmpty && !(_tab == 'catalog' && _catalog == null))
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.menu_book_outlined, size: 36, color: pal.muted),
              Text(t('Модулей нет'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(_tab == 'installed' ? t('Скачайте из каталога или импортируйте JSON-файл.') : t('В каталоге пока нет модулей.'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
            ]),
          ),
        for (final g in groups)
          if (g.$3.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text('${t(g.$2)}  ${g.$3.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.muted))),
            for (final m in g.$3) _row(m, s, pal),
          ],
      ],
    );
  }

  Widget _row(_Item m, Settings s, Palette pal) {
    final installed = m.installed;
    final busy = _busy[m.id];
    final isPrimary = installed != null && s.get<String>('primaryModule') == installed.id;
    final updatable = _updatable(m);
    final open = _open == m.id;
    Widget action;
    if (busy != null) {
      action = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 6), Text('${(busy.$1 * 100).round()}%', style: TextStyle(color: pal.muted, fontSize: 13))]),
      );
    } else if (_tab == 'catalog' && m.unavailable) {
      action = IconButton(icon: Icon(Icons.block, color: pal.muted), tooltip: t('Нет свободной электронной версии'), onPressed: null);
    } else if (updatable) {
      action = IconButton(icon: Icon(Icons.refresh, color: pal.accent), tooltip: t('Есть новая версия'), onPressed: () => _install(m.cat!));
    } else if (_tab == 'installed' && installed?.type == 'bible' && installed?.features['helper'] != true) {
      action = IconButton(
        icon: Icon(isPrimary ? Icons.star : Icons.star_border, color: isPrimary ? pal.accent : pal.muted),
        tooltip: isPrimary ? t('Основной перевод') : t('Сделать основным'),
        onPressed: isPrimary ? null : () => _primary(m),
      );
    } else if (installed != null) {
      action = Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.check_circle_outline, color: pal.accent));
    } else {
      action = IconButton(
        icon: Icon(Icons.download, color: pal.accent),
        tooltip: '${t('Скачать')}${m.size > 0 ? ' · ${fmtSize(m.size)}' : ''}',
        onPressed: () => _install(m.cat ?? CatalogEntry(m.json)),
      );
    }
    final sub = [if (m.language.isNotEmpty) langName(m.language), m.title.isNotEmpty ? m.title : t(moduleTypeNames[m.type] ?? m.type)].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _open = open ? null : m.id),
        child: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Row(children: [
            Icon(_typeIcon[m.type] ?? Icons.abc, size: 22, color: pal.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: m.unavailable ? pal.muted : pal.text)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.muted)),
                ]),
              ),
            ),
            action,
            Icon(open ? Icons.expand_less : Icons.expand_more, color: pal.muted),
          ]),
        ),
      ),
      if (open) _details(m, pal, isPrimary, updatable, busy != null),
      Divider(height: 1, color: pal.line),
    ]);
  }

  Widget _details(_Item m, Palette pal, bool isPrimary, bool updatable, bool busy) {
    final installed = m.installed;
    final facts = <(String, String)>[
      (t('Вид'), t(moduleTypeNames[m.type] ?? m.type) + (m.str('dictionaryKind') != null ? ' · ${m.str('dictionaryKind') == 'strongs' ? t('по номерам Стронга') : t('по словам')}' : '')),
      if (m.size > 0) (t('Объём'), fmtSize(m.size)),
      if (m.language.isNotEmpty) (t('Язык'), m.language.toUpperCase()),
      if (m.str('version') != null) (t('Версия'), m.str('version')!),
      if (m.str('license') != null) (t('Лицензия'), m.str('license')!),
      if (m.str('author') != null) (t('Автор'), m.str('author')!),
      if (m.str('source') != null) (t('Источник'), m.str('source')!),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.str('description') != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(m.str('description')!, style: TextStyle(color: pal.text, height: 1.35))),
        for (final f in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 84, child: Text(f.$1, style: TextStyle(color: pal.muted, fontSize: 13))),
              Expanded(child: SelectableText(f.$2, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        if (busy) Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: _busy[m.id]!.$1, color: pal.accent, backgroundColor: pal.line)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (installed?.type == 'bible' && installed?.features['helper'] != true && !isPrimary)
            OutlinedButton.icon(icon: const Icon(Icons.star_border, size: 16), label: Text(t('Сделать основным')), onPressed: () => _primary(m)),
          if (installed == null && !m.unavailable)
            FilledButton.icon(icon: const Icon(Icons.download, size: 16), label: Text('${t('Скачать')}${m.size > 0 ? ' · ${fmtSize(m.size)}' : ''}'), onPressed: busy ? null : () => _install(m.cat ?? CatalogEntry(m.json))),
          if (installed != null && m.cat != null && !m.cat!.unavailable)
            OutlinedButton.icon(icon: const Icon(Icons.refresh, size: 16), label: Text(updatable ? t('Обновить') : t('Переустановить')), onPressed: busy ? null : () => _install(m.cat!)),
          if (installed != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(t('Удалить')),
              onPressed: () async {
                if (await confirm(context, '${t('Удалить')}: ${m.name}?', t('Удалить'))) _remove(m);
              },
            ),
        ]),
      ]),
    );
  }
}

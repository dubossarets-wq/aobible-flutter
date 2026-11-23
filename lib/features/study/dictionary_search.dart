// «Словарь» (как «Ещё» → «Словарь» в Swift-версии): поиск статьи по номеру Стронга (G26, H430) или по началу слова
// во всех словарях; нажатие открывает статью.
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;

import '../../core/fuzzy.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../ui/ios_style.dart' show AIcon, ico;
import '../../ui/kit.dart';
import 'dictionary_sheet.dart';
import 'sheet.dart';
import 'study_data.dart';

/// Номер Стронга из запроса: «G26», «g 0026», «Н430» (русская «Н» — ивритский номер); иначе null
String? strongFromQuery(String q) {
  final m = RegExp(r'^([gGгГ]|[hHнН])\s*0*(\d{1,4})$').firstMatch(q.trim());
  if (m == null) return null;
  final greek = 'gGгГ'.contains(m[1]!);
  return '${greek ? 'G' : 'H'}${m[2]}';
}

Future<void> openDictionarySearch(BuildContext context) => showSheet(context, const DictionarySearchSheet(), size: SheetSize.tall);

class _Hit {
  const _Hit(this.module, this.key, this.word);
  final String module, key, word;
}

/// «Возможно, вы искали»: близкие по написанию слова словарей — заголовки статей «по словам» и слова обратного
/// указателя (русские слова, по которым находятся номера Стронга). Сначала с меньшим числом исправлений, затем покороче.
/// В отдельном потоке: слов в словарях десятки тысяч
Future<List<String>> _nearWords(List<String> paths, String raw) => Isolate.run(() {
      final query = fuzzyFold(raw).trim();
      final qc = query.codeUnits;
      if (qc.length < 3) return const <String>[];
      final allowed = fuzzyAllowed(qc.length);
      final best = <String, int>{};
      void take(String word) {
        final w = fuzzyFold(word);
        if (w.length < 3 || w == query) return;
        final s = fuzzyScore(qc, w.codeUnits, allowed);
        if (s != null && s < (best[w] ?? 1 << 30)) best[w] = s;
      }

      final strongKey = RegExp(r'^[GH]\d+$');
      for (final path in paths) {
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          bool has(String table) => db.select('SELECT 1 FROM sqlite_master WHERE name = ?', [table]).isNotEmpty;
          if (has('dict')) {
            for (final r in db.select('SELECT key FROM dict')) {
              final k = r['key'] as String;
              if (!strongKey.hasMatch(k)) take(k); // номера Стронга — не слова
            }
          }
          if (has('windex')) {
            for (final r in db.select('SELECT word FROM windex')) {
              take(r['word'] as String);
            }
          }
        } catch (_) {
          // словарь не читается — берём остальные
        } finally {
          db.close();
        }
      }
      final list = best.entries.toList()
        ..sort((a, b) {
          if (a.value != b.value) return a.value.compareTo(b.value);
          if (a.key.length != b.key.length) return a.key.length.compareTo(b.key.length);
          return a.key.compareTo(b.key);
        });
      return [for (final e in list.take(6)) e.key];
    });

class DictionarySearchSheet extends ConsumerStatefulWidget {
  const DictionarySearchSheet({super.key});
  @override
  ConsumerState<DictionarySearchSheet> createState() => _DictionarySearchSheetState();
}

class _DictionarySearchSheetState extends ConsumerState<DictionarySearchSheet> {
  final _ctl = TextEditingController();
  List<_Hit> _hits = const [];
  List<String> _near = const []; // ничего не нашлось — близкие по написанию слова
  int _gen = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    StudyData.ensure().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String _label(Map<String, dynamic> e, String key) => (e['lemma'] as String?) ?? (e['word'] as String?) ?? key;

  void _search(String raw) {
    final q = raw.trim().toLowerCase().replaceAll('ё', 'е');
    final out = <_Hit>[];
    if (q.isNotEmpty) {
      final strong = strongFromQuery(q);
      if (strong != null) {
        for (final m in StudyData.dictionaries()) {
          final e = StudyData.dictGet(m.id, strong);
          if (e != null) out.add(_Hit(m.id, strong, _label(e, strong)));
        }
      } else {
        for (final m in StudyData.dictionaries()) {
          if (StudyData.dictKind(m) == 'strongs') continue;
          for (final k in StudyData.dictPrefix(m.id, q, 30)) {
            final e = StudyData.dictGet(m.id, k);
            out.add(_Hit(m.id, k, e == null ? k : _label(e, k)));
          }
        }
      }
    }
    final gen = ++_gen;
    setState(() {
      _hits = out;
      _near = const [];
    });
    // ничего не нашлось — после короткой паузы ищем близкие слова
    if (out.isNotEmpty || q.length < 3 || strongFromQuery(q) != null) return;
    final paths = [for (final m in StudyData.dictionaries()) m.path];
    Future<void>.delayed(const Duration(milliseconds: 300)).then((_) async {
      if (!mounted || gen != _gen) return;
      final near = await _nearWords(paths, q).catchError((_) => const <String>[]);
      if (mounted && gen == _gen) setState(() => _near = near);
    });
  }

  void _pickNear(String w) {
    _ctl.value = TextEditingValue(text: w, selection: TextSelection.collapsed(offset: w.length));
    _search(w);
  }

  void _open(_Hit h) {
    final strong = RegExp(r'^[GH]\d').hasMatch(h.key);
    final panes = ref.read(panesProvider);
    openDictionary(
      context,
      DictRequest(text: h.word, strongs: strong ? [h.key] : const [], morph: const [], ref: panes.first.ref, pane: 0, preselect: (moduleId: h.module, key: h.key), autoOpen: true),
      full: strong,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final q = _ctl.text.trim();
    final none = _ready && StudyData.dictionaries().isEmpty;
    return SheetScaffold(
      title: t('Словарь'),
      body: SheetList(children: [
        AobInput(controller: _ctl, hint: t('Слово или номер Стронга'), autofocus: true, autocorrect: false, onChanged: _search, onSubmitted: _search),
        const SizedBox(height: 8),
        if (!_ready)
          Loading(t('Загрузка…'))
        else if (none)
          Text(t('Словарей пока нет. Установите их: «Ещё» → «Библиотека модулей» → «Словари».'), style: TextStyle(color: pal.muted))
        else if (q.isEmpty)
          Text(t('Введите слово или номер Стронга, например G26 или H430.'), style: TextStyle(color: pal.muted))
        else if (_hits.isEmpty)
          Text(t('Ничего не найдено.'), style: TextStyle(color: pal.muted)),
        // слово с опечаткой: близкие слова словарей; нажатие подставляет его в поиск
        if (_ready && !none && q.isNotEmpty && _hits.isEmpty && _near.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(t('Возможно, вы искали'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.muted)),
          for (final w in _near)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _pickNear(w),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                child: Row(children: [
                  AIcon(ico(LucideIcons.search), size: 16, color: pal.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(w, style: TextStyle(fontSize: 16, color: pal.accent))),
                ]),
              ),
            ),
        ],
        for (final h in _hits)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _open(h),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.word, style: const TextStyle(fontSize: 16)),
                Text('${h.key} · ${ModuleStore.instance.get(h.module)?.name ?? h.module}', style: TextStyle(fontSize: 12.5, color: pal.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}

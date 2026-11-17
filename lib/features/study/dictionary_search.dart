// «Словарь» (как «Ещё» → «Словарь» в Swift-версии): поиск статьи по номеру Стронга (G26, H430) или по началу слова
// во всех словарях; нажатие открывает статью.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
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

class DictionarySearchSheet extends ConsumerStatefulWidget {
  const DictionarySearchSheet({super.key});
  @override
  ConsumerState<DictionarySearchSheet> createState() => _DictionarySearchSheetState();
}

class _DictionarySearchSheetState extends ConsumerState<DictionarySearchSheet> {
  final _ctl = TextEditingController();
  List<_Hit> _hits = const [];
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
    setState(() => _hits = out);
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

// Параллельные места стиха (CrossReferencesSheet.jsx): ссылка + текст из перевода текущей панели.
// Нажатие открывает место во второй панели (экран делится автоматически).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'dictionary_sheet.dart';
import 'sheet.dart';
import 'study_data.dart';

Future<void> openXrefs(BuildContext context, {required int pane, required String moduleId, required VerseRef at}) =>
    showSheet(context, XrefsSheet(pane: pane, moduleId: moduleId, at: at));

class XrefsSheet extends ConsumerStatefulWidget {
  const XrefsSheet({super.key, required this.pane, required this.moduleId, required this.at});
  final int pane;
  final String moduleId;
  final VerseRef at;
  @override
  ConsumerState<XrefsSheet> createState() => _XrefsSheetState();
}

class _XrefsSheetState extends ConsumerState<XrefsSheet> {
  List<({String osis, OsisRef ref, String source})>? _refs;
  String _source = '';
  final _texts = <String, (List<({int chapter, int verse, String text})>, bool)>{};

  @override
  void initState() {
    super.initState();
    // Список строится после показа окна (у «Бытия 1:1» ссылок десятки), тексты — по мере прокрутки
    Future(() async {
      await StudyData.ensure();
      final v = StudyData.verse(widget.moduleId, widget.at);
      final refs = StudyData.refsForVerse(widget.moduleId, widget.at);
      if (!mounted) return;
      setState(() {
        _source = v == null ? '' : _plain(v);
        _refs = refs;
      });
    });
  }

  static String _plain(String raw) => raw.replaceAllMapped(RegExp(r'\{([^|}]*)\|[^}]*\}'), (m) => m.group(1)!).replaceAll('‹', '').replaceAll('›', '');

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final module = ModuleStore.instance.get(widget.moduleId);
    final refs = _refs;
    Widget body;
    if (refs == null) {
      body = SheetList(children: [Loading(t('Загрузка…'))]);
    } else if (refs.isEmpty) {
      body = SheetList(children: [if (_source.isNotEmpty) QuoteBox(_source), Empty(icon: LucideIcons.link2, title: t('Параллельных мест нет'))]);
    } else {
      // стих, к которому ищем места, — над списком: при прокрутке остаётся вверху (длинный — не выше трети экрана)
      final list = Builder(builder: (bc) => ListView.builder(
        padding: EdgeInsets.fromLTRB(16, _source.isNotEmpty ? 4 : 12, 16, 20 + MediaQuery.paddingOf(bc).bottom),
        itemCount: refs.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: H4('${t('Места')} · ${refs.length}')),
                  Hint(widget.pane == 0 ? t('Место откроется во второй панели.') : t('Место откроется здесь; вернуться — кнопкой «назад».')),
                ]),
              ]),
            );
          }
          final it = refs[i - 1];
          final tx = _texts[it.osis] ??= StudyData.textForRef(widget.moduleId, it.ref);
          final (parts, truncated) = tx;
          // строка — от края до края окна, отступ 20 — у содержимого
          return bleed(InkWell(
            onTap: () => openRefInOther(context, ref, widget.pane, it.ref.start),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtOsis(it.ref, full: true), style: TextStyle(fontWeight: FontWeight.w700, color: pal.accent, fontSize: 14.7)),
                const SizedBox(height: 3),
                if (parts.isNotEmpty)
                  Text.rich(
                    TextSpan(children: [
                      for (final p in parts) ...[
                        if (parts.length > 1) TextSpan(text: '${p.verse}', style: TextStyle(fontSize: 10, color: pal.muted, fontFeatures: const [FontFeature.superscripts()])),
                        TextSpan(text: '${p.text} '),
                      ],
                      if (truncated) TextSpan(text: '…', style: TextStyle(color: pal.muted)),
                    ]),
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  )
                else
                  Text(t('В переводе {module} нет этой книги.', {'module': module?.name ?? '', 'book': Books.instance.meta(it.ref.book).name}), style: TextStyle(color: pal.muted, fontSize: 16, height: 1.5)),
              ]),
            ),
          ));
        },
      ));
      body = _source.isEmpty
          ? list
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.34),
                  child: SingleChildScrollView(child: QuoteBox(_source)),
                ),
              ),
              Expanded(child: list),
            ]);
    }
    return SheetScaffold(
      title: t('Параллельные места · {ref}', {'ref': fmtRef(widget.at)}),
      subtitle: module?.name,
      body: body,
    );
  }
}

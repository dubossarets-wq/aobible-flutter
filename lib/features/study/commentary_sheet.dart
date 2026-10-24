// Комментарий к стиху (CommentarySheet.jsx): вкладки по модулям-комментариям, текст статьи.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'dictionary_sheet.dart';
import 'sheet.dart';
import 'study_data.dart';

Future<void> openCommentary(BuildContext context, {required int pane, required VerseRef at, String? moduleId}) =>
    showSheet(context, CommentarySheet(pane: pane, at: at, moduleId: moduleId));

class CommentarySheet extends ConsumerStatefulWidget {
  const CommentarySheet({super.key, required this.pane, required this.at, this.moduleId});
  final int pane;
  final VerseRef at;
  final String? moduleId;
  @override
  ConsumerState<CommentarySheet> createState() => _CommentarySheetState();
}

class _CommentarySheetState extends ConsumerState<CommentarySheet> {
  List<({InstalledModule module, List<({String key, OsisRef ref, String title, String text})> items})>? _res;
  String? _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.moduleId;
    Future(() async {
      await StudyData.ensure();
      final r = StudyData.commentaryFor(widget.at);
      if (!mounted) return;
      setState(() {
        _res = r;
        if (!r.any((x) => x.module.id == _sel)) _sel = r.isEmpty ? null : r.first.module.id;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    final cur = res?.where((x) => x.module.id == _sel).firstOrNull;
    final fs = ((ref.watch(settingsProvider.select((s) => s.j['commentaryFontSize'])) ?? 19) as num).toDouble();
    final children = <Widget>[];
    if (res == null) {
      children.add(Loading(t('Загрузка…')));
    } else if (res.isEmpty) {
      children.add(Empty(icon: Icons.chat_bubble_outline, title: t('Комментариев к этому стиху нет')));
    } else {
      if (res.length > 1) {
        children.add(TabsRow(labels: [for (final x in res) x.module.name], index: res.indexWhere((x) => x.module.id == _sel).clamp(0, res.length - 1), onTap: (i) => setState(() => _sel = res[i].module.id)));
      }
      if (cur != null) {
        for (final it in cur.items) {
          children.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            H4('${fmtOsis(it.ref, full: true)}${it.title.isNotEmpty ? ' · ${it.title}' : ''}'),
            LinkedText(text: it.text, onOpen: (r) => openRefInOther(context, ref, widget.pane, r), style: TextStyle(fontSize: fs, height: 1.6)),
          ]));
        }
        final m = cur.module;
        children.add(SourceNote([m.name, m.meta['author'], m.meta['license']].where((x) => x != null && x.toString().isNotEmpty).join(' · ')));
      }
    }
    return SheetScaffold(
      title: t('Комментарий · {ref}', {'ref': fmtRef(widget.at)}),
      subtitle: cur?.module.title,
      body: SheetList(children: children),
    );
  }
}

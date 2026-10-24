// Сравнение выделенных стихов во всех установленных переводах (CompareSheet.jsx). Слова, которыми перевод
// отличается от открытого, подсвечены. У каждого перевода — кнопка «Параллельно»: экран делится, в другой
// панели открывается этот перевод на том же месте.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../hub.dart';
import 'interlinear.dart';
import 'sheet.dart';
import 'study_data.dart';

Future<void> openCompare(BuildContext context, WidgetRef ref, List<VerseRef> refs, String moduleId) {
  final sorted = [...refs]..sort((a, b) {
      final c = Books.instance.order(a.book).compareTo(Books.instance.order(b.book));
      if (c != 0) return c;
      return a.chapter != b.chapter ? a.chapter.compareTo(b.chapter) : a.verse.compareTo(b.verse);
    });
  return showSheet(context, CompareSheet(refs: sorted, moduleId: moduleId), size: SheetSize.tall);
}

/// Подпись выделения: «Ин. 3:16», «Ин. 3:16–18», «Ин. 3:16, 18»
String selectionLabel(List<VerseRef> refs, {bool full = false}) {
  if (refs.isEmpty) return '';
  final first = refs.first;
  if (refs.length == 1) return fmtRef(first, full: full);
  if (refs.every((r) => r.book == first.book && r.chapter == first.chapter)) {
    final vs = refs.map((r) => r.verse).toList();
    final contiguous = [for (var i = 1; i < vs.length; i++) vs[i] == vs[i - 1] + 1].every((x) => x);
    final m = Books.instance.meta(first.book);
    return '${full ? m.name : m.short} ${first.chapter}:${contiguous ? '${vs.first}–${vs.last}' : vs.join(', ')}';
  }
  return refs.map((r) => fmtRef(r, full: full)).join('; ');
}

String _selectionText(String moduleId, List<VerseRef> refs) {
  final lines = <String>[];
  for (final r in refs) {
    final v = StudyData.verse(moduleId, r);
    if (v != null) lines.add(refs.length > 1 ? '${r.verse} ${plainOf(v)}' : plainOf(v));
  }
  return lines.join('\n');
}

String _norm(String w) => w.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Части второго текста с пометкой «отличается» от первого (наибольшая общая подпоследовательность по словам)
List<(String, bool)> diffWords(String base, String other) {
  final a = base.split(RegExp(r'\s+')).where((x) => x.trim().isNotEmpty).map(_norm).toList();
  final tokens = RegExp(r'\s+|\S+').allMatches(other).map((m) => m.group(0)!).toList();
  final b = tokens.where((x) => x.trim().isNotEmpty).toList();
  final bn = b.map(_norm).toList();
  final n = a.length, m = bn.length;
  if (m == 0) return [(other, false)];
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == bn[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] > dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final same = List<bool>.filled(m, false);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == bn[j]) {
      same[j] = true;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  final out = <(String, bool)>[];
  var k = 0;
  for (final p in tokens) {
    if (p.trim().isEmpty) {
      out.add((p, false));
    } else {
      out.add((p, !same[k++] && _norm(p).isNotEmpty));
    }
  }
  return out;
}

const _langOrder = ['ru', 'en', 'zh', 'hi', 'es', 'ar', 'fr', 'pt', 'id', 'de', 'ja', 'tr', 'sw', 'vi', 'tl', 'ko', 'fa', 'it', 'pl', 'uk', 'ro', 'nl', 'el', 'sv', 'cs', 'sr', 'sq', 'hy', 'hr', 'da', 'nb', 'be', 'eo', 'he', 'grc', 'la', 'cu', 'syr'];
const _langRu = {
  'ru': 'Русский', 'en': 'English', 'zh': 'Китайский', 'hi': 'Хинди', 'es': 'Испанский', 'ar': 'Арабский', 'fr': 'Французский', 'pt': 'Португальский',
  'id': 'Индонезийский', 'de': 'Немецкий', 'ja': 'Японский', 'tr': 'Турецкий', 'sw': 'Суахили', 'vi': 'Вьетнамский', 'tl': 'Тагальский', 'ko': 'Корейский',
  'fa': 'Персидский', 'it': 'Итальянский', 'pl': 'Польский', 'uk': 'Українська', 'ro': 'Румынский', 'nl': 'Нидерландский', 'el': 'Новогреческий',
  'sv': 'Шведский', 'cs': 'Чешский', 'sr': 'Сербский', 'sq': 'Албанский', 'hy': 'Армянский', 'hr': 'Хорватский', 'da': 'Датский', 'nb': 'Норвежский',
  'be': 'Белорусский', 'eo': 'Эсперанто', 'he': 'Иврит', 'grc': 'Греческий', 'la': 'Латынь', 'cu': 'Церковнославянский', 'syr': 'Сирийский',
};
int _langRank(String c) => _langOrder.contains(c) ? _langOrder.indexOf(c) : _langOrder.length + (c.isEmpty ? 1 : 0);
String _langName(String c) {
  if (c.isEmpty) return t('Другие');
  if (currentLang != 'ru') {
    final l = langs.where((x) => x.code == c).firstOrNull;
    if (l != null) return l.name;
    return c.toUpperCase();
  }
  return _langRu[c] ?? c.toUpperCase();
}

class CompareSheet extends ConsumerStatefulWidget {
  const CompareSheet({super.key, required this.refs, required this.moduleId});
  final List<VerseRef> refs;
  final String moduleId;
  @override
  ConsumerState<CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends ConsumerState<CompareSheet> {
  String _lang = 'all';
  Map<String, String>? _texts;
  late final List<InstalledModule> _ordered;

  @override
  void initState() {
    super.initState();
    // Переводы (без оригиналов и служебных модулей подстрочника); открытый — первым
    final bibles = ModuleStore.instance.bibles.where((b) => b.features['helper'] != true && b.features['interlinear'] != true && b.id != 'oshb' && b.id != 'byz-rp2018').toList();
    final current = bibles.where((b) => b.id == widget.moduleId).firstOrNull;
    _ordered = [?current, ...bibles.where((b) => b.id != widget.moduleId)];
    Future(() {
      final texts = {for (final b in _ordered) b.id: _selectionText(b.id, widget.refs)};
      if (mounted) setState(() => _texts = texts);
    });
  }

  void _parallel(InstalledModule b) {
    final r = widget.refs.first;
    if (!bookList(b.id).any((x) => x['id'] == r.book)) {
      Hub.toast(t('В переводе {module} нет книги «{book}»', {'module': b.name, 'book': Books.instance.meta(r.book).name}));
      return;
    }
    final panes = ref.read(panesProvider);
    final from = paneOf(panes, widget.moduleId);
    final n = ref.read(panesProvider.notifier);
    if (panes.length < 2) {
      n.toggleSplit(moduleId: b.id);
      n.navigate(1, r);
    } else {
      final target = from == 0 ? 1 : 0;
      n.setModule(target, b.id);
      n.navigate(target, r);
    }
    closeAllSheets(context);
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final others = _ordered.where((b) => b.id != widget.moduleId).toList();
    final current = _ordered.where((b) => b.id == widget.moduleId).firstOrNull;
    final langCodes = {for (final b in _ordered) b.language}.toList()..sort((a, b) => _langRank(a).compareTo(_langRank(b)));
    final shown = _ordered.where((b) => b.id == widget.moduleId || _lang == 'all' || b.language == _lang).toList();
    final texts = _texts;
    final pane = paneOf(ref.read(panesProvider), widget.moduleId);
    final children = <Widget>[];
    if (others.isEmpty) {
      children.add(Empty(
        icon: Icons.local_library_outlined,
        title: t('Другой перевод не установлен'),
        child: Column(children: [
          Text(t('Установите ещё один перевод из каталога.')),
          if (Hub.openLibrary != null)
            TextButton(
              onPressed: () {
                closeAllSheets(context);
                Hub.openLibrary!(context, ref, pane);
              },
              child: Text(t('Открыть каталог')),
            ),
        ]),
      ));
    }
    if (texts == null) {
      children.add(Loading(t('Загрузка…')));
    } else {
      if (langCodes.length > 1) {
        children.add(ChipWrap([
          for (final c in ['all', ...langCodes]) Chip2(c == 'all' ? t('Все языки') : _langName(c), on: _lang == c, onTap: () => setState(() => _lang = c)),
        ]));
      }
      for (final b in shown) {
        final tx = texts[b.id] ?? '';
        final isCur = b.id == widget.moduleId;
        Widget text;
        if (tx.isEmpty) {
          text = Text(t('В этом переводе нет такого места.'), style: TextStyle(color: pal.muted, fontSize: 16.3, height: 1.5));
        } else if (!isCur && current != null && (texts[widget.moduleId] ?? '').isNotEmpty && b.language == current.language) {
          text = Text.rich(
            TextSpan(children: [
              for (final (s, d) in diffWords(texts[widget.moduleId]!, tx))
                TextSpan(text: s, style: d ? TextStyle(backgroundColor: pal.accent.withValues(alpha: 0.22)) : null),
            ]),
            style: const TextStyle(fontSize: 16.3, height: 1.5),
          );
        } else {
          text = Text(tx, style: const TextStyle(fontSize: 16.3, height: 1.5));
        }
        children.add(Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(child: Text(isCur ? t('открыт сейчас') : b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 13.6))),
              if (!isCur) IconButton(icon: Icon(Icons.view_column_outlined, color: pal.accent), tooltip: t('Читать параллельно'), onPressed: () => _parallel(b)),
            ]),
            text,
          ]),
        ));
      }
      if (Hub.openLibrary != null) {
        children.add(BigButton(t('Другие переводы'), icon: Icons.local_library_outlined, onTap: () {
          closeAllSheets(context);
          Hub.openLibrary!(context, ref, pane);
        }));
      }
    }
    return SheetScaffold(title: t('Сравнение переводов'), subtitle: selectionLabel(widget.refs, full: true), body: SheetList(gap: 8, children: children));
  }
}

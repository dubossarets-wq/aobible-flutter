// Сравнение выделенных стихов во всех установленных переводах (CompareSheet.jsx). Слова, которыми перевод
// отличается от открытого, подсвечены. У каждого перевода — кнопка «Параллельно»: экран делится, в другой
// панели открывается этот перевод на том же месте.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bible.dart';
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../shell/fonts.dart' show readerTextStyle;
import '../../ui/kit.dart';
import '../hub.dart';
import 'interlinear.dart';
import 'sheet.dart';
import 'study_data.dart';
import '../../ui/ios_style.dart';

/// pick — «Читать параллельно» (CompareSheet pick): то же окно с заголовком «Читать параллельно», ниже; pane — откуда открыли
Future<void> openCompare(BuildContext context, WidgetRef ref, List<VerseRef> refs, String moduleId, {bool pick = false, int? pane}) {
  final sorted = [...refs]..sort((a, b) {
      final c = Books.instance.order(a.book).compareTo(Books.instance.order(b.book));
      if (c != 0) return c;
      return a.chapter != b.chapter ? a.chapter.compareTo(b.chapter) : a.verse.compareTo(b.verse);
    });
  return showSheet(context, CompareSheet(refs: sorted, moduleId: moduleId, pick: pick, pane: pane), size: pick ? SheetSize.normal : SheetSize.tall);
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

/// Текст с подсвеченными отличиями (mark.diff: #f2a65a 38 %, скругление 3, поля 1 px по бокам) — плашки рисуем
/// под текстом по границам слов, как в вебе: у фона TextSpan скруглений не бывает
class DiffText extends StatefulWidget {
  const DiffText({super.key, required this.parts, required this.style});
  final List<(String, bool)> parts;
  final TextStyle style;
  @override
  State<DiffText> createState() => _DiffTextState();
}

class _DiffTextState extends State<DiffText> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final ranges = <(int, int)>[];
    var at = 0;
    for (final (s, d) in widget.parts) {
      if (d) ranges.add((at, at + s.length));
      at += s.length;
    }
    return CustomPaint(
      painter: _DiffPainter(_key, ranges),
      child: Text.rich(key: _key, TextSpan(children: [for (final (s, _) in widget.parts) TextSpan(text: s)]), style: widget.style),
    );
  }
}

class _DiffPainter extends CustomPainter {
  _DiffPainter(this.key, this.ranges);
  final GlobalKey key;
  final List<(int, int)> ranges;

  @override
  void paint(Canvas canvas, Size size) {
    final rp = key.currentContext?.findRenderObject();
    if (rp is! RenderParagraph || !rp.hasSize) return;
    final paint = Paint()..color = const Color(0x61F2A65A);
    for (final (a, b) in ranges) {
      try {
        for (final x in rp.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b))) {
          final r = x.toRect();
          if (r.width < 1) continue;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(r.left - 1, r.top, r.right + 1, r.bottom), const Radius.circular(3)), paint);
        }
      } catch (_) {}
    }
  }

  @override
  bool shouldRepaint(_DiffPainter old) => old.ranges != ranges || old.key != key;
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
  const CompareSheet({super.key, required this.refs, required this.moduleId, this.pick = false, this.pane});
  final List<VerseRef> refs;
  final String moduleId;
  final bool pick;
  final int? pane;
  @override
  ConsumerState<CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends ConsumerState<CompareSheet> {
  String _lang = 'all';
  Map<String, String>? _texts;
  late final List<InstalledModule> _ordered;
  final _diffs = <String, List<(String, bool)>>{}; // разница с открытым переводом считается один раз (иначе — на каждое нажатие плашки языка)

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
    final from = widget.pane ?? paneOf(panes, widget.moduleId);
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
    final pane = widget.pane ?? paneOf(ref.read(panesProvider), widget.moduleId);
    final font = readerTextStyle(ref.watch(settingsProvider), size: 16.32, weight: 400).copyWith(height: 1.5); // .cmp-text: --font-text
    final children = <Widget>[];
    if (others.isEmpty) {
      children.add(Empty(
        icon: LucideIcons.library,
        title: t('Другой перевод не установлен'),
        child: Column(children: [
          Text(t('Установите ещё один перевод из каталога.')),
          if (Hub.openLibrary != null)
            LinkButton(t('Открыть каталог'), () {
              closeAllSheets(context);
              Hub.openLibrary!(context, ref, pane);
            }),
        ]),
      ));
    }
    if (texts == null) {
      children.add(Loading(t('Загрузка…')));
    } else {
      if (langCodes.length > 1) {
        children.add(Transform.translate(
          offset: const Offset(0, -4), // .lang-chips { margin-top: -4px }
          child: FilterChips([
            for (final c in ['all', ...langCodes]) Chip2(c == 'all' ? t('Все языки') : _langName(c), on: _lang == c, onTap: () => setState(() => _lang = c)),
          ]),
        ));
      }
      final cmpItems = <Widget>[]; // .cmp-list: без промежутков между переводами
      for (final b in shown) {
        final tx = texts[b.id] ?? '';
        final isCur = b.id == widget.moduleId;
        Widget text;
        if (tx.isEmpty) {
          text = Text(t('В этом переводе нет такого места.'), style: TextStyle(color: pal.muted, fontSize: 16.32, height: 1.5));
        } else if (!isCur && current != null && (texts[widget.moduleId] ?? '').isNotEmpty && b.language == current.language) {
          text = DiffText(parts: _diffs[b.id] ??= diffWords(texts[widget.moduleId]!, tx), style: font);
        } else {
          text = Text(tx, style: font);
        }
        // .cmp-item: отступ 12 сверху и снизу (у первого сверху 2), строка 4 px между шапкой и текстом;
        // линия — от края до края окна, отступ 20 — у содержимого (справа 11: значок 20 в кнопке 38 — на 20 от края)
        // стиль iPhone: переводы — частями карточки группы
        cmpItems.add((iosUiNow ? (Widget w) => IosCardItem(pal: pal, first: b == shown.first, last: b == shown.last, indent: iosHeaderLeft, child: w) : bleed)(Container(
          padding: iosUiNow ? EdgeInsets.fromLTRB(iosHeaderLeft, 10, 11, 12) : EdgeInsets.fromLTRB(20, b == shown.first ? 2 : 12, 11, 12),
          decoration: iosUiNow ? null : BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(children: [
                Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Expanded(child: Text(isCur ? t('открыт сейчас') : b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 13.6))),
                if (!isCur) IconBtn(icon: LucideIcons.columns2, size: 20, color: pal.accent, tooltip: t('Читать параллельно'), onTap: () => _parallel(b)),
              ]),
            ),
            const SizedBox(height: 4),
            text,
          ]),
        )));
      }
      children.add(Column(children: cmpItems));
      if (Hub.openLibrary != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4), // .cmp-more
          child: BigButton(t('Другие переводы'), icon: LucideIcons.library, onTap: () {
            closeAllSheets(context);
            Hub.openLibrary!(context, ref, pane);
          }),
        ));
      }
    }
    return SheetScaffold(title: widget.pick ? t('Читать параллельно') : t('Сравнение переводов'), subtitle: selectionLabel(widget.refs, full: true), body: SheetList(children: children));
  }
}

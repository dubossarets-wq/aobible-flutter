// Тексты и подписи стихов (общие для планов и проповедей): как selectionLabel/quoteVerse в веб-версии (SelectionBar.jsx).
import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/markup.dart';
import '../../core/modules.dart';

/// Текст стиха из модуля без разметки; null — такого стиха (или модуля) нет
String? verseText(String moduleId, VerseRef r) {
  try {
    if (ModuleStore.instance.get(moduleId) == null) return null;
    final rows = ModuleStore.instance.db(moduleId).select('SELECT text FROM verses WHERE book = ? AND chapter = ? AND verse = ?', [r.book, r.chapter, r.verse]);
    return rows.isEmpty ? null : plainText(rows.first['text'] as String);
  } catch (_) {
    return null;
  }
}

/// «Ин. 3:16», «Ин. 3:16–18», «Ин. 3:16, 18»; full — с полным названием книги
String selectionLabel(List<VerseRef> refs, {bool full = false}) {
  if (refs.isEmpty) return '';
  final b = Books.instance;
  final first = refs.first;
  if (refs.length == 1) return b.formatRef(first.book, first.chapter, first.verse, full: full);
  final same = refs.every((r) => r.book == first.book && r.chapter == first.chapter);
  if (same) {
    final vs = [for (final r in refs) r.verse];
    var contiguous = true;
    for (var i = 1; i < vs.length; i++) {
      if (vs[i] != vs[i - 1] + 1) contiguous = false;
    }
    final m = b.meta(first.book);
    return '${full ? m.name : m.short} ${first.chapter}:${contiguous ? '${vs.first}–${vs.last}' : vs.join(', ')}';
  }
  return refs.map((r) => b.formatRef(r.book, r.chapter, r.verse, full: full)).join('; ');
}

/// Единый формат копирования и «Поделиться»: "Текст стиха" - Ин. 3:16 (диапазон через обычный дефис)
String quoteLabel(List<VerseRef> refs) => selectionLabel(refs).replaceAll('–', '-');
String quoteVerse(String text, String label) => '"${text.replaceAll(RegExp(r'\s+'), ' ').trim()}" - $label';

/// Переводы для стиха дня и виджета: перевод первой панели, основной из настроек, затем любые установленные —
/// но только на языке приложения (читают греческий текст — стих дня всё равно по-русски); другие языки — лишь если
/// на языке приложения не установлено ни одного перевода
List<InstalledModule> verseModules(String? paneModule, String primary) {
  final store = ModuleStore.instance;
  final ids = <String>{?paneModule, primary, for (final m in store.bibles) m.id};
  final all = [for (final id in ids) if (store.get(id) != null && store.get(id)!.type == 'bible') store.get(id)!];
  final own = [for (final m in all) if (m.language == currentLang) m];
  return own.isEmpty ? all : own;
}

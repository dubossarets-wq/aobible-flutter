// Библиотека модулей: вкладка «Импорт» (ModuleImporter.jsx), «Источник каталога» (Fold), переключатель модуля со свайпом
// (.row-switch + useSwipeToggle). Файлы выбираются через file_picker; в тестах выбор подменяется pickModuleFiles.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'colors.dart';
import 'library_sheet.dart' show fmtSize, moduleTypeNames;
import 'module_import.dart';
import 'sheet.dart';
import '../../ui/ios_style.dart';

/// Выбор файлов модулей: (имя, содержимое). По умолчанию — окно выбора файлов системы; тесты подменяют
Future<List<(String, Uint8List)>> Function() pickModuleFiles = () async {
  final files = await FilePicker.pickFiles();
  return [for (final f in files) (f.name, await f.readAsBytes())];
};

/// Пример файла модуля — образец формата, не переводится
const moduleSample = '''{
  "format": "aob-module",
  "formatVersion": 1,
  "type": "dictionary",
  "dictionaryKind": "words",
  "id": "my-dictionary",
  "name": "Мой словарь",
  "language": "ru",
  "license": "CC BY 4.0",
  "entries": {
    "агнец": {
      "word": "Агнец",
      "text": "Ягнёнок; жертвенное животное…",
      "refs": ["John.1.29", "Rev.5.6"]
    }
  }
}''';

String fmtNum(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(currentLang == 'ru' ? ' ' : ',');
    b.write(s[i]);
  }
  return b.toString();
}

Color okColor(Palette p) => p.dark ? const Color(0xff7cc68a) : const Color(0xff2f6339);
Color dangerColor(Palette p) => p.dark ? const Color(0xffef8a78) : const Color(0xffb4412f);

/// Фраза с подстановками, у которых свой вид (в веб-версии — JSX-вставки с классом mono)
Widget phraseWith(String key, Map<String, String> mono, TextStyle style, TextStyle monoStyle) {
  final raw = t(key);
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in RegExp(r'\{(\w+)\}').allMatches(raw)) {
    spans.add(TextSpan(text: raw.substring(at, m.start)));
    final v = mono[m.group(1)];
    spans.add(TextSpan(text: v ?? m.group(0), style: v == null ? null : monoStyle));
    at = m.end;
  }
  spans.add(TextSpan(text: raw.substring(at)));
  return Text.rich(TextSpan(children: spans), style: style);
}

class _Item {
  _Item(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  String state = 'reading'; // reading | ready | error | installing | done
  double p = 0;
  String label = '';
  ImportPreview? preview;
  String? error;
}

/// Вкладка «Импорт»: выбрать файлы, проверить, установить
class ImportTab extends ConsumerStatefulWidget {
  const ImportTab({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  ConsumerState<ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends ConsumerState<ImportTab> {
  final List<_Item> _items = [];
  bool _fold = false;

  Future<void> _pick() async {
    List<(String, Uint8List)> files;
    try {
      files = await pickModuleFiles();
    } catch (e) {
      if (mounted) toast(context, t('Не удалось прочитать файл: {error}', {'error': '$e'}));
      return;
    }
    for (final (name, bytes) in files) {
      final it = _Item(name, bytes)..label = t('Чтение…');
      if (!mounted) return;
      setState(() => _items.add(it));
      try {
        final pv = await ModuleStore.instance.previewImport(bytes, name);
        pv.meta['size'] = bytes.length;
        if (mounted) setState(() => it..state = 'ready'..preview = pv..p = 0.5);
      } catch (e) {
        if (mounted) setState(() => it..state = 'error'..error = e is ModuleError ? e.message : '$e');
      }
    }
  }

  Future<void> _copySample() async {
    await Clipboard.setData(const ClipboardData(text: moduleSample));
    if (mounted) toast(context, t('Пример скопирован'));
  }

  Future<void> _install(_Item it) async {
    setState(() => it..state = 'installing'..p = 0.5..label = t('Установка…'));
    try {
      await ModuleStore.instance.installPreview(it.preview!, onProgress: (p, l) {
        if (mounted) setState(() => it..p = 0.5 + p * 0.5..label = t(l));
      });
      if (!mounted) return;
      setState(() => it.state = 'done');
      toast(context, t('{name} установлен', {'name': '${it.preview!.meta['name']}'}));
    } catch (e) {
      if (mounted) setState(() => it..state = 'error'..error = t('Не удалось сохранить: {error}', {'error': '$e'}));
    }
  }

  String _stats(Map<String, dynamic> m) {
    final s = (m['stats'] as Map?) ?? const {};
    return switch (m['type']) {
      'bible' => ' · ${t('{books} кн., {verses} стихов', {'books': '${s['books']}', 'verses': fmtNum(s['verses'] as int? ?? 0)})}${(m['features'] as Map?)?['strongs'] == true ? ', ${t('есть номера Стронга')}' : ''}',
      'dictionary' => ' · ${t('{n} статей', {'n': fmtNum(s['entries'] as int? ?? 0)})}',
      'crossrefs' => ' · ${t('ссылки для {n} стихов', {'n': fmtNum(s['verses'] as int? ?? 0)})}',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    final store = ModuleStore.instance;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5);
    final children = <Widget>[
      // .dropzone: пунктирная рамка, значок, подпись и кнопка (перетаскивать на телефоне нечего — только выбор)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        decoration: BoxDecoration(border: Border.all(color: pal.line, width: 2), borderRadius: BorderRadius.circular(kRadius)),
        child: Column(children: [
          Icon(ico(LucideIcons.upload), size: 26, color: pal.muted),
          const SizedBox(height: 10),
          Text(t('Перетащите JSON-файлы сюда или'), textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
          const SizedBox(height: 10),
          AobButton(kind: BtnKind.primary, label: t('Выбрать файлы'), onTap: _pick),
          const SizedBox(height: 10),
          Text(t('Переводы, словари, параллельные места · .json или .json.gz'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13.1, color: pal.muted, height: 1.4)),
        ]),
      ),
      for (final it in _items) _card(it, pal, store),
      // Fold «Формат модуля»
      LibFold(
        title: t('Формат модуля'),
        open: _fold,
        onToggle: () => setState(() => _fold = !_fold),
        children: [
          phraseWith(
            'Родной формат — {native} (описание: docs/MODULE_SCHEMA.md в проекте). Также принимаются массив книг с полем {chapters}, список стихов {verses}, словарь {dict} и список статей {entries}.',
            const {'native': 'aob-module', 'chapters': 'chapters', 'verses': '{book, chapter, verse, text}', 'dict': '{"H1": {...}}', 'entries': '[{word, definition}]'},
            TextStyle(fontSize: 13.1, color: pal.muted, height: 1.4),
            mono.copyWith(color: pal.muted),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: (iosUiNow ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius * 0.6)) : BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius * 0.75))),
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Text(moduleSample, style: mono.copyWith(fontSize: 12.5, height: 1.45, color: pal.text))),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: AobButton(
              block: true,
              small: true,
              icon: LucideIcons.copy,
              label: t('Скопировать пример'),
              onTap: _copySample,
            ),
          ),
        ],
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
    ]);
  }

  /// .mod-card: имя файла, прогресс, сведения о модуле, предупреждения и действия
  Widget _card(_Item it, Palette pal, ModuleStore store) {
    final m = it.preview?.meta;
    final exists = m != null && store.get(m['id'] as String) != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: (iosUiNow ? iosShape(iosCardAt(pal, IosElevated.of(context)), BorderRadius.circular(iosRadius)) : BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(ico(LucideIcons.fileJson), size: 18, color: pal.accent),
          const SizedBox(width: 8),
          Flexible(child: Text('${m?['name'] ?? it.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
        ]),
        const SizedBox(height: 2),
        Text('${it.name} · ${fmtSize(it.bytes.length)}', style: TextStyle(fontSize: 13.1, color: pal.muted)),
        if (it.state == 'reading' || it.state == 'installing') ...[const SizedBox(height: 8), AobProgress(value: it.p, label: it.label)],
        if (it.state == 'error') ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(ico(LucideIcons.triangleAlert), size: 15, color: dangerColor(pal))),
            const SizedBox(width: 6),
            Expanded(child: Text(it.error ?? '', style: TextStyle(color: dangerColor(pal), height: 1.4))),
          ]),
        ],
        if (m != null && it.state != 'error') ...[
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${t('Тип: {type}', {'type': t(moduleTypeNames[m['type']] ?? '${m['type']}')})}${m['dictionaryKind'] != null ? ' (${m['dictionaryKind'] == 'strongs' ? t('по номерам Стронга') : t('по словам')})' : ''} · id: '),
              TextSpan(text: '${m['id']}', style: const TextStyle(fontFamily: 'monospace')),
              TextSpan(text: _stats(m)),
              TextSpan(text: '\n${t('Лицензия: {license}', {'license': '${m['license']}'})}'),
            ]),
            style: TextStyle(fontSize: 13.1, color: pal.muted, height: 1.45),
          ),
          if (it.preview!.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in it.preview!.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(ico(LucideIcons.triangleAlert), size: 13, color: pal.muted)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w, style: TextStyle(fontSize: 13.6, color: pal.muted, height: 1.35))),
                ]),
              ),
          ],
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (it.state == 'ready') AobButton(small: true, kind: BtnKind.primary, label: exists ? t('Заменить установленный') : t('Установить'), onTap: () => _install(it)),
          if (it.state == 'done') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: okColor(pal).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ico(LucideIcons.circleCheck), size: 13, color: okColor(pal)),
                const SizedBox(width: 4),
                Text(t('Установлен'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: okColor(pal))),
              ]),
            ),
            AobButton(small: true, label: t('К установленным'), onTap: widget.onDone),
          ],
          if (it.state != 'installing' && it.state != 'done') AobButton(small: true, label: t('Убрать'), onTap: () => setState(() => _items.remove(it))),
        ]),
      ]),
    );
  }
}

/// Раскрывающийся блок (Fold в ui.jsx): строка с шевроном, линия сверху
class LibFold extends ConsumerWidget {
  const LibFold({super.key, required this.title, required this.open, required this.onToggle, required this.children});
  final String title;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = effectivePalette(ref.watch(settingsProvider));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: onToggle,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
          child: Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 14.25, fontWeight: FontWeight.w600, color: open ? pal.text : pal.muted))),
            AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: Icon(ico(LucideIcons.chevronDown), size: 17, color: open ? pal.text : pal.muted)),
          ]),
        ),
      ),
      Reveal(
        open: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in children) Padding(padding: const EdgeInsets.only(top: 10), child: c),
        ]),
      ),
    ]);
  }
}

/// Переключатель в строке модуля: нажатие или свайп вбок (бегунок едет за пальцем, отпустили — встал на ближайшее место)
class RowSwitch extends StatefulWidget {
  const RowSwitch({super.key, required this.value, required this.onChanged, this.tip});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? tip;
  @override
  State<RowSwitch> createState() => _RowSwitchState();
}

class _RowSwitchState extends State<RowSwitch> {
  static const _thumb = 18.0; // ход бегунка
  double? _pos;

  @override
  Widget build(BuildContext context) {
    final on = _pos != null ? _pos! > _thumb / 2 : widget.value;
    return Tooltip(
      message: widget.tip ?? '',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        onHorizontalDragStart: (_) => _pos = widget.value ? _thumb : 0,
        onHorizontalDragUpdate: (d) => setState(() => _pos = ((_pos ?? 0) + d.delta.dx).clamp(0, _thumb)),
        onHorizontalDragEnd: (_) {
          final next = (_pos ?? 0) > _thumb / 2;
          setState(() => _pos = null);
          if (next != widget.value) widget.onChanged(next);
        },
        onHorizontalDragCancel: () => setState(() => _pos = null),
        child: SizedBox(width: 56, height: 44, child: Center(child: AobSwitch(value: on, onChanged: null))),
      ),
    );
  }
}

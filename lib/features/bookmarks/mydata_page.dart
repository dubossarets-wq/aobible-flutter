// Окно «Мои данные» (PrefsSheet.jsx → MyData, VersionsSheet.jsx → резервные копии):
// сохранить всё в файл, восстановить из файла, вернуть данные из копии.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../ui/kit.dart';
import '../shell/tour_targets.dart' show tourKey;
import 'ui.dart';
import 'userdata.dart';

void openMyData(BuildContext context, WidgetRef ref, int pane) {
  showAobSheet<void>(context, builder: (_) => const MyDataPage());
}

class MyDataPage extends ConsumerStatefulWidget {
  const MyDataPage({super.key});
  @override
  ConsumerState<MyDataPage> createState() => _MyDataPageState();
}

class _MyDataPageState extends ConsumerState<MyDataPage> {
  Map<String, dynamic>? _pending; // файл, который собираются восстановить
  String? _error;
  List<BackupInfo> _backups = listBackups();

  Future<void> _save() async {
    try {
      final d = DateTime.now();
      final name = '${t('AO Bible — мои данные')} ${two(d.day)}-${two(d.month)}-${d.year}.json';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(jsonEncode(exportData()), flush: true);
      final r = await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], title: t('AO Bible — мои данные')));
      if (mounted && r.status != ShareResultStatus.dismissed) toast(context, t('Файл сохранён'));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final f = await FilePicker.pickFile();
      if (f == null) return;
      final json = parseDataFile(utf8.decode(await f.readAsBytes()));
      if (mounted) setState(() => _pending = json);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = t('Это не файл с данными AO Bible.'));
    }
  }

  Future<void> _restore(bool Function() run) async {
    final ok = run();
    if (ok) await reloadAfterReplace(ref);
    if (!mounted) return;
    setState(() {
      _pending = null;
      _backups = listBackups();
    });
    if (!ok) toast(context, t('Не удалось сохранить: {error}', {'error': '—'}));
  }

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    final p = _pending;
    final d = p == null ? null : describeData(p);
    final counts = {if (d != null) for (final e in d.entries) if (e.key != 'at') e.key: '${e.value}'};
    // .pref-note: 0,92rem, межстрочный 1,5, серый
    TextStyle note() => TextStyle(fontSize: 14.7, height: 1.5, color: pal.muted);

    // .pref-btns: кнопки в ряд, у каждой не уже 180 px — на узком экране переносятся
    Widget btns(List<Widget> children, {Key? key}) => LayoutBuilder(
          builder: (_, c) {
            final two = c.maxWidth >= 2 * 180 + 8;
            return Wrap(key: key, spacing: 8, runSpacing: 8, children: [for (final w in children) SizedBox(width: two ? (c.maxWidth - 8) / 2 : c.maxWidth, child: w)]);
          },
        );

    // Свой ScaffoldMessenger/Scaffold: «Файл сохранён» должно быть видно поверх окна
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AobSheet(
          title: t('Мои данные'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Закладки, заметки, любимые стихи, выделения, планы, проповеди и настройки — в одном файле. Чтобы ничего не потерять или перейти на новый телефон.'), style: note()),
            const SizedBox(height: 10),
            btns([
              AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.download, label: t('Сохранить в файл'), onTap: _save),
              AobButton(wide: true, icon: LucideIcons.upload, label: t('Восстановить из файла'), onTap: _pick),
            ], key: tourKey('pref-btns')), // цель инструкции
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(fontSize: 15, height: 1.4, color: Color(0xffb4412f)))),
            if (d != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    d['at'] != null
                        ? t('В файле от {date}: закладок {bookmarks}, заметок {notes}, любимых стихов {favorites}, выделений {highlights}, планов {plans}, проповедей {sermons}.', {...counts, 'date': fmtDate((d['at'] as DateTime).millisecondsSinceEpoch, year: true)})
                        : t('В файле: закладок {bookmarks}, заметок {notes}, любимых стихов {favorites}, выделений {highlights}, планов {plans}, проповедей {sermons}.', counts),
                    style: TextStyle(fontSize: 14.7, height: 1.4, color: pal.text),
                  ),
                  const SizedBox(height: 8),
                  Text(t('Всё на телефоне заменится данными из файла. Нынешнее останется в резервной копии («Версии приложения»).'), style: note()),
                  const SizedBox(height: 10),
                  btns([
                    AobButton(kind: BtnKind.primary, wide: true, label: t('Восстановить'), onTap: () => _restore(() => importData(p!))),
                    AobButton(wide: true, label: t('Отмена'), onTap: () => setState(() => _pending = null)),
                  ]),
                ]),
              ),
            const SizedBox(height: 20),
            // «Резервные копии» — раздел окна «Версии приложения» (VersionsSheet.jsx), здесь рядом с файлом
            GroupTitle(t('Резервные копии')),
            Text(t('Настройки, закладки, заметки и любимые стихи сохраняются перед каждым обновлением (последние 5 копий).'), style: TextStyle(fontSize: 13.1, height: 1.4, color: pal.muted)),
            const SizedBox(height: 8),
            if (_backups.isEmpty) Text(t('Копий пока нет — первая появится при следующем обновлении.'), style: TextStyle(fontSize: 13.1, height: 1.4, color: pal.muted)),
            for (final b in _backups)
              // .version: рамка, скругление, отступы 10/14, фон bg
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: pal.bg, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(kRadius)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtDate(b.at, year: true), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
                  const SizedBox(height: 6),
                  Text('${reasonLabel(b.reason)} · ${t('закладок {bookmarks}, заметок {notes}, любимых {favorites}', {'bookmarks': '${b.bookmarks}', 'notes': '${b.notes}', 'favorites': '${b.favorites}'})}', style: TextStyle(fontSize: 14.4, height: 1.4, color: pal.muted)),
                  const SizedBox(height: 6),
                  ConfirmButton(small: true, icon: LucideIcons.rotateCcw, label: t('Восстановить эту копию'), confirmLabel: t('Восстановить'), onConfirm: () => _restore(() => restoreBackup(b.at))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

// Страница «Мои данные» (PrefsSheet.jsx → MyData, VersionsSheet.jsx → резервные копии):
// сохранить всё в файл, восстановить из файла, вернуть данные из копии.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'ui.dart';
import 'userdata.dart';

void openMyData(BuildContext context, WidgetRef ref, int pane) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyDataPage()));
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
    final pal = ref.watch(settingsProvider).palette;
    final p = _pending;
    final d = p == null ? null : describeData(p);
    final counts = {if (d != null) for (final e in d.entries) if (e.key != 'at') e.key: '${e.value}'};
    TextStyle note() => TextStyle(color: pal.muted, height: 1.4);
    Widget btn(IconData i, String label, VoidCallback f, {bool primary = false}) => primary
        ? FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: pal.accent, foregroundColor: pal.onAccent), onPressed: f, icon: Icon(i, size: 18), label: Text(label))
        : OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: pal.text, side: BorderSide(color: pal.line)), onPressed: f, icon: Icon(i, size: 18), label: Text(label));

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bar, foregroundColor: pal.barText, title: Text(t('Мои данные'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(t('Закладки, заметки, любимые стихи, выделения, планы, проповеди и настройки — в одном файле. Чтобы ничего не потерять или перейти на новый телефон.'), style: note()),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          btn(Icons.download_outlined, t('Сохранить в файл'), _save, primary: true),
          btn(Icons.upload_outlined, t('Восстановить из файла'), _pick),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (d != null)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: pal.panel, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                d['at'] != null
                    ? t('В файле от {date}: закладок {bookmarks}, заметок {notes}, любимых стихов {favorites}, выделений {highlights}, планов {plans}, проповедей {sermons}.', {...counts, 'date': fmtDate((d['at'] as DateTime).millisecondsSinceEpoch, year: true)})
                    : t('В файле: закладок {bookmarks}, заметок {notes}, любимых стихов {favorites}, выделений {highlights}, планов {plans}, проповедей {sermons}.', counts),
                style: TextStyle(color: pal.text, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(t('Всё на телефоне заменится данными из файла. Нынешнее останется в резервной копии («Версии приложения»).'), style: note()),
              const SizedBox(height: 10),
              Row(children: [
                btn(Icons.restore, t('Восстановить'), () => _restore(() => importData(p!)), primary: true),
                const SizedBox(width: 10),
                btn(Icons.close, t('Отмена'), () => setState(() => _pending = null)),
              ]),
            ]),
          ),
        const SizedBox(height: 24),
        Text(t('Резервные копии'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: pal.text)),
        const SizedBox(height: 4),
        Text(t('Настройки, закладки, заметки и любимые стихи сохраняются перед каждым обновлением (последние 5 копий).'), style: note()),
        const SizedBox(height: 8),
        if (_backups.isEmpty) Text(t('Копий пока нет — первая появится при следующем обновлении.'), style: note()),
        for (final b in _backups)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: pal.panel, border: Border.all(color: pal.line), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtDate(b.at, year: true), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${reasonLabel(b.reason)} · ${t('закладок {bookmarks}, заметок {notes}, любимых {favorites}', {'bookmarks': '${b.bookmarks}', 'notes': '${b.notes}', 'favorites': '${b.favorites}'})}', style: note()),
              ),
              ConfirmButton(pal: pal, icon: Icons.restore, label: t('Восстановить эту копию'), confirmLabel: t('Восстановить'), onConfirm: () => _restore(() => restoreBackup(b.at))),
            ]),
          ),
      ]),
    );
  }
}

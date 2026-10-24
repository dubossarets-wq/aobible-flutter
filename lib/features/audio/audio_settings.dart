// Настройки → «Аудио»: книги, скачанные для прослушивания без интернета (PrefsSheet.jsx → OfflineList).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import 'audio_download.dart';
import 'audio_offline.dart';

void openAudioSettings(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AudioSettingsPage()));

class AudioSettingsPage extends ConsumerWidget {
  const AudioSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider).palette;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bar, foregroundColor: pal.barText, title: Text(t('Аудио'))),
      body: AudioOfflineList(pal: pal),
    );
  }
}

/// Список скачанных книг; его же можно вставить в экран настроек оболочки
class AudioOfflineList extends StatelessWidget {
  const AudioOfflineList({super.key, required this.pal});
  final Palette pal;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BookDownloads.I.version,
      builder: (_, _, _) {
        final items = OfflineAudio.list().entries.toList();
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Text(t('Пока ничего нет. Чтобы слушать без интернета, нажмите в проигрывателе стрелку вниз.'), style: TextStyle(color: pal.muted, fontSize: 14.5, height: 1.4)),
          );
        }
        final total = items.fold<int>(0, (a, e) => a + (((e.value as Map)['bytes'] as num?)?.toInt() ?? 0));
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Text(t('Скачано {n} кн. · {size} МБ', {'n': '${items.length}', 'size': (total / 1048576).toStringAsFixed(0)}), style: TextStyle(color: pal.muted, fontSize: 14.5)),
          ),
          for (final e in items) _row(context, e.key, (e.value as Map).cast<String, dynamic>()),
        ]);
      },
    );
  }

  Widget _row(BuildContext context, String key, Map<String, dynamic> v) {
    final p = key.split('|');
    final audioId = p[0], book = p[1];
    final name = Books.instance.meta(book).name;
    final mod = ModuleStore.instance.get(audioId);
    return ListTile(
      title: Text(name, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
      subtitle: Text('${mod?.name ?? audioId} · ${t('{n} МБ', {'n': (((v['bytes'] as num?) ?? 0) / 1048576).toStringAsFixed(0)})}', style: TextStyle(color: pal.muted)),
      trailing: IconButton(
        tooltip: t('Удалить скачанную книгу {book}', {'book': name}),
        icon: Icon(Icons.delete_outline, color: pal.muted),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              backgroundColor: pal.panel,
              title: Text(t('Удалить скачанную книгу {book}', {'book': name}), style: TextStyle(color: pal.text, fontSize: 17)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Отмена'))),
                TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('Удалить'))),
              ],
            ),
          );
          if (ok != true) return;
          await OfflineAudio.removeBook(audioId, book);
          BookDownloads.I.version.value++;
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Удалено из телефона: {book}', {'book': name}))));
        },
      ),
    );
  }
}

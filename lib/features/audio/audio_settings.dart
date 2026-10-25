// Настройки → «Аудио»: книги, скачанные для прослушивания без интернета (PrefsSheet.jsx → OfflineList).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/modules.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'audio_download.dart';
import 'audio_offline.dart';

/// Окно «Аудио» — нижний лист, как страницы настроек в веб-версии
Future<void> openAudioSettings(BuildContext context) => showAobSheet<void>(context, builder: (_) => const AudioSettingsPage());

class AudioSettingsPage extends ConsumerWidget {
  const AudioSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = paletteOf(ref);
    return AobSheet(
      title: t('Аудио'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GroupTitle(t('Книги без интернета')),
        AudioOfflineList(pal: pal),
      ]),
    );
  }
}

/// Список скачанных книг; его же можно вставить в экран настроек оболочки (внутри прокрутки окна)
class AudioOfflineList extends StatelessWidget {
  const AudioOfflineList({super.key, required this.pal});
  final Palette pal;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BookDownloads.I.version,
      builder: (_, _, _) {
        final items = OfflineAudio.list().entries.toList();
        // .pref-note: .92rem, строка 1,5, цвет muted, отступ снизу 10
        TextStyle note() => TextStyle(color: pal.muted, fontSize: 14.7, height: 1.5);
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(t('Пока ничего нет. Чтобы слушать без интернета, нажмите в проигрывателе стрелку вниз.'), style: note()),
          );
        }
        final total = items.fold<int>(0, (a, e) => a + (((e.value as Map)['bytes'] as num?)?.toInt() ?? 0));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(t('Скачано {n} кн. · {size} МБ', {'n': '${items.length}', 'size': (total / 1048576).toStringAsFixed(0)}), style: note()),
          ),
          for (final e in items) _OfflineRow(key: ValueKey(e.key), itemKey: e.key, v: (e.value as Map).cast<String, dynamic>(), pal: pal),
        ]);
      },
    );
  }
}

/// Строка списка (.pref-list li): название и мелкая подпись, корзина; нажатие на корзину — «Удалить» / «Отмена»
class _OfflineRow extends StatefulWidget {
  const _OfflineRow({super.key, required this.itemKey, required this.v, required this.pal});
  final String itemKey;
  final Map<String, dynamic> v;
  final Palette pal;
  @override
  State<_OfflineRow> createState() => _OfflineRowState();
}

class _OfflineRowState extends State<_OfflineRow> {
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final p = widget.itemKey.split('|');
    final audioId = p[0], book = p[1];
    final name = Books.instance.meta(book).name;
    final mod = ModuleStore.instance.get(audioId);
    final label = t('Удалить скачанную книгу {book}', {'book': name});
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
      child: Row(spacing: 8, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 15, color: pal.text)),
            Text('${mod?.name ?? audioId} · ${t('{n} МБ', {'n': (((widget.v['bytes'] as num?) ?? 0) / 1048576).toStringAsFixed(0)})}', style: TextStyle(fontSize: 12.5, color: pal.muted)),
          ]),
        ),
        if (_armed) ...[
          AobButton(
            label: t('Удалить'),
            kind: BtnKind.danger,
            onTap: () async {
              setState(() => _armed = false);
              await OfflineAudio.removeBook(audioId, book);
              BookDownloads.I.version.value++;
              Hub.toast(t('Удалено из телефона: {book}', {'book': name}));
            },
          ),
          AobButton(label: t('Отмена'), onTap: () => setState(() => _armed = false)),
        ] else
          IconBtn(icon: LucideIcons.trash2, subtle: true, size: 15, tooltip: label, onTap: () => setState(() => _armed = true)),
      ]),
    );
  }
}

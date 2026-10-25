// Скачивание звучащей книги для прослушивания без интернета: одно состояние на кнопку в мини-панели и в
// раскрытом проигрывателе (прогресс виден в обоих), подпись под панелью, список скачанного для настроек.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'audio_data.dart';
import 'audio_logic.dart';
import 'audio_offline.dart';

const greenOk = Color(0xFF2F9A5F);

String mb(int bytes) => t('{n} МБ', {'n': megabytes(bytes)});

class DlNote {
  const DlNote(this.text, {this.ok = false, this.remove});
  final String text;
  final bool ok;
  final Future<void> Function()? remove;
}

class BookDownloads {
  BookDownloads._();
  static final I = BookDownloads._();

  final note = ValueNotifier<DlNote?>(null);
  final progress = ValueNotifier<double?>(null); // доля 0..1 у скачивающейся книги
  final version = ValueNotifier<int>(0); // список скачанного изменился
  String? busy; // 'аудиомодуль|книга'
  CancelToken? _cancel;

  bool isBusy(String audioId, String book) => busy == '$audioId|$book';

  /// Нажатие на кнопку: скачать или (если уже скачана) показать подпись с «удалить»
  Future<void> click(String audioId, String book) async {
    final key = '$audioId|$book';
    if (busy != null) return;
    final name = Books.instance.meta(book).name;
    if (OfflineAudio.isBookOffline(audioId, book)) {
      note.value = DlNote(t('«{book}» в телефоне — слушайте без интернета', {'book': name}), ok: true, remove: () async {
        await OfflineAudio.removeBook(audioId, book);
        version.value++;
        note.value = null;
      });
      return;
    }
    final pack = await loadPack(audioId);
    if (pack == null) return;
    busy = key;
    _cancel = CancelToken();
    progress.value = 0;
    note.value = DlNote(t('Скачиваю «{book}»…', {'book': name}));
    try {
      final bytes = await OfflineAudio.downloadBook(pack, book, cancel: _cancel, onProgress: (done, total, b) {
        progress.value = done / total;
        note.value = DlNote(t('Скачиваю «{book}»: {done} из {total} · {size}', {'book': name, 'done': '$done', 'total': '$total', 'size': mb(b)}));
      });
      note.value = DlNote(t('«{book}» скачана ({size})', {'book': name, 'size': mb(bytes)}), ok: true);
    } catch (e) {
      note.value = DlNote(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      busy = null;
      _cancel = null;
      progress.value = null;
      version.value++;
    }
  }
}

/// Кнопка рядом с настройками. Во время загрузки — круг прогресса, после — зелёная галочка
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.audioId, required this.book, this.size = 19, required this.pal});
  final String audioId, book;
  final double size;
  final Palette pal;

  @override
  Widget build(BuildContext context) {
    final d = BookDownloads.I;
    return ListenableBuilder(
      listenable: Listenable.merge([d.progress, d.version]),
      builder: (_, _) {
        final offline = OfflineAudio.isBookOffline(audioId, book);
        final prog = d.isBusy(audioId, book) ? d.progress.value : null;
        final name = Books.instance.meta(book).name;
        return Semantics(
          button: true,
          label: offline ? t('{book} скачана для прослушивания без интернета', {'book': name}) : t('Скачать {book} для прослушивания без интернета', {'book': name}),
          child: Tooltip(
            message: offline ? t('Скачано') : t('Скачать книгу'),
            child: InkResponse(
              radius: 22,
              onTap: () => d.click(audioId, book),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(alignment: Alignment.center, children: [
                  // Кольцо загрузки — .dl-ring (inset 6 в кнопке 40 px, обводка 2,5 при 32 px)
                  if (prog != null) SizedBox(width: 26.5, height: 26.5, child: CircularProgressIndicator(value: prog, strokeWidth: 2.2, color: pal.accent, backgroundColor: pal.muted.withValues(alpha: 0.3))),
                  Icon(prog != null ? LucideIcons.download : offline ? LucideIcons.checkCircle2 : LucideIcons.download, size: prog != null ? 14 : size, color: offline ? greenOk : pal.text),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Подпись о скачивании книги (под панелью и в раскрытом проигрывателе)
class DownloadNote extends StatelessWidget {
  const DownloadNote({super.key, required this.pal, this.center = false, this.border = true, this.gap = 0});
  final Palette pal;
  final bool center;
  final bool border;
  final double gap; // отступ снизу, пока подпись видна (gap колонки в проигрывателе)

  @override
  Widget build(BuildContext context) {
    final d = BookDownloads.I;
    return ValueListenableBuilder<DlNote?>(
      valueListenable: d.note,
      builder: (_, n, _) {
        if (n == null) return const SizedBox.shrink();
        Widget link(String label, VoidCallback f) => GestureDetector(
              onTap: f,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(label, style: TextStyle(color: pal.accent, fontSize: 13.4, decoration: TextDecoration.underline))),
            );
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(border ? 14 : 0, border ? 8 : 0, border ? 14 : 0, (border ? 8 : 0) + gap),
          decoration: border ? BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))) : null,
          child: Wrap(
            alignment: center ? WrapAlignment.center : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(n.text, style: TextStyle(fontSize: 13.4, color: n.ok ? greenOk : pal.text)),
              if (n.remove != null) link(t('удалить'), () => n.remove!()),
              link(t('скрыть'), () => d.note.value = null),
            ],
          ),
        );
      },
    );
  }
}

/// Подпись под часами таймера
String sleepLeftText(DateTime until) => '${math.max(1, (until.difference(DateTime.now()).inSeconds / 60).round())}';

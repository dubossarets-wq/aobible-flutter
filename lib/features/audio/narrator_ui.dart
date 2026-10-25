// Интерфейс диктора: предложение скачать голос в мини-проигрывателе и строка «Диктор: Дмитрий» в настройках аудио.
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'audio_engine.dart';
import 'narrator.dart';

String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(0);

/// Подпись хода загрузки: «Скачиваю голос… 45%» / «Распаковываю голос…»
String voiceProgressText(String phase, double? p) =>
    phase == 'unpack' ? t('Распаковываю голос…') : t('Скачиваю голос… {n}%', {'n': '${((p ?? 0) * 100).round()}'});

/// Нет записи, голос не скачан: вопрос и две кнопки (вместо строки управления мини-проигрывателя)
class NarratorOffer extends StatelessWidget {
  const NarratorOffer({super.key, required this.pal, this.error});
  final Palette pal;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final v = NarratorVoice.I;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ValueListenableBuilder<String?>(
            valueListenable: v.busy,
            builder: (_, phase, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: t('Для этой главы нет аудиозаписи.'), style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' ${t('Прочитать голосом диктора?')}'),
              ]), style: TextStyle(fontSize: 14.4, height: 1.4, color: pal.text)),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(fontSize: 13, color: Color(0xFFD64545)))),
              const SizedBox(height: 10),
              if (phase == null)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  AobButton(label: t('Скачать голос ({n} МБ)', {'n': '$voiceSizeMb'}), icon: LucideIcons.download, kind: BtnKind.primary, small: true, onTap: AudioEngine.I.acceptNarrator),
                  AobButton(label: t('Не нужно'), small: true, onTap: AudioEngine.I.declineNarrator),
                ])
              else
                ValueListenableBuilder<double?>(
                  valueListenable: v.progress,
                  builder: (_, p, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(voiceProgressText(phase, p), style: TextStyle(fontSize: 13, color: pal.muted)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: phase == 'download' ? p : null, minHeight: 4, color: pal.accent, backgroundColor: pal.line),
                    ),
                    if (phase == 'download') ...[
                      const SizedBox(height: 8),
                      AobButton(label: t('Отмена'), small: true, onTap: v.cancel),
                    ],
                  ]),
                ),
            ]),
          ),
        ),
        IconBtn(icon: LucideIcons.x, subtle: true, size: 18, tooltip: t('Закрыть аудио'), onTap: AudioEngine.I.declineNarrator),
      ]),
    );
  }
}

/// «Диктор: Дмитрий» (скачать / удалить, размер, ход загрузки) и переключатель «Читать диктором, когда нет записи»
class NarratorSettings extends StatefulWidget {
  const NarratorSettings({super.key, required this.pal});
  final Palette pal;
  @override
  State<NarratorSettings> createState() => _NarratorSettingsState();
}

class _NarratorSettingsState extends State<NarratorSettings> {
  bool _armed = false; // нажали корзину — ждём подтверждения
  String? _error;

  @override
  void initState() {
    super.initState();
    NarratorVoice.I.refresh();
  }

  Future<void> _download() async {
    setState(() => _error = null);
    try {
      await NarratorVoice.I.install();
    } catch (_) {
      if (mounted) setState(() => _error = t('Голос не скачался. Проверьте интернет.'));
    }
  }

  Future<void> _remove() async {
    setState(() => _armed = false);
    // Читает как раз он — сначала останавливаем
    if (AudioEngine.I.s.narrated) await AudioEngine.I.stop();
    await NarratorVoice.I.remove();
    Hub.toast(t('Голос диктора удалён'));
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final v = NarratorVoice.I;
    TextStyle note() => TextStyle(color: pal.muted, fontSize: 12.5);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.line))),
        child: ListenableBuilder(
          listenable: Listenable.merge([v.installed, v.busy, v.progress, v.bytes]),
          builder: (_, _) {
            final phase = v.busy.value;
            final sub = phase != null
                ? voiceProgressText(phase, v.progress.value)
                : v.installed.value
                    ? t('Голос скачан · {size} МБ', {'size': _mb(v.bytes.value)})
                    : t('Голос не скачан · {n} МБ', {'n': '$voiceSizeMb'});
            return Row(spacing: 8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Диктор: Дмитрий'), style: TextStyle(fontSize: 15, color: pal.text)),
                  Text(sub, style: note()),
                  if (_error != null) Text(_error!, style: const TextStyle(fontSize: 12.5, color: Color(0xFFD64545))),
                  if (phase == 'download')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: v.progress.value, minHeight: 4, color: pal.accent, backgroundColor: pal.line)),
                    ),
                ]),
              ),
              if (phase == 'download')
                AobButton(label: t('Отмена'), onTap: v.cancel)
              else if (phase == null && !v.installed.value)
                AobButton(label: t('Скачать'), icon: LucideIcons.download, kind: BtnKind.primary, onTap: _download)
              else if (phase == null && _armed) ...[
                AobButton(label: t('Удалить'), kind: BtnKind.danger, onTap: _remove),
                AobButton(label: t('Отмена'), onTap: () => setState(() => _armed = false)),
              ] else if (phase == null)
                IconBtn(icon: LucideIcons.trash2, subtle: true, size: 15, tooltip: t('Удалить голос диктора'), onTap: () => setState(() => _armed = true)),
            ]);
          },
        ),
      ),
      SwitchRow(
        label: t('Читать диктором, когда нет записи'),
        hint: t('Если живой записи нет, главу прочитает голос диктора — на телефоне, без интернета'),
        value: narratorEnabled,
        onChanged: (x) => setState(() => narratorEnabled = x),
      ),
    ]);
  }
}

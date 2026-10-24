// Приветствие при первом запуске (Welcome.jsx): три коротких шага — размер букв, долгое нажатие на стих,
// нажатие на слово. Только новому человеку, один раз.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import 'appearance_sheet.dart';
import 'colors.dart';
import 'help_sheet.dart';
import 'sheet.dart';

Future<void> openWelcome(BuildContext context) {
  prefs.setBool('welcomePending', false);
  return showAppSheet(context, (_) => const WelcomeSheet());
}

const _steps = <(IconData, String, String)>[
  (Icons.text_fields, 'Удобный размер букв', 'Подберите размер, чтобы читать было легко. Поменять его можно в «Оформлении» или двумя пальцами прямо на тексте.'),
  (Icons.touch_app_outlined, 'Зажмите стих', 'Откроются действия: цвет, заметка, закладка, копировать, поделиться, подстрочник, комментарии.'),
  (Icons.translate, 'Нажмите на слово', 'Увидите слово оригинала на иврите или греческом и его значение по словарю Стронга.'),
];

class WelcomeSheet extends ConsumerStatefulWidget {
  const WelcomeSheet({super.key});
  @override
  ConsumerState<WelcomeSheet> createState() => _WelcomeSheetState();
}

class _WelcomeSheetState extends ConsumerState<WelcomeSheet> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pal = effectivePalette(s);
    final step = _steps[_i];
    final last = _i == _steps.length - 1;
    return AppSheet(
      title: t('Добро пожаловать'),
      subtitle: t('Шаг {n} из {total}', {'n': '${_i + 1}', 'total': '${_steps.length}'}),
      footer: Row(children: [
        Expanded(child: OutlinedButton(onPressed: _i > 0 ? () => setState(() => _i--) : () => Navigator.of(context).maybePop(), child: Text(_i > 0 ? t('Назад') : t('Пропустить')))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: last ? () => Navigator.of(context).maybePop() : () => setState(() => _i++), child: Text(last ? t('Начать чтение') : t('Далее')))),
      ]),
      children: [
        Center(child: Icon(step.$1, size: 44, color: pal.accent)),
        const SizedBox(height: 8),
        Center(child: Text(t(step.$2), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        Text(t(step.$3), textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.4, color: pal.muted)),
        if (_i == 0) ...[
          RangeRow(
            label: t('Размер шрифта'),
            big: true,
            value: s.d('fontSize'),
            min: 13,
            max: 40,
            step: 1,
            onChanged: (v) => ref.read(settingsProvider.notifier).set({'fontSize': v}),
            word: (v) => '${v.round()} px',
          ),
          Sample(s: s, head: true),
        ],
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < _steps.length; k++) Container(width: 8, height: 8, margin: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, color: k == _i ? pal.accent : pal.line)),
        ]),
        if (last) Center(child: TextButton(onPressed: () => openHelp(context), child: Text(t('Открыть инструкцию')))),
      ],
    );
  }
}

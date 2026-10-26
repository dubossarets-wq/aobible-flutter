// Приветствие при первом запуске (Welcome.jsx): три коротких шага — размер букв, долгое нажатие на стих,
// нажатие на слово. Только новому человеку, один раз.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import 'appearance_sheet.dart';
import 'colors.dart';
import 'help_sheet.dart';
import 'sheet.dart';

Future<void> openWelcome(BuildContext context) {
  prefs.setBool('welcomePending', false);
  return showAppSheet(context, (_) => const WelcomeSheet());
}

// Значки — как в Welcome.jsx: Type, Hand, BookA
const _steps = <(IconData, String, String)>[
  (LucideIcons.type, 'Удобный размер букв', 'Подберите размер, чтобы читать было легко. Поменять его можно в «Оформлении» или двумя пальцами прямо на тексте.'),
  (LucideIcons.hand, 'Зажмите стих', 'Откроются действия: цвет, заметка, закладка, копировать, поделиться, подстрочник, комментарии.'),
  (LucideIcons.bookA, 'Нажмите на слово', 'Увидите слово оригинала на иврите или греческом и его значение по словарю Стронга.'),
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
    // .welcome-step: по центру, зазор 10, поля 8 сверху и 4 снизу
    return AppSheet(
      title: t('Добро пожаловать'),
      subtitle: t('Шаг {n} из {total}', {'n': '${_i + 1}', 'total': '${_steps.length}'}),
      gap: 10,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      // .welcome-actions: «Назад / Пропустить» слева, главная кнопка справа
      footer: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [ // Wrap: при крупном шрифте кнопки переносятся, а не вылезают за край
        AobButton(label: _i > 0 ? t('Назад') : t('Пропустить'), onTap: _i > 0 ? () => setState(() => _i--) : () => Navigator.of(context).maybePop()),
        AobButton(kind: BtnKind.primary, label: last ? t('Начать чтение') : t('Далее'), onTap: last ? () => Navigator.of(context).maybePop() : () => setState(() => _i++)),
      ]),
      children: [
        Center(child: Icon(step.$1, size: 40, color: pal.accent)),
        Center(child: Text(t(step.$2), style: TextStyle(fontSize: 18.75, fontWeight: FontWeight.w700, color: pal.text))),
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 510), child: Text(t(step.$3), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.4, color: pal.text)))),
        if (_i == 0) ...[
          RangeRow(
            label: t('Размер шрифта'),
            buttons: false,
            value: s.d('fontSize'),
            min: 13,
            max: 40,
            step: 1,
            onChanged: (v) => ref.read(settingsProvider.notifier).set({'fontSize': v}),
            word: (v) => '${v.round()} px',
          ),
          Sample(s: s, head: true),
        ],
        // .welcome-dots: точки 8, зазор 6; выбранная — цвета акцента
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < _steps.length; k++) Container(width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(shape: BoxShape.circle, color: k == _i ? pal.accent : pal.muted.withValues(alpha: 0.4))),
          ]),
        ),
        if (last) Center(child: AobButton(block: true, small: true, label: t('Открыть инструкцию'), onTap: () => openHelp(context))),
      ],
    );
  }
}

// Аккаунт Колоса: вход через Google, состояние синхронизации, выход и удаление аккаунта. Открывается из самого
// верха «Ещё».
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart' show Palette;
import '../../ui/ios_style.dart';
import '../../ui/kit.dart';
import '../hub.dart';
import 'account_sync.dart';
import 'ui.dart';

void openAccount(BuildContext context) {
  showAobSheet<void>(context, builder: (_) => const AccountPage());
}

/// Вторая строка пункта «Аккаунт» в «Ещё»: кто вошёл (или приглашение войти)
String accountMenuSub() {
  final st = accountState.value;
  return st.signedIn ? (st.email ?? st.name ?? '') : t('Закладки, заметки и настройки — на всех устройствах');
}

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});
  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  String? _accError;

  String _errorText(String e) => switch (e) {
        'not-configured' => t('Вход через Google скоро заработает.'),
        'offline' => t('Нет связи с интернетом — данные сойдутся, когда она появится.'),
        'auth' => t('Вход больше не действует — войдите снова.'),
        'quota' => t('В аккаунте закончилось место.'),
        'google' => t('Google не подтвердил вход. Попробуйте ещё раз.'),
        _ => t('Не удалось: {error}', {'error': e}),
      };

  Future<void> _signIn() async {
    setState(() => _accError = null);
    final e = await signInWithGoogle();
    if (!mounted) return;
    setState(() {
      _accError = e == null || e == 'canceled' ? null : _errorText(e);
    });
  }

  Widget _account(Palette pal, TextStyle Function() note, Widget Function(List<Widget>, {Key? key}) btns) => ValueListenableBuilder<SyncState>(
        valueListenable: accountState,
        builder: (context, st, _) => ValueListenableBuilder<bool>(
          valueListenable: syncBusy,
          builder: (context, busy, _) {
            if (!st.signedIn) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Войдите через Google — закладки, заметки, выделения, проповеди, планы, история и настройки сохранятся в аккаунте и появятся на других ваших устройствах (iPhone, Android, сайт).'), style: note()),
                if (st.error == 'auth') Padding(padding: const EdgeInsets.only(top: 8), child: Text(_errorText('auth'), style: const TextStyle(fontSize: 14.7, height: 1.4, color: Color(0xffb4412f)))),
                const SizedBox(height: 10),
                btns([AobButton(kind: BtnKind.primary, wide: true, icon: LucideIcons.logIn, label: t('Войти через Google'), onTap: busy ? null : _signIn)]),
                if (_accError != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_accError!, style: const TextStyle(fontSize: 14.7, height: 1.4, color: Color(0xffb4412f)))),
              ]);
            }
            final when = st.lastSync == null ? null : DateTime.fromMillisecondsSinceEpoch(st.lastSync!);
            final status = busy
                ? t('Синхронизация…')
                : st.error != null
                    ? _errorText(st.error!)
                    : when == null
                        ? ''
                        : t('Синхронизировано: {time}', {'time': '${fmtDate(st.lastSync!, year: false)} ${two(when.hour)}:${two(when.minute)}'});
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(st.email ?? st.name ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
              const SizedBox(height: 4),
              if (status.isNotEmpty) Text(status, style: note()),
              const SizedBox(height: 10),
              btns([
                AobButton(wide: true, icon: LucideIcons.refreshCw, label: t('Синхронизировать'), onTap: busy
                    ? null
                    : () async {
                        if (await syncNow()) Hub.restartApp?.call();
                      }),
                AobButton(wide: true, icon: LucideIcons.logOut, label: t('Выйти'), onTap: busy ? null : signOut),
              ]),
              const SizedBox(height: 8),
              ConfirmButton(
                small: true,
                icon: LucideIcons.trash2,
                label: t('Удалить аккаунт и данные на сервере'),
                confirmLabel: t('Удалить'),
                onConfirm: () async {
                  final e = await deleteAccount();
                  if (mounted) setState(() => _accError = e == null ? null : _errorText(e));
                },
              ),
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('На этом телефоне данные останутся.'), style: TextStyle(fontSize: 13.1, height: 1.4, color: pal.muted))),
              if (_accError != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_accError!, style: const TextStyle(fontSize: 14.7, height: 1.4, color: Color(0xffb4412f)))),
            ]);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pal = paletteOf(ref);
    TextStyle note() => TextStyle(fontSize: 14.7, height: 1.5, color: pal.muted);
    Widget btns(List<Widget> children, {Key? key}) => LayoutBuilder(
          builder: (_, c) {
            final two = !iosStyleOf(ref) && c.maxWidth >= 2 * 180 + 8;
            return Wrap(key: key, spacing: 8, runSpacing: 8, children: [for (final w in children) SizedBox(width: two ? (c.maxWidth - 8) / 2 : c.maxWidth, child: w)]);
          },
        );
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AobSheet(title: t('Аккаунт'), child: _account(pal, note, btns)),
      ),
    );
  }
}

// Эмуляция экранной клавиатуры на компьютере (Windows/macOS/Linux): поле ввода в фокусе — снизу встаёт серая
// «клавиатура» высотой как у телефона, а приложение получает её высоту в MediaQuery.viewInsets — окна и вкладки
// подстраиваются так же, как под настоящую. F8 — включить/выключить, «Скрыть» — убрать курсор из поля.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Только на компьютере (на телефоне клавиатура настоящая) и не в тестах (flutter test ставит FLUTTER_TEST)
final bool keyboardEmuAvailable = (Platform.isWindows || Platform.isLinux || Platform.isMacOS) && !Platform.environment.containsKey('FLUTTER_TEST');

class KeyboardEmu extends StatefulWidget {
  const KeyboardEmu({super.key, required this.child});
  final Widget child;
  @override
  State<KeyboardEmu> createState() => _KeyboardEmuState();
}

class _KeyboardEmuState extends State<KeyboardEmu> {
  static const _height = 300.0; // как у клавиатуры телефона в портретной ориентации
  bool _on = true;
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_check);
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_check);
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  // в фокусе поле ввода? (у EditableText свой Focus внутри)
  void _check() {
    final c = FocusManager.instance.primaryFocus?.context;
    final typing = c != null && (c.widget is EditableText || c.findAncestorWidgetOfExactType<EditableText>() != null);
    if (typing != _typing && mounted) setState(() => _typing = typing);
  }

  bool _key(KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.f8) {
      setState(() => _on = !_on);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _on && _typing;
    final mq = MediaQuery.of(context);
    final inset = shown ? _height + mq.padding.bottom : 0.0;
    return MediaQuery(
      data: mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: inset > mq.viewInsets.bottom ? inset : mq.viewInsets.bottom)),
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        if (shown)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: inset,
            child: Material(
              color: const Color(0xFF2B2D31),
              child: SafeArea(
                top: false,
                child: Stack(children: [
                  const Center(
                    child: Text('Эмуляция клавиатуры\nпечатайте на клавиатуре компьютера · F8 — выключить',
                        textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB8BCC4), fontSize: 13, height: 1.5)),
                  ),
                  Positioned(
                    right: 12,
                    top: 10,
                    child: TextButton(
                      onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                      child: const Text('Скрыть', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

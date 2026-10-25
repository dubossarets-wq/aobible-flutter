// Первый запуск: ставим основной перевод (дальше — остальные стартовые модули, по мере переноса функций).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n.dart';
import '../core/modules.dart';
import '../core/settings.dart';
import '../features/hub.dart';
import 'kit.dart';

class BootstrapScreen extends ConsumerStatefulWidget {
  const BootstrapScreen({super.key, required this.onReady});
  final VoidCallback onReady;
  @override
  ConsumerState<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> {
  double _p = 0;
  String _label = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _label = t('Подключаю каталог…');
    });
    try {
      final cat = await ModuleStore.instance.catalog();
      if (!mounted) return;
      final id = ref.read(settingsProvider).get<String>('primaryModule');
      final e = cat.firstWhere((m) => m.id == id, orElse: () => cat.firstWhere((m) => m.id == 'rst-plus'));
      await ModuleStore.instance.install(e, onProgress: (p, l) {
        if (!mounted) return; // окно могли закрыть, пока шла загрузка
        setState(() {
          _p = p;
          _label = '${e.name}: ${t(l)}';
        });
      });
      if (mounted) widget.onReady();
    } catch (err) {
      debugPrint('bootstrap: $err');
      if (!mounted) return;
      setState(() => _error = t('Не удалось подключиться к серверу. Проверьте интернет.'));
    }
  }

  // Как .bootstrap в веб-версии: карточка по центру экрана, всё — по левому краю
  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    final p = TextStyle(fontSize: 15, height: 1.5, color: pal.muted);
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(alignment: Alignment.centerLeft, child: Icon(LucideIcons.bookOpen, size: 36, color: pal.accent)),
              const SizedBox(height: 14),
              Text('AO Bible', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.32, color: pal.text)),
              const SizedBox(height: 14),
              if (_error == null) ...[
                Text(t('Готовлю Синодальный перевод, словари и параллельные места…'), style: p),
                const SizedBox(height: 14),
                AobProgress(value: _p, label: _label),
              ] else ...[
                Text(_error!, style: p.copyWith(color: const Color(0xffb4412f))),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  AobButton(label: t('Повторить'), icon: LucideIcons.rotateCw, kind: BtnKind.primary, onTap: _run),
                  if (Hub.openLibrary != null) AobButton(label: t('Библиотека модулей'), icon: LucideIcons.library, onTap: () => Hub.openLibrary!(context, ref, 0)),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

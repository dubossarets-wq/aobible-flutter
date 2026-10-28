// Первый запуск: ставим основной перевод (дальше — остальные стартовые модули, по мере переноса функций).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> with SingleTickerProviderStateMixin {
  double _p = 0;
  String? _error;
  String? _detail; // техническая причина ошибки
  bool _started = false; // каталог получен, пошла загрузка перевода
  // значок чуть «дышит» — плавно поднимается и опускается на 3
  late final _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _detail = null;
      _p = 0;
      _started = false;
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
          _started = true;
        });
      });
      if (mounted) widget.onReady();
    } catch (err) {
      debugPrint('bootstrap: $err');
      if (!mounted) return;
      setState(() {
        _error = t('Не удалось подключиться к серверу. Проверьте интернет.');
        _detail = '$err'; // причина мелко — по снимку экрана видно, что случилось
      });
    }
  }

  // Как .bootstrap в веб-версии: значок, название, этапы с отметками и общий прогресс — всё по центру
  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider).palette;
    final muted = TextStyle(fontSize: 15, height: 1.5, color: pal.muted);
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            // появление: проявляется и поднимается на 8
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedBuilder(
                  animation: _float,
                  builder: (context, child) => Transform.translate(offset: Offset(0, -3 * Curves.easeInOut.transform(_float.value)), child: child),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 28, offset: const Offset(0, 10)),
                        BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: SvgPicture.string(_logo),
                  ),
                ),
                const SizedBox(height: 18),
                Text('AO Bible', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: pal.text)),
                const SizedBox(height: 6),
                if (_error == null) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(t('Готовлю Синодальный перевод, словари и параллельные места…'), textAlign: TextAlign.center, style: muted),
                  ),
                  const SizedBox(height: 22),
                  _Steps(pal: pal, p: _p, started: _started),
                  const SizedBox(height: 14),
                  Text(t('Это нужно только один раз — дальше Библия работает без интернета.'), textAlign: TextAlign.center, style: muted.copyWith(fontSize: 12.8)),
                ] else ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(color: Color.lerp(pal.panel, _danger, 0.1), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(LucideIcons.wifiOff, size: 20, color: _danger),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(fontSize: 15, height: 1.4, color: _danger))),
                    ]),
                  ),
                  if (_detail != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_detail!, style: TextStyle(fontSize: 12, height: 1.35, color: pal.muted))),
                  const SizedBox(height: 16),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    AobButton(label: t('Повторить'), icon: LucideIcons.rotateCw, kind: BtnKind.primary, onTap: _run),
                    if (Hub.openLibrary != null) AobButton(label: t('Библиотека модулей'), icon: LucideIcons.library, onTap: () => Hub.openLibrary!(context, ref, 0)),
                  ]),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

const _danger = Color(0xffb4412f);

// Значок приложения — тот же, что public/icons/icon.svg в веб-версии
const _logo = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<rect width="512" height="512" rx="112" fill="#38363a"/>
<path d="M256 150c-38-26-92-34-150-26v236c58-8 112 0 150 26z" fill="#f6f5f2"/>
<path d="M256 150c38-26 92-34 150-26v236c-58-8-112 0-150 26z" fill="#e9e4d8"/>
<path d="M300 128v120l26-18 26 18V122c-18 0-36 2-52 6z" fill="#c9893f"/>
<path d="M146 200h76M146 236h76M146 272h76M290 284h76M290 320h60" stroke="#b9b2a3" stroke-width="10" stroke-linecap="round"/>
</svg>''';

/// Этапы установки по доле прогресса: каталог (ещё не начали) → загрузка (до 60 %) → распаковка и запись
class _Steps extends StatelessWidget {
  const _Steps({required this.pal, required this.p, required this.started});
  final Palette pal;
  final double p;
  final bool started;

  @override
  Widget build(BuildContext context) {
    final stage = !started ? 0 : p < 0.6 ? 1 : p < 1 ? 2 : 3;
    final items = [t('Каталог модулей'), t('Загрузка перевода'), t('Установка')];
    final pct = (p * 100).round();
    Widget mark(int st) {
      // st: 0 — ждёт, 1 — идёт, 2 — готово
      final Widget w = switch (st) {
        2 => Container(
            key: const ValueKey(2),
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
            child: Icon(LucideIcons.check, size: 12, color: pal.onAccent),
          ),
        1 => SizedBox(
            key: const ValueKey(1),
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent, backgroundColor: pal.accent.withValues(alpha: 0.22)),
          ),
        _ => Container(
            key: const ValueKey(0),
            width: 20,
            height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.muted.withValues(alpha: 0.45), width: 1.5)),
          ),
      };
      return SizedBox(
        width: 20,
        height: 20,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: FadeTransition(opacity: a, child: c)),
          child: Center(child: w),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      decoration: BoxDecoration(
        color: pal.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        for (var i = 0; i < items.length; i++)
          Container(
            height: 40,
            decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: pal.line.withValues(alpha: 0.6)))) : null,
            child: Row(children: [
              mark(i < stage ? 2 : i == stage ? 1 : 0),
              const SizedBox(width: 12),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -1),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    style: TextStyle(fontSize: 14.7, height: 1.2, fontWeight: i == stage ? FontWeight.w600 : FontWeight.w400, color: i <= stage ? pal.text : pal.muted),
                    child: Text(items[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: p.clamp(0.02, 1.0)),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: pal.accent, backgroundColor: pal.muted.withValues(alpha: 0.18)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            child: Text('$pct%', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.muted, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
      ]),
    );
  }
}

// Подстрочник стиха (InterlinearSheet.jsx): вкладки Синодальный / Винокуров / Вульгата (Новый Завет) и
// Еврейский / Септуагинта / Вульгата (Ветхий Завет). Слово оригинала, под ним — чтение, перевод и номер Стронга.
// Иврит — справа налево. Нажатие на слово открывает статью словаря с точной формой слова. Стрелки — соседние стихи.
// Озвучка слов (ORIG_AUDIO) выключена, как в веб-версии.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/books.dart';
import '../../core/i18n.dart';
import '../../core/panes.dart';
import '../../core/settings.dart';
import '../../ui/kit.dart';
import '../shell/fonts.dart' show readerTextStyle;
import 'dictionary_sheet.dart';
import 'interlinear.dart';
import 'sheet.dart';
import 'study_data.dart';
import 'translit.dart';

/// Hub.openInterlinear
Future<void> openInterlinearSheet(BuildContext context, WidgetRef ref, VerseRef at, String moduleId) =>
    showSheet(context, InterlinearSheet(at: at, moduleId: moduleId), size: SheetSize.full);

class InterlinearSheet extends ConsumerStatefulWidget {
  const InterlinearSheet({super.key, required this.at, required this.moduleId});
  final VerseRef at;
  final String moduleId;
  @override
  ConsumerState<InterlinearSheet> createState() => _InterlinearSheetState();
}

enum _Status { loading, install, none, error, ok }

class _InterlinearSheetState extends ConsumerState<InterlinearSheet> {
  /// Показанный сейчас стих; пока грузится соседний, на экране остаётся прежний
  late VerseRef _ref = widget.at;
  /// Стих, который загружается (быстрые нажатия стрелок идут от него)
  late VerseRef _target = widget.at;
  _Status _status = _Status.loading;
  String _label = '';
  String _error = '';
  List<IlWord> _words = const [];
  String _ru = '';
  int _gen = 0;
  // Откуда въезжает следующий вид: 1 — справа (вперёд), -1 — слева
  int _dir = 1;
  // Новый Завет: vin | syn | vulg (всегда открывается на Винокурове); Ветхий Завет: heb | lxx | vulg — выбор запоминается
  String _source = 'vin';
  String _otSource = prefs.getString('ilSourceOT') ?? 'heb';
  // Как оформлены показанные слова (меняются вместе со словами, а не раньше)
  bool _shownHebrew = false;
  bool _shownLatin = false;
  String _shownCur = '';

  bool get _ot => !isNt(_target.book);
  bool get _vin => !_ot && _source == 'vin';
  bool get _lxx => _ot && _otSource == 'lxx';
  bool get _vulg => (_ot ? _otSource : _source) == 'vulg';
  bool get _hebrew => _ot && !_lxx && !_vulg;
  String get _cur => _vulg ? 'vulg' : (_ot ? (_lxx ? 'lxx' : 'heb') : (_vin ? 'vin' : 'syn'));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final target = _target;
    final cur = _cur, hebrew = _hebrew, latin = _vulg;
    // первая загрузка — показываем «Загрузка…»; потом старое остаётся на экране, пока готовится новое
    if (_shownCur.isEmpty && _status != _Status.loading) setState(() => _status = _Status.loading);
    try {
      if (originalFor(target.book) == null) return setState(() => _status = _Status.none);
      void progress(double p, String label) {
        if (gen == _gen && mounted) {
          setState(() {
            _status = _Status.install;
            _label = label;
          });
        }
      }

      if (!_lxx && !_vulg) await ensureOriginal(target.book, progress);
      final words = _lxx
          ? await lxxInterlinear(target, progress)
          : _vulg
              ? await vulgInterlinear(target, progress)
              : _vin
                  ? await vinInterlinear(target, progress)
                  : origInterlinear(target);
      final ru = StudyData.verse(widget.moduleId, target);
      if (gen != _gen || !mounted) return;
      setState(() {
        _ref = target;
        _words = words ?? const [];
        _ru = ru == null ? '' : plainOf(ru);
        _shownCur = cur;
        _shownHebrew = hebrew;
        _shownLatin = latin;
        _status = _Status.ok;
      });
    } catch (e) {
      if (gen == _gen && mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _status = _Status.error;
        });
      }
    }
  }

  void _pick(String v) {
    final order = _ot ? ['heb', 'lxx', 'vulg'] : ['vin', 'syn', 'vulg'];
    _dir = order.indexOf(v) >= order.indexOf(_cur) ? 1 : -1;
    setState(() {
      if (_ot) {
        _otSource = v;
        prefs.setString('ilSourceOT', v);
      } else {
        _source = v;
      }
    });
    _load();
  }

  /// Соседний стих по оригинальному тексту (с переходом через главу)
  void _step(int d) {
    final id = _lxx ? lxxModule : _vulg ? vulgModule : originalFor(_target.book);
    if (id == null || !StudyData.isInstalled(id)) return;
    var chapter = _target.chapter, verse = _target.verse + d;
    if (verse < 1) {
      if (chapter == 1) return;
      chapter -= 1;
      final n = StudyData.verseCount(id, _target.book, chapter);
      verse = n == 0 ? 1 : n;
    } else if (verse > StudyData.verseCount(id, _target.book, chapter)) {
      if (chapter >= StudyData.chapterCount(id, _target.book)) return;
      chapter += 1;
      verse = 1;
    }
    _dir = d > 0 ? 1 : -1;
    _target = VerseRef(_target.book, chapter, verse);
    _load();
  }

  void _open(IlWord w) {
    if (w.strongs == null) return;
    final pane = paneOf(ref.read(panesProvider), widget.moduleId);
    openDictionary(
      context,
      DictRequest(
        text: w.gloss.isNotEmpty ? w.gloss : w.text,
        strongs: w.strongs!,
        morph: w.morph != null ? [w.morph!] : const [],
        ref: _ref,
        pane: pane,
        origWord: OrigInfo(orig: w.text, morph: w.morph, num: w.num),
        autoOpen: true,
        fromInterlinear: true,
      ),
      full: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final subtitle = _vulg
        ? t('Вульгата (Климентина) · значения по словарю')
        : _lxx
            ? t('Септуагинта (Свит) · значения по словарю')
            : _hebrew
                ? t('Еврейский текст (OSHB) · синодальный')
                : _vin
                    ? t('Греческий текст (Робинсон — Пирпонт) · А. Винокуров')
                    : t('Греческий текст (Робинсон — Пирпонт) · синодальный');
    Widget body;
    switch (_status) {
      case _Status.loading:
      case _Status.install:
        body = SheetList(children: [Loading(_status == _Status.install ? '${t('Загружаю оригинал…')} $_label' : t('Загрузка…'))]);
      case _Status.none:
        body = SheetList(children: [Text(t('Для этой книги нет оригинала.'), style: TextStyle(color: pal.muted))]);
      case _Status.error:
        body = SheetList(children: [WarnBox(child: Text(_error))]);
      case _Status.ok:
        body = _okBody(pal);
    }
    return SheetScaffold(
      title: t('Подстрочник · {ref}', {'ref': fmtRef(_ref)}),
      subtitle: subtitle,
      headerExtra: [
        IconBtn(icon: LucideIcons.chevronLeft, tooltip: t('Предыдущий стих'), onTap: () => _step(-1)),
        IconBtn(icon: LucideIcons.chevronRight, tooltip: t('Следующий стих'), onTap: () => _step(1)),
      ],
      body: body,
    );
  }

  /// Подсказка под словами: коротко, что это за перевод
  String get _hint => _shownCur == 'vin'
      ? t('Подстрочный перевод Нового Завета А. Винокурова.')
      : _shownCur == 'lxx'
          ? t('Септуагинта — греческий Ветхий Завет (изд. Г. Б. Свита). Под словом: чтение, значение и номер Стронга. Нажмите на слово — откроется словарь.')
          : _shownCur == 'vulg'
              ? t('Латинская Вульгата; под словами — значение и начальная форма.')
              : _shownCur == 'heb'
                  ? t('Под словом: чтение, перевод и номер Стронга; бледным — обычное значение. Нажмите на слово — откроется словарь.')
                  : t('Синодальный перевод; под словами — оригинал, чтение и номер Стронга.');

  Widget _okBody(Palette pal) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rtl = _shownHebrew;
    final key = ValueKey('${_ref.chapter}:${_ref.verse}:$_shownCur');
    final content = SingleChildScrollView(
      key: key,
      padding: EdgeInsets.fromLTRB(16, 6, 16, 24 + bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_words.isEmpty) Text(t('В оригинале этого стиха нет.'), style: TextStyle(color: pal.muted)),
        if ((_shownCur == 'lxx' || _shownCur == 'vulg') && _words.isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t('Под словами — значения по словарю, а не перевод.'), style: TextStyle(color: pal.muted, fontSize: 12.9))), // .muted.small
        Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Wrap(spacing: 6, runSpacing: 10, children: [for (final w in _words) _Cell(word: w, hebrew: rtl, latin: _shownLatin, onTap: () => _open(w))]),
        ),
        const SizedBox(height: 12),
        Text(_hint, style: TextStyle(color: pal.muted, fontSize: 13.6)), // .sheet-hint
      ]),
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // смахивание влево — следующий стих, вправо — предыдущий (перевод переключают плашки сверху)
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) _step(1);
        if (v > 300) _step(-1);
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // закреплено сверху: переключатель переводов и стих; прокручиваются только слова
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Segmented(
            value: _cur,
            onChanged: _pick,
            options: _ot ? [('heb', t('Еврейский')), ('lxx', t('Септуагинта')), ('vulg', t('Вульгата'))] : [('vin', t('Винокуров')), ('syn', t('Синодальный')), ('vulg', t('Вульгата'))],
          ),
        ),
        if (_ru.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: _QuoteCard(verse: _ref.verse, text: _ru)),
        Expanded(
          // слова уезжают целиком, на их место въезжают другие — в сторону смахивания
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
              transitionBuilder: (child, anim) {
                final incoming = child.key == key;
                final from = Offset(incoming ? _dir.toDouble() : -_dir.toDouble(), 0);
                return SlideTransition(position: Tween(begin: from, end: Offset.zero).animate(anim), child: child);
              },
              child: content,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Стих с номером на карточке: компактная, длинный стих прокручивается внутри (не отнимает место у слов)
class _QuoteCard extends ConsumerWidget {
  const _QuoteCard({required this.verse, required this.text});
  final int verse;
  final String text;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final settings = ref.watch(settingsProvider);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 132),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: mix(pal.text, 0.055, pal.panel), borderRadius: BorderRadius.circular(18)),
      child: SingleChildScrollView(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$verse ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.accent, fontFeatures: const [FontFeature.superscripts()])),
            TextSpan(text: text),
          ]),
          style: readerTextStyle(settings, size: 16.5, weight: 400).copyWith(height: 1.45, color: pal.text),
        ),
      ),
    );
  }
}

class _Cell extends ConsumerWidget {
  const _Cell({required this.word, required this.hebrew, required this.latin, required this.onTap});
  final IlWord word;
  final bool hebrew;
  final bool latin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = ref.watch(settingsProvider.select((s) => s.palette));
    final w = word;
    final tr = latin ? w.lemma : translit(w.text);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: w.strongs == null ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 35),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Directionality(textDirection: hebrew ? TextDirection.rtl : TextDirection.ltr, child: Text(w.text, style: TextStyle(fontFamily: hebrew ? 'Noto Serif Hebrew' : null, fontSize: hebrew ? 24 : 21.6, height: 1.25, color: pal.text))),
              Text(tr.isEmpty ? ' ' : tr, style: TextStyle(fontSize: 12.48, color: pal.muted, fontStyle: FontStyle.italic)), // .il-tr
              Text(
                w.gloss.isEmpty ? ' ' : w.gloss,
                style: w.guess
                    ? TextStyle(fontSize: 14.72, color: pal.accent.withValues(alpha: 0.55), fontStyle: FontStyle.italic)
                    : TextStyle(fontSize: 14.72, fontWeight: FontWeight.w600, color: pal.accent),
              ),
              Text(w.num != null ? w.num!.substring(1) : ' ', style: TextStyle(fontSize: 12.8, color: pal.muted, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }
}

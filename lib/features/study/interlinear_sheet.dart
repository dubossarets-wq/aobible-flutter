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
  late VerseRef _ref = widget.at;
  _Status _status = _Status.loading;
  String _label = '';
  String _error = '';
  List<IlWord> _words = const [];
  String _ru = '';
  int _gen = 0;
  // Новый Завет: syn | vin | vulg; Ветхий Завет: heb | lxx | vulg — выбор запоминается
  String _source = prefs.getString('ilSource') ?? 'syn';
  String _otSource = prefs.getString('ilSourceOT') ?? 'heb';

  bool get _ot => !isNt(_ref.book);
  bool get _vin => !_ot && _source == 'vin';
  bool get _lxx => _ot && _otSource == 'lxx';
  bool get _vulg => (_ot ? _otSource : _source) == 'vulg';
  bool get _hebrew => _ot && !_lxx && !_vulg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (_status != _Status.loading) setState(() => _status = _Status.loading);
    try {
      if (originalFor(_ref.book) == null) return setState(() => _status = _Status.none);
      void progress(double p, String label) {
        if (gen == _gen && mounted) {
          setState(() {
            _status = _Status.install;
            _label = label;
          });
        }
      }

      if (!_lxx && !_vulg) await ensureOriginal(_ref.book, progress);
      final words = _lxx
          ? await lxxInterlinear(_ref, progress)
          : _vulg
              ? await vulgInterlinear(_ref, progress)
              : _vin
                  ? await vinInterlinear(_ref, progress)
                  : origInterlinear(_ref);
      final ru = StudyData.verse(widget.moduleId, _ref);
      if (gen != _gen || !mounted) return;
      setState(() {
        _words = words ?? const [];
        _ru = ru == null ? '' : plainOf(ru);
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
    setState(() {
      if (_ot) {
        _otSource = v;
        prefs.setString('ilSourceOT', v);
      } else {
        _source = v;
        prefs.setString('ilSource', v);
      }
    });
    _load();
  }

  /// Соседний стих по оригинальному тексту (с переходом через главу)
  void _step(int d) {
    final id = _lxx ? lxxModule : _vulg ? vulgModule : originalFor(_ref.book);
    if (id == null || !StudyData.isInstalled(id)) return;
    var chapter = _ref.chapter, verse = _ref.verse + d;
    if (verse < 1) {
      if (chapter == 1) return;
      chapter -= 1;
      final n = StudyData.verseCount(id, _ref.book, chapter);
      verse = n == 0 ? 1 : n;
    } else if (verse > StudyData.verseCount(id, _ref.book, chapter)) {
      if (chapter >= StudyData.chapterCount(id, _ref.book)) return;
      chapter += 1;
      verse = 1;
    }
    _ref = VerseRef(_ref.book, chapter, verse);
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

  Widget _okBody(Palette pal) {
    final hint = _vin
        ? t('Подстрочник А. Винокурова — с разрешения автора. Под словом: чтение, перевод и номер Стронга.')
        : _lxx
            ? t('Септуагинта — греческий Ветхий Завет (изд. Г. Б. Свита). Под словом: чтение, значение и номер Стронга. Нажмите на слово — откроется словарь.')
            : _vulg
                ? t('Вульгата — латинская Библия бл. Иеронима (Климентинское издание). Под словом: начальная форма и значение. Значения — из Викисловаря (CC BY-SA 4.0), формы — по Collatinus.')
                : t('Под словом: чтение, перевод и номер Стронга; бледным — обычное значение. Нажмите на слово — откроется словарь.');
    final cur = _vulg ? 'vulg' : (_ot ? (_lxx ? 'lxx' : 'heb') : (_vin ? 'vin' : 'syn'));
    final rtl = _hebrew;
    return SheetList(children: [
      Segmented(
        value: cur,
        onChanged: _pick,
        options: _ot ? [('heb', t('Еврейский')), ('lxx', t('Септуагинта')), ('vulg', t('Вульгата'))] : [('syn', t('Синодальный')), ('vin', t('Винокуров')), ('vulg', t('Вульгата'))],
      ),
      if (_ru.isNotEmpty) QuoteBox(_ru),
      if (_words.isEmpty) Text(t('В оригинале этого стиха нет.'), style: TextStyle(color: pal.muted)),
      if ((_lxx || _vulg) && _words.isNotEmpty) Text(t('Под словами — значения по словарю, а не перевод.'), style: TextStyle(color: pal.muted, fontSize: 12.9)), // .muted.small
      Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Wrap(spacing: 6, runSpacing: 10, children: [for (final w in _words) _Cell(word: w, hebrew: rtl, latin: _vulg, onTap: () => _open(w))]),
      ),
      Text(hint, style: TextStyle(color: pal.muted, fontSize: 13.6)), // .sheet-hint
    ]);
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

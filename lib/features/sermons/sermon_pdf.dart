// «Печать и PDF» (printSermon в SermonsSheet.jsx): аккуратная страница проповеди — серия, название, подзаголовок, дата;
// стихи с полосой слева и подключёнными переводами; свой текст с **жирным** и *курсивом*; заметки для себя — мелко и
// приглушённо. Файл PDF (шрифты PT Serif / PT Sans из приложения) — в системное окно «Поделиться»: печать, сохранение, отправка.
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/markup.dart';
import '../plans/loc.dart';
import 'sermon_store.dart';

const _accent = PdfColor.fromInt(0xff8a6b3f);
const _muted = PdfColor.fromInt(0xff777777);

Future<pw.Font> _font(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));

/// PDF проповеди (байты)
Future<List<int>> sermonPdf(Sermon s) async {
  final serif = await _font('PTSerif-Regular'), serifB = await _font('PTSerif-Bold'), serifI = await _font('PTSerif-Italic');
  final sans = await _font('PTSans-Regular'), sansB = await _font('PTSans-Bold');
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: serif, bold: serifB, italic: serifI, boldItalic: serifB),
  );
  pw.TextStyle ui(double size, {bool bold = false, PdfColor? color}) => pw.TextStyle(font: bold ? sansB : sans, fontSize: size, color: color);
  final body = pw.TextStyle(fontSize: 12.5, lineSpacing: 3);

  // свой текст: абзацы, **жирный**, *курсив*
  List<pw.Widget> rich(String text, pw.TextStyle style) => [
    for (final para in text.trim().split('\n'))
      pw.RichText(
        text: pw.TextSpan(
          style: style,
          children: [
            for (final p in fmtParts(para.isEmpty ? ' ' : para))
              pw.TextSpan(
                text: p.t,
                style: p.b
                    ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    : p.i
                    ? pw.TextStyle(fontStyle: pw.FontStyle.italic)
                    : null,
              ),
          ],
        ),
      ),
  ];

  // строки цитаты — каждая отдельно (длинный диапазон стихов может перейти на следующую страницу), у всех полоса слева
  pw.Widget bar(pw.Widget child, {double top = 0}) => pw.Container(
    padding: pw.EdgeInsets.only(left: 12, top: top, bottom: 2),
    decoration: const pw.BoxDecoration(
      border: pw.Border(left: pw.BorderSide(color: _accent, width: 3)),
    ),
    child: child,
  );

  final out = <pw.Widget>[];
  final series = '${s['series'] ?? ''}'.trim(), subtitle = '${s['subtitle'] ?? ''}'.trim();
  final date = DateTime.tryParse('${s['date'] ?? ''}');
  if (series.isNotEmpty)
    out.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(series.toUpperCase(), style: ui(9.5, bold: true, color: _accent).copyWith(letterSpacing: 0.6)),
      ),
    );
  out.add(pw.Text('${s['title']}', style: ui(22, bold: true)));
  if (subtitle.isNotEmpty)
    out.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 13, color: PdfColor.fromInt(0xff444444))),
      ),
    );
  if (date != null)
    out.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(fmtDay(date, full: true, year: true), style: ui(10, color: _muted)),
      ),
    );
  out.add(pw.SizedBox(height: 14));

  for (final b in blocksOf(s)) {
    if (isVerse(b)) {
      final tx = verseTexts(b) ?? ['${b['text']}'];
      out.add(pw.SizedBox(height: 8));
      out.add(bar(pw.Text(blockRefFull(b), style: ui(10, bold: true, color: _accent)), top: 2));
      for (final (i, x) in tx.indexed) {
        out.add(
          bar(
            tx.length > 1
                ? pw.RichText(
                    text: pw.TextSpan(
                      style: body,
                      children: [
                        pw.TextSpan(
                          text: '${(b['verse'] as int) + i} ',
                          style: ui(8, bold: true, color: _accent),
                        ),
                        pw.TextSpan(text: x),
                      ],
                    ),
                  )
                : pw.Text(x, style: body),
          ),
        );
      }
      for (final a in altsOf(b)) {
        final at = [for (final x in (a['t'] as List? ?? const [])) a['il'] == true ? plainText('$x') : '$x'].where((x) => x.isNotEmpty).join(' ');
        if (at.isEmpty) continue;
        out.add(bar(pw.Text('${a['n']}', style: ui(8.5, bold: true, color: _muted)), top: 4));
        out.add(bar(pw.Text(at, style: body.copyWith(fontSize: 11.5, color: const PdfColor.fromInt(0xff333333)))));
      }
      out.add(pw.SizedBox(height: 8));
    } else if ('${b['text']}'.trim().isNotEmpty) {
      final note = b['type'] == 'note';
      out.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          child: note
              ? pw.Container(
                  padding: const pw.EdgeInsets.only(left: 10),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(left: pw.BorderSide(color: PdfColor.fromInt(0xffbbbbbb), width: 2)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: rich('${b['text']}', pw.TextStyle(fontSize: 10.5, fontStyle: pw.FontStyle.italic, color: _muted)),
                  ),
                )
              : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: rich('${b['text']}', body)),
        ),
      );
    }
  }
  doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 46, marginRight: 46, marginTop: 50, marginBottom: 50), build: (_) => out));
  return doc.save();
}

/// Сохранить PDF во временную папку и открыть системное окно «Поделиться» (печать, сохранить, отправить)
Future<void> shareSermonPdf(Sermon s) async {
  final bytes = await sermonPdf(s);
  final dir = await getTemporaryDirectory();
  final name = '${s['title']}'.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
  final f = File('${dir.path}${Platform.pathSeparator}${name.isEmpty ? 'sermon' : name}.pdf');
  await f.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(f.path, mimeType: 'application/pdf')],
      title: '${s['title']}',
    ),
  );
}

// Логика аудиокниг без плагинов: разбор записи, стих по времени, подходящий перевод, соседние стихи и главы.
import 'dart:convert';

import 'package:aobible/core/books.dart';
import 'package:aobible/features/audio/audio_logic.dart';
import 'package:aobible/features/audio/audio_offline.dart';
import 'package:flutter_test/flutter_test.dart';

BookShape _shape(Map<int, List<int>> m) => BookShape(m);

void main() {
  final pack = AudioPack.fromJson(jsonDecode('''
  {"id":"a","name":"Ч","title":"Чтец","translation":"rst","language":"ru","chapters":{
    "John.1":{"url":"https://x/1.mp3","verses":[[1,40.36],[2,47.0],[3,55.26]]},
    "John.2":{"url":"https://x/all.mp3","start":100,"end":200,"verses":[[1,110],[2,150]]},
    "John.3":{"url":"https://x/all.mp3","start":200,"end":300,"verses":[[1,210]]},
    "Matt.1":{"url":"https://x/m.mp3","verses":[]}
  }}''') as Map<String, dynamic>);

  test('разбор модуля и адреса книги без повторов', () {
    expect(pack.has('John', 1), true);
    expect(pack.has('John', 9), false);
    expect(pack.urlsOf('John'), ['https://x/1.mp3', 'https://x/all.mp3']);
  });

  test('стих по времени и начало стиха', () {
    final c = pack.chapters['John.1']!;
    expect(c.verseAt(10), null);
    expect(c.verseAt(47.0), 2);
    expect(c.verseAt(46.96), 2); // запас 0,05 с
    expect(c.verseAt(500), 3);
    expect(c.startFor(2), 47.0);
    expect(c.startFor(1), 40.36);
    final s = pack.chapters['John.2']!;
    expect(s.startFor(1), 100); // первый стих — с начала главы в общем файле
    expect(s.startFor(2), 150);
    expect(s.span(999), (100.0, 100.0));
    expect(c.span(300), (0.0, 300.0));
  });

  test('какая запись подходит к переводу', () {
    expect(fitsTranslation('rst', 'rst'), true);
    expect(fitsTranslation('rst', 'rst-plus'), true);
    expect(fitsTranslation('rst', 'rst-dc'), true);
    expect(fitsTranslation('rst', 'kjv'), false);
    expect(fitsTranslation(null, 'kjv'), true);
    expect(fitsTranslation('kjv', 'kjv'), true);
    expect(fitsTranslation('oshb', 'rst'), false);
  });

  final shapes = {
    'Gen': _shape({1: [1, 2], 2: [1, 3]}), // во 2 главе нет 2-го стиха
    'Exod': _shape({1: [1], 2: [1, 2]}),
  };
  final books = ['Gen', 'Exod'];
  BookShape of(String b) => shapes[b]!;

  test('соседний стих: внутри главы, через пропуск, главу и книгу', () {
    expect(neighbourVerse(const VerseRef('Gen', 1, 1), 1, books, of), const VerseRef('Gen', 1, 2));
    expect(neighbourVerse(const VerseRef('Gen', 1, 2), 1, books, of), const VerseRef('Gen', 2, 1));
    expect(neighbourVerse(const VerseRef('Gen', 2, 1), 1, books, of), const VerseRef('Gen', 2, 3));
    expect(neighbourVerse(const VerseRef('Gen', 2, 3), 1, books, of), const VerseRef('Exod', 1, 1));
    expect(neighbourVerse(const VerseRef('Exod', 2, 2), 1, books, of), null);
    expect(neighbourVerse(const VerseRef('Gen', 1, 1), -1, books, of), null);
    expect(neighbourVerse(const VerseRef('Exod', 1, 1), -1, books, of), const VerseRef('Gen', 2, 3));
    expect(neighbourVerse(const VerseRef('Gen', 2, 3), -1, books, of), const VerseRef('Gen', 2, 1));
  });

  test('соседняя глава', () {
    expect(neighbourChapter(const VerseRef('Gen', 1, 2), 1, books, of), const VerseRef('Gen', 2, 1));
    expect(neighbourChapter(const VerseRef('Gen', 2, 3), 1, books, of), const VerseRef('Exod', 1, 1));
    expect(neighbourChapter(const VerseRef('Exod', 1, 1), -1, books, of), const VerseRef('Gen', 2, 1));
    expect(neighbourChapter(const VerseRef('Gen', 1, 1), -1, books, of), null);
    expect(neighbourChapter(const VerseRef('Exod', 2, 1), 1, books, of), null);
  });

  test('часы и размеры', () {
    expect(clock(65), '1:05');
    expect(clock(3723), '1:02:03');
    expect(clock(double.nan), '0:00');
    expect(fmtMin(15), '15:00');
    expect(fmtMin(75), '1:15:00');
    expect(megabytes(3 * 1048576), '3.0');
    expect(megabytes(20 * 1048576), '20');
  });

  test('имя файла записи стабильно и различается по адресу', () {
    expect(OfflineAudio.fileName('https://a/1.mp3'), OfflineAudio.fileName('https://a/1.mp3'));
    expect(OfflineAudio.fileName('https://a/1.mp3'), isNot(OfflineAudio.fileName('https://a/2.mp3')));
    expect(OfflineAudio.fileName('https://a/1.mp3').endsWith('.mp3'), true);
  });
}

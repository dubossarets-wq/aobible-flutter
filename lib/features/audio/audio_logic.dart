// Чистая логика аудиокниг (без плагинов и интерфейса — проверяется тестами):
// разбор модуля-записи, какая запись подходит к переводу, стих по времени, соседний стих/глава, часы.
import '../../core/books.dart';

/// Запись одной главы: адрес файла, время начала стихов (секунды от начала файла).
/// start/end есть, когда на несколько глав один файл (тогда глава — кусок файла).
class AudioChapter {
  AudioChapter(this.url, this.verses, this.start, this.end);
  final String url;
  final List<(int, double)> verses; // (номер стиха, секунда начала) по возрастанию
  final double? start;
  final double? end;

  bool get shared => end != null;

  static AudioChapter? fromJson(Object? j) {
    if (j is! Map || j['url'] is! String) return null;
    final list = <(int, double)>[];
    for (final p in (j['verses'] as List? ?? const [])) {
      if (p is List && p.length >= 2 && p[0] is num && p[1] is num) list.add(((p[0] as num).toInt(), (p[1] as num).toDouble()));
    }
    return AudioChapter(j['url'] as String, list, (j['start'] as num?)?.toDouble(), (j['end'] as num?)?.toDouble());
  }

  /// С какой секунды начинать стих: первый стих — с начала главы (объявление «Глава …»), иначе — с начала стиха
  double startFor(int verse) {
    if (verse == 1 && start != null) return start!;
    for (final v in verses) {
      if (v.$1 == verse) return v.$2;
    }
    return start ?? 0;
  }

  /// Какой стих звучит в секунду [sec] (с запасом 0,05 с, как в веб-версии); null — до первого стиха
  int? verseAt(double sec) {
    final t = sec + 0.05;
    int? cur;
    for (final v in verses) {
      if (v.$2 <= t) {
        cur = v.$1;
      } else {
        break;
      }
    }
    return cur;
  }

  /// Начало и длина главы внутри файла; [duration] — длина файла (когда глава не вырезана из общего)
  (double, double) span(double duration) {
    final s = shared ? (start ?? 0) : 0.0;
    final e = shared ? end! : duration;
    return (s, (e - s).clamp(0, double.infinity));
  }
}

/// Аудиомодуль: перевод, к которому записи подходят, и озвученные главы («Книга.глава» → запись)
class AudioPack {
  AudioPack(this.id, this.name, this.title, this.translation, this.language, this.chapters);
  final String id, name, title, language;
  final String? translation;
  final Map<String, AudioChapter> chapters;

  static AudioPack fromJson(Map<String, dynamic> j) {
    final ch = <String, AudioChapter>{};
    (j['chapters'] as Map? ?? const {}).forEach((k, v) {
      final c = AudioChapter.fromJson(v);
      if (c != null) ch[k as String] = c;
    });
    final name = j['name'] as String? ?? j['id'] as String;
    return AudioPack(j['id'] as String, name, j['title'] as String? ?? name, j['translation'] as String?, j['language'] as String? ?? 'ru', ch);
  }

  bool has(String book, int chapter) => chapters.containsKey('$book.$chapter');

  /// Адреса файлов всех глав книги (без повторов: на несколько глав бывает один файл)
  List<String> urlsOf(String book) => {
        for (final e in chapters.entries)
          if (e.key.split('.').first == book) e.value.url,
      }.toList();
}

// Синодальный с разметкой и без — один и тот же текст
const _rst = {'rst', 'rst-plus', 'rst-dc'};
bool sameText(String a, String b) => _rst.contains(a) && _rst.contains(b);

/// Подходит ли аудиокнига (её translation) к переводу bibleId
bool fitsTranslation(String? translation, String bibleId) => translation == null || translation.isEmpty || translation == bibleId || sameText(translation, bibleId);

/// Номера стихов по главам одной книги (только непустые стихи)
class BookShape {
  BookShape(this.verses) : chapters = (verses.keys.toList()..sort());
  final Map<int, List<int>> verses;
  final List<int> chapters;
}

/// Соседний стих (dir = 1 вперёд, -1 назад); через границу главы и книги. null — дальше некуда.
/// [books] — порядок книг перевода, [shapeOf] — стихи книги.
VerseRef? neighbourVerse(VerseRef ref, int dir, List<String> books, BookShape Function(String book) shapeOf) {
  var bi = books.indexOf(ref.book);
  if (bi < 0) return null;
  var shape = shapeOf(ref.book);
  var chIdx = shape.chapters.indexOf(ref.chapter);
  // Внутри главы
  final list = shape.verses[ref.chapter] ?? const <int>[];
  if (dir > 0) {
    for (final v in list) {
      if (v > ref.verse) return VerseRef(ref.book, ref.chapter, v);
    }
  } else {
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i] < ref.verse) return VerseRef(ref.book, ref.chapter, list[i]);
    }
  }
  if (chIdx < 0) chIdx = dir > 0 ? shape.chapters.lastIndexWhere((c) => c < ref.chapter) : shape.chapters.indexWhere((c) => c > ref.chapter);
  if (chIdx < 0 && dir < 0) chIdx = shape.chapters.length;
  return _chapterEdge(books, shapeOf, bi, shape, chIdx, dir, last: dir < 0);
}

/// Первый стих соседней главы (dir = 1) или предыдущей (dir = -1) — для кнопок «глава назад/вперёд»
VerseRef? neighbourChapter(VerseRef ref, int dir, List<String> books, BookShape Function(String book) shapeOf) {
  final bi = books.indexOf(ref.book);
  if (bi < 0) return null;
  final shape = shapeOf(ref.book);
  var chIdx = shape.chapters.indexOf(ref.chapter);
  if (chIdx < 0) chIdx = dir > 0 ? shape.chapters.lastIndexWhere((c) => c < ref.chapter) : shape.chapters.indexWhere((c) => c > ref.chapter);
  if (chIdx < 0 && dir < 0) chIdx = shape.chapters.length;
  return _chapterEdge(books, shapeOf, bi, shape, chIdx, dir, last: false);
}

VerseRef? _chapterEdge(List<String> books, BookShape Function(String) shapeOf, int bi, BookShape shape, int chIdx, int dir, {required bool last}) {
  var i = chIdx + dir;
  for (var guard = 0; guard < 400; guard++) {
    if (i >= 0 && i < shape.chapters.length) {
      final c = shape.chapters[i];
      final vs = shape.verses[c] ?? const <int>[];
      if (vs.isNotEmpty) return VerseRef(books[bi], c, last ? vs.last : vs.first);
      i += dir;
      continue;
    }
    bi += dir;
    if (bi < 0 || bi >= books.length) return null;
    shape = shapeOf(books[bi]);
    i = dir > 0 ? 0 : shape.chapters.length - 1;
  }
  return null;
}

/// «1:05», «1:02:03»
String clock(double s) {
  final v = s.isFinite ? s.floor().clamp(0, 1 << 30) : 0;
  final h = v ~/ 3600, m = (v % 3600) ~/ 60, ss = (v % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// Таймер сна на ленте: «15:00», «1:05:00»
String fmtMin(int m) => m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:00' : '$m:00';

/// Размер: «3,4 МБ» считает вызывающий через t(); здесь — число мегабайт как в веб-версии
String megabytes(int bytes) => (bytes / 1048576).toStringAsFixed(bytes < 10485760 ? 1 : 0);

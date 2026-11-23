// Похожие по написанию слова — для подсказок «Возможно, вы искали» (поиск по стихам, словарь, карты).
import 'dart:math' as math;

/// Расстояние Дамерау — Левенштейна (вставка, удаление, замена, перестановка соседних букв)
int fuzzyDistance(List<int> a, List<int> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev2 = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) v = math.min(v, prev2[j - 2] + 1);
      cur[j] = v;
    }
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// Сколько ошибок прощаем слову такой длины: одну на каждые три буквы, но не меньше одной
int fuzzyAllowed(int length) => math.max(1, length ~/ 3);

/// Насколько слово n близко к запросу q: расстояние до всего слова или до его начала такой же длины (недописанное
/// слово тоже подходит, но на единицу хуже); null — слишком далеко
int? fuzzyScore(List<int> q, List<int> n, int allowed) {
  var best = 1 << 30;
  if ((n.length - q.length).abs() <= allowed) best = fuzzyDistance(q, n);
  if (n.length > q.length) best = math.min(best, fuzzyDistance(q, n.sublist(0, q.length)) + 1);
  return best <= allowed ? best : null;
}

/// «ё» = «е», нижний регистр, без знаков ударения — как в поиске
String fuzzyFold(String s) => s.toLowerCase().replaceAll('ё', 'е').replaceAll('́', '');

import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.openInMemory();
  print('SQLite ${sqlite3.version.libVersion}');
  db.execute("CREATE VIRTUAL TABLE t USING fts5(x, tokenize='unicode61 remove_diacritics 2')");
  db.execute("INSERT INTO t VALUES ('В начале сотворил Бог небо и землю'), ('И сказал Бог: да будет свет')");
  print(db.select("SELECT rowid, highlight(t, 0, '[', ']') h FROM t WHERE t MATCH 'бог*'").map((r) => r['h']).toList());
  db.close();
}

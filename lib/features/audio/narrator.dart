// Запасной диктор: когда для главы нет записи, движок спрашивает его, не прочтёт ли он главу сам.
// Пока заглушка: возвращает false, и человек видит прежнее сообщение «Для этой главы нет аудиозаписи.»
// Ведущая сессия подключит сюда другого диктора (вернуть true, если чтение началось).
import '../../core/books.dart';

Future<bool> narrateFallback({required int pane, required String moduleId, required VerseRef from}) async => false;

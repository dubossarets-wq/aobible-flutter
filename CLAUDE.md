# AO Bible на Flutter

Перенос веб-приложения AO Bible (React + Capacitor, исходники: `G:\AO Bible\src`) на Flutter — та же функциональность
и тот же вид, но быстрее. Веб-версия — образец: тексты кнопок, порядок пунктов, поведение берём оттуда.

## Общение и стиль
- С владельцем — только по-русски. Комментарии в коде — по-русски, коротко, «почему», как в существующих файлах.
- Код — как в соседних файлах: Riverpod 3 (`Notifier`/`NotifierProvider`, без legacy `StateProvider`), без лишних абстракций.

## Окружение (всё на диске E:, на C: мало места)
```sh
. /g/flutter-sdk/env.sh      # PATH к Flutter, PUB_CACHE, ANDROID_HOME, JAVA_HOME
flutter analyze lib/features/<ваша папка>
flutter test test/<ваш тест>.dart
```
Сборки (`flutter build ...`) и `flutter pub add` — НЕ запускать: их делает ведущая сессия (параллельные сборки ломают друг друга).
Нужен пакет, которого нет в pubspec.yaml, — напишите об этом в отчёте.

## Устройство
- `lib/core/` — ядро: `modules.dart` (модули: JSON с aobible.app → SQLite на устройстве; не-библейские модули
  пока хранят исходный JSON в таблице `payload` — разбирайте под свою функцию: можно добавить таблицы при установке,
  но тогда правьте `_convert` аккуратно и только свою ветку `type`), `bible.dart` (книга ленивым списком, поиск FTS5),
  `books.dart` (книги, разбор ссылок, `VerseRef`), `markup.dart` (разметка стиха, `Token`), `settings.dart`
  (настройки, темы `Palette`, `prefs`), `panes.dart` (панели, переходы, `livePositions`, `SyncHub`), `i18n.dart` (`t()`).
- `lib/ui/` — оболочка: главный экран, панель чтения, строка стиха (`verse_view.dart`), «Перейти», поиск.
- `lib/features/<имя>/` — функции. Каждая — своя папка и своя `register()` (вызов в `lib/features/features.dart`).
  Подключение к читалке и оболочке — только через `lib/features/hub.dart`:
  `Hub.onWordTap`, `Hub.verseDecorators`, `Hub.selectionBar`, `Hub.openPlans/openBookmarks/openMore/...`,
  `Hub.audioBar`, `Hub.afterStart`; выделение — `selectionProvider`; после изменения отметок — `decorVersionProvider.notifier.bump()`.
- Править файлы вне своей папки нельзя, кроме одной строки своей `register()` в `features.dart`. Нужна новая точка
  в `hub.dart` или правка ядра — опишите в отчёте, что и зачем (ведущая сессия добавит).

## Данные
- Пользовательские данные (закладки, заметки, выделения, проповеди, планы, настройки) — в `prefs` (JSON, ключи как
  в веб-версии: `bookmarks`, `notes`, `highlights`, `favorites`, `collections`, `sermons`, `plans`…), форматы — как
  в веб-версии (`G:\AO Bible\src\core\*.js`), чтобы перенос из старого приложения и файлы «Мои данные» подходили.
- Не терять и не сбрасывать данные и настройки людей при обновлениях.

## Языки
- Все надписи — через `t('Русская фраза')`; словари `assets/i18n/<язык>.json` взяты из веб-версии — по возможности
  используйте те же фразы, что в веб-версии (они уже переведены на 21 язык). Новая фраза — добавьте перевод во все
  21 файл (кроме ru — его нет). Тексты Библии, словарей и комментариев не переводим (никакого машинного перевода).

## Лицензии и права
- Только общественное достояние, свободные лицензии или с разрешения. Подписи источников (карты, иллюстрации, словари)
  — как в веб-версии. Синтез речи в публикуемых записях не используем. Приложение бесплатное и некоммерческое.

## Скорость
- Цель — быстрее веб-версии во всём: тяжёлое — в `Isolate.run`, данные — запросами к SQLite, списки — ленивые
  (`ListView.builder`), без лишних перестроек (Riverpod `select`).

## Дизайн — один в один с веб-версией
- Образец — живая веб-версия: компоненты `G:\AO Bible\src\components\*.jsx` и стили `G:\AO Bible\src\styles.css`
  (внимание: многие правила переопределены ниже по файлу — смотрите последние правила для селектора).
  Эталонные снимки экранов (телефон 400 px, светлая тема): папка
  `C:\Users\stude\AppData\Local\Temp\claude\e--AO-Bible\2de710ea-f53d-4c78-909a-aa1d1c5e1a55\scratchpad\web\`.
  Свои снимки веб-версии можно снять скриптом `…\scratchpad\webref.mjs` (Playwright, локальный сервер dist/pwa) — скопируйте
  и допишите шаги под свои экраны (`node <скрипт>`).
- Значки — только Lucide (`LucideIcons.*`, те же, что импортирует компонент веб-версии из lucide-react: `BookOpen` →
  `LucideIcons.bookOpen`). Material `Icons.*` не использовать.
- Общие элементы — `lib/ui/kit.dart`: `showAobSheet`/`AobSheet` (нижние окна), `PrefRow`, `MenuRow`, `MenuSep`, `GroupTitle`,
  `AobButton`, `AobChip`, `AobSwitch`, `SwitchRow`, `Segmented`, `IconBtn`, `AobInput`, `RoundFab`, `mix()`, `kRadius`.
  Не использовать Material-виджеты с чужим видом: ListTile, Switch, FilledButton, SegmentedButton, AlertDialog, NavigationBar.
- Цвета — только из `Palette` (тема + свои цвета), смеси — `mix(a, доля, b)` как color-mix в CSS. Шрифт интерфейса 15 px, 1rem = 16 px.

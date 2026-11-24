# QA_PROGRESS — аудит Swift и Flutter (24.11.2026)

## Сделано
- Flutter `dart analyze lib`: было 10 замечаний → осталось 2 (стиль prefer_initializing_formals в ios_style.dart, исправить нельзя без приватных именованных параметров).
  Убраны: неиспользуемая переменная verses (sermons_sheet), неиспользуемый _busy (reader_pane), forEach-литерал (books), лишний импорт (account_sync), if без скобок (sermon_pdf), null-aware элемент (interlinear_sheet).
- Flutter жизненный цикл: поля-контроллеры/таймеры без dispose — не найдено; setState/context после await без mounted — не найдено.
- Swift (поиск по коду): print/TODO/try! на данных извне — нет.

## В работе
- Swift Core: ревью агентом (только чтение), затем правки.

## Очередь
- Swift Views: ReaderView, PagedChapter, DictionarySheet, StudyViews, остальное.
- Flutter: ui/, features/ — повторы дублей, паритет с Swift.
- Сборки: iOS (gh workflow ios-native.yml + словарь), Android (build_android.sh).

## Не проверено (нет устройства/симулятора)
- Поведение на устройствах, вход Google и синхронизация (нет Client ID).

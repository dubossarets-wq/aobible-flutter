# QA_PROGRESS — аудит Swift и Flutter (24.11.2026)

## Сделано
- Flutter `dart analyze lib`: было 10 замечаний → осталось 2 (стиль prefer_initializing_formals в ios_style.dart, исправить нельзя без приватных именованных параметров).
  Убраны: неиспользуемая переменная verses (sermons_sheet), неиспользуемый _busy (reader_pane), forEach-литерал (books), лишний импорт (account_sync), if без скобок (sermon_pdf), null-aware элемент (interlinear_sheet).
- Flutter жизненный цикл: поля-контроллеры/таймеры без dispose — не найдено; setState/context после await без mounted — не найдено.
- Swift (поиск по коду): print/TODO/try! на данных извне — нет.

## Swift Core (ревью агентом, 18 пунктов) — все исправлены
- сборка #177: busy_timeout, повторная установка, DST у напоминаний, таймер сна, вход Google, цикл pull, границы импорта, «Глава», дубли онлайн-глав, импорт не на главном потоке, история после перехода.
- далее: защита от потери данных (.bak, не обнулять неразобранный ключ), гонка синхронизации (touched/snap), выход во время синхронизации, кэш индексов поиска (6 штук + нехватка памяти + сброс при замене), адреса аудио по книгам, разбор частей словарей вне главного потока.

## В работе
- Swift Views: ReaderView и основа — агент (только чтение).

## Очередь
- Swift Views: ReaderView, PagedChapter, DictionarySheet, StudyViews, остальное.
- Flutter: ui/, features/ — повторы дублей, паритет с Swift.
- Сборки: iOS (gh workflow ios-native.yml + словарь), Android (build_android.sh).

## Не проверено (нет устройства/симулятора)
- Поведение на устройствах, вход Google и синхронизация (нет Client ID).

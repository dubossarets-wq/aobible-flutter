# AO Bible на iPhone — установка с Макбука

Платный аккаунт Apple для своего iPhone не нужен: хватает обычного Apple ID. Ограничение бесплатной установки —
приложение работает 7 дней, потом его нужно поставить заново (шаг 6). Для App Store и TestFlight нужен
Apple Developer Program ($99 в год).

## 1. Один раз подготовить Макбук
1. App Store → установить **Xcode**. Открыть его один раз, согласиться с лицензией; когда предложит — поставить
   компоненты для iOS.
2. Терминал:
   ```sh
   xcode-select --install
   brew install --cask flutter      # если нет Homebrew: https://brew.sh
   brew install cocoapods
   flutter doctor                   # всё, что относится к iOS, должно быть ✓
   ```

## 2. Получить код
Через GitHub (если папка выложена в репозиторий):
```sh
git clone https://github.com/dubossarets-wq/aobible-flutter.git
cd aobible-flutter
```
Или скопировать папку `E:\aobible-flutter` на Макбук (без папок `build` и `.dart_tool`).

## 3. Подготовить проект
```sh
flutter pub get
cd ios && pod install && cd ..
```

## 4. iPhone
1. Подключить кабелем, на iPhone нажать «Доверять этому компьютеру».
2. iPhone: Настройки → Конфиденциальность и безопасность → **Режим разработчика** → включить (телефон перезагрузится).

## 5. Подпись (один раз)
1. `open ios/Runner.xcworkspace` — откроется Xcode.
2. Слева выбрать **Runner** → вкладка **Signing & Capabilities** → **Team** → **Add an Account…** → войти своим Apple ID →
   выбрать «(Personal Team)».
3. Если Xcode пишет, что идентификатор `app.aobible` занят, — заменить Bundle Identifier на `app.aobible.dev`.

## 6. Поставить на iPhone
```sh
flutter run --release
```
(или в Xcode выбрать свой iPhone вверху и нажать ▶).
При первом запуске iPhone скажет «Ненадёжный разработчик»: Настройки → Основные → **VPN и управление устройством** →
свой Apple ID → «Доверять».

## Что на iPhone пока не работает
- Виджет «Стих дня» (сделан только для Android).
- Перенос закладок из прежнего приложения (на iPhone прежнего приложения не было).

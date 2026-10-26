#!/bin/sh
# Сборка для Google Play: AAB, подписанный ключом загрузки (G:\android-build\keys).
# versionCode = 40 000 000 + минуты с 1.1.2026 — больше, чем у прежнего приложения (30 000 000 + …), обновление пройдёт.
# Запуск: sh tool/build_play.sh 2.0
. /g/flutter-sdk/env.sh
cd "$(dirname "$0")/.."
NAME=${1:-2.0}
CODE=$(( 40000000 + ( $(date -u +%s) - $(date -u -d 2026-01-01 +%s) ) / 60 ))
export AOB_KEYSTORE=G:/android-build/keys/aobible-upload.jks
export AOB_KEY_PASS="$(tr -d '\r\n' < /g/android-build/keys/password.txt)"
flutter build appbundle --release --build-name="$NAME" --build-number="$CODE" || exit 1
mkdir -p /g/android-build/out
cp build/app/outputs/bundle/release/app-release.aab "/g/android-build/out/aobible-flutter-$NAME-$CODE.aab"
echo "ГОТОВО: G:/android-build/out/aobible-flutter-$NAME-$CODE.aab (versionCode $CODE)"

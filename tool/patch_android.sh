#!/usr/bin/env bash
# Патчинг Android-конфигурации после `flutter create`:
#  1. Разрешения INTERNET + MANAGE_EXTERNAL_STORAGE (доступ к Obsidian Vault)
#  2. Запросы для Health Connect
#  3. Имя приложения "System: Hermes"
#  4. minSdk 28 (требуется flutter_health_connect)
set -e

MANIFEST="android/app/src/main/AndroidManifest.xml"
GRADLE="android/app/build.gradle.kts"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: AndroidManifest.xml не найден. Запусти `flutter create --platforms android .`."
  exit 1
fi

# 1. Разрешения: интернет и доступ к внешнему хранилищу (для Obsidian Vault)
sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n    <application>|' "$MANIFEST"

# 2. Health Connect: запросы и пермишен на чтение шагов
sed -i 's|</manifest>|<queries>\n        <package android:name="com.google.android.apps.healthdata" />\n    </queries>\n</manifest>|' "$MANIFEST"
sed -i 's|<application|<uses-permission android:name="android.permission.health.READ_STEPS"/>\n    <uses-permission android:name="android.permission.health.READ_EXERCISE"/>\n    <application>|' "$MANIFEST"

# 3. Имя приложения в лаунчере
sed -i 's|android:label="system_hermes"|android:label="System: Hermes"|' "$MANIFEST"

# 4. minSdk 28 (Health Connect требует 26+, рекомендуем 28)
if [ -f "$GRADLE" ]; then
  sed -i 's|minSdk = flutter.minSdkVersion|minSdk = 28|' "$GRADLE" || true
fi

echo "OK: Android-конфигурация пропатчена."

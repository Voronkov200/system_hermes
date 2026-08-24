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

# 1. Разрешения: интернет, доступ к внешнему хранилищу (Obsidian), микрофон (запись голоса)
sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <application>|' "$MANIFEST"

# 2. Health Connect: запросы и пермишен на чтение шагов
sed -i 's|</manifest>|<queries>\n        <package android:name="com.google.android.apps.healthdata" />\n    </queries>\n</manifest>|' "$MANIFEST"
sed -i 's|<application|<uses-permission android:name="android.permission.health.READ_STEPS"/>\n    <uses-permission android:name="android.permission.health.READ_EXERCISE"/>\n    <application>|' "$MANIFEST"

# 3. Имя приложения в лаунчере
sed -i 's|android:label="system_hermes"|android:label="System: Hermes"|' "$MANIFEST"

# 4. minSdk 28 (Health Connect требует 26+, рекомендуем 28)
if [ -f "$GRADLE" ]; then
  sed -i 's|minSdk = flutter.minSdkVersion|minSdk = 28|' "$GRADLE" || true

  # 4a. Стабильная подпись: явный signingConfig release из переменных
  # окружения (HERMES_KEYSTORE и др.). Без этого каждый CI-раннер
  # генерирует свой debug-ключ и обновление APK на телефоне ломается.
  sed -i 's|signingConfig = signingConfigs.getByName("debug")|signingConfig = signingConfigs.getByName("release")|' "$GRADLE" || true
  sed -i 's|buildTypes {|signingConfigs {\n            create("release") {\n                storeFile = file(System.getenv("HERMES_KEYSTORE") ?: "../../tool/debug.keystore")\n                storePassword = System.getenv("HERMES_STORE_PASSWORD") ?: "android"\n                keyAlias = System.getenv("HERMES_KEY_ALIAS") ?: "androiddebugkey"\n                keyPassword = System.getenv("HERMES_KEY_PASSWORD") ?: "android"\n            }\n        }\n        buildTypes {|' "$GRADLE" || true
fi

# 4b. flutter_health_connect 1.2.3 пинит compileSdk 33 — зависимости требуют 34+.
HCPLUGIN="$HOME/.pub-cache/hosted/pub.dev/flutter_health_connect-1.2.3/android/build.gradle"
if [ -f "$HCPLUGIN" ]; then
  sed -i 's|compileSdkVersion 33|compileSdkVersion 36|' "$HCPLUGIN"
fi

# 5. AGP 9 требует namespace у всех library-модулей; старые плагины
#    (flutter_health_connect) его не задают — берём package из манифеста.
ROOT_GRADLE="android/build.gradle.kts"
if [ -f "$ROOT_GRADLE" ]; then
  grep -q "AGP 9 namespace fallback" "$ROOT_GRADLE" || cat >> "$ROOT_GRADLE" <<'EOF'

// AGP 9 namespace fallback
subprojects {
    plugins.withId("com.android.library") {
        // file_picker 11 не применяет kotlin-android под AGP 9 (рассчитывает на built-in
        // Kotlin, который Flutter отключает) — применяем сами.
        if (!plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            apply(plugin = "org.jetbrains.kotlin.android")
        }
        extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
            if (namespace.isNullOrEmpty()) {
                val mf = project.projectDir.resolve("src/main/AndroidManifest.xml")
                val pkg = Regex("""package\s*=\s*"([^"]+)"""").find(mf.readText())?.groupValues?.get(1)
                if (pkg != null) namespace = pkg
            }
        }
    }
}
EOF
fi

# 6. flutter_health_connect 1.2.3 ставит Java target 1.8, а Kotlin берёт JDK-дефолт
#    (напр. 21) — несоответствие JVM-таргетов роняет release-сборку.
#    Включаем мягкую валидацию таргета (общая для локальной сборки и CI).
GRADLE_PROPS="android/gradle.properties"
if [ -f "$GRADLE_PROPS" ]; then
  grep -q "kotlin.jvm.target.validation.mode" "$GRADLE_PROPS" || \
    printf '\n# flutter_health_connect 1.2.3: Java target 1.8 vs Kotlin target от JDK-дефолта (21).\n# Мягкая валидация JVM-таргета — иначе release-сборка падает.\nkotlin.jvm.target.validation.mode=warning\n' >> "$GRADLE_PROPS"
fi

echo "OK: Android-конфигурация пропатчена."

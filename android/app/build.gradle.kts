plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.aobible"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Нужно flutter_local_notifications (напоминания о плане чтения)
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.aobible"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Как у прежнего приложения в Google Play (Android 7.0) — ни одно устройство не теряем
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "AO Bible"
    }

    // Подпись ключом загрузки Google Play (тот же, что у прежнего приложения): путь и пароль — из окружения
    // (tool/build_play.sh), в репозиторий не попадают. Без них выпускная сборка подписывается отладочным ключом.
    signingConfigs {
        create("upload") {
            val ks = System.getenv("AOB_KEYSTORE")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("AOB_KEY_PASS")
                keyAlias = "upload"
                keyPassword = System.getenv("AOB_KEY_PASS")
            }
        }
    }

    buildTypes {
        // Проверочная сборка ставится рядом с приложением из Google Play (другой идентификатор и название):
        // не нужно удалять прежнее приложение, данные людей не трогаются
        debug {
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appName"] = "AO Bible Flutter"
        }
        // Проверочная сборка с настоящей скоростью (машинный код, как в выпуске) — тоже рядом с приложением из Play
        getByName("profile") {
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appName"] = "AO Bible Flutter"
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = if (System.getenv("AOB_KEYSTORE") != null) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // FIX (fitur baru): membaca google-services.json saat build, supaya
    // Firebase.initializeApp() di Flutter otomatis terhubung ke project
    // Firebase yang benar tanpa perlu konfigurasi manual tambahan.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.tiodoras_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // FIX (fitur baru): wajib untuk plugin flutter_local_notifications
        // (dipakai fcm_service.dart) — tanpa ini build APK release gagal
        // dengan error "requires core library desugaring to be enabled".
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.tiodoras_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FIX (fitur baru): library desugaring yang diaktifkan di atas butuh
    // dependency ini supaya benar-benar tersedia saat compile.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

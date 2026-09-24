plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mobile"
    // receive_sharing_intent butuh compileSdk 37+; default flutter.compileSdkVersion
    // di Flutter 3.44.6 masih 36. Di-hardcode ke 37 (SDK-nya sudah terinstal).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Keystore release cuma ada di CI (di-decode dari GitHub Secrets, lihat
    // .github/workflows/android-release.yml). Kunci yang SAMA di tiap build
    // wajib supaya APK baru bisa menimpa versi lama di HP tester -- debug key
    // CI berbeda tiap runner. Build lokal tanpa file ini tetap pakai debug key.
    val releaseKeystore = file("release.jks")
    signingConfigs {
        if (releaseKeystore.exists()) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeystore.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
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
    // Kontrol eksplisit atas splash-screen sistem Android 12+ (lihat catatan
    // di styles.xml / MainActivity.kt) -- dibutuhkan karena mekanisme
    // auto-dismiss bawaan Flutter tidak konsisten waktu Activity dibuat lewat
    // trampoline share-sheet (BLOKIR-D di docs/plan.md).
    implementation("androidx.core:core-splashscreen:1.0.1")
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mobile"
    // receive_sharing_intent needs compileSdk 37+; the default flutter.compileSdkVersion
    // in Flutter 3.44.6 is still 36. Hardcoded to 37 (that SDK is installed).
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

    // The release keystore only exists in CI (decoded from GitHub Secrets, see
    // .github/workflows/android-release.yml). The SAME key on every build is
    // required so a new APK can install over the old one on testers' phones --
    // CI's debug key differs per runner. Local builds without this file use the debug key.
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
    // Explicit control over the Android 12+ system splash screen (see the
    // notes in styles.xml / MainActivity.kt) -- needed because Flutter's
    // built-in auto-dismiss is unreliable when the Activity is created via the
    // share-sheet trampoline (see "Gotchas" in CLAUDE.md).
    implementation("androidx.core:core-splashscreen:1.0.1")
}

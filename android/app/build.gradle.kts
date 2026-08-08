plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dreamviz.exodus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time, which does not exist below
        // API 26. Without desugaring the build fails outright.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Matches the iOS bundle identifier so both stores point at one app.
        applicationId = "com.dreamviz.exodus"
        // Pinned rather than inherited from flutter.minSdkVersion: amplify_auth_cognito
        // and amplify_api require 24, and flutter_webrtc requires 23. Letting the
        // Flutter default drift below either one breaks the manifest merge.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys, so sideloaded test builds install and `flutter run
            // --release` works. A Play Store upload needs a real keystore and
            // an app bundle instead — see "Android builds" in the README.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

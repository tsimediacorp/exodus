import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real signing key, if one exists. android/key.properties is gitignored and
// holds storeFile/storePassword/keyAlias/keyPassword.
//
// This matters far beyond the Play Store. Android identifies an app by its
// SIGNATURE: an update only installs over an existing app when both are signed
// by the same key. The debug key below is generated per-machine and is
// regenerated whenever it is deleted or expires — the moment it changes, the
// update is REFUSED, the only way forward is uninstall-and-reinstall, and that
// takes every conversation, devotional and saved verse with it.
//
// A stable release key is therefore the fix for "updates wipe my history", not
// merely a store requirement.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signed with the real key when android/key.properties is present,
            // and only then does an update install over the previous build
            // instead of demanding an uninstall that destroys the user's data.
            //
            // Falling back to the debug key keeps `flutter run --release` and
            // sideloading working for anyone without the keystore — but any
            // build made that way is disposable, because its signature is not
            // guaranteed to match the last one.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

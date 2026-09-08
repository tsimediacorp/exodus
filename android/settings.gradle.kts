pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Reads android/app/google-services.json so FCM knows which project this
    // build belongs to. That file is a CLIENT config, not a credential: it
    // already ships inside every APK and can be regenerated any time with
    // `firebase apps:sdkconfig ANDROID <appId> --project exodus-tsi`.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")

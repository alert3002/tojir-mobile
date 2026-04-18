plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

android {
    namespace = "tj.tojir.tojir_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tj.tojir.tojir_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing (required for Google Play).
    // Create `mobile/android/key.properties` (do NOT commit it) with:
    // storeFile=../keystore/tojir-release.jks
    // storePassword=*****
    // keyAlias=*****
    // keyPassword=*****
    val keystorePropsFile = rootProject.file("key.properties")
    val keystoreProps = Properties()
    val hasReleaseKeystore = keystorePropsFile.exists()
    if (hasReleaseKeystore) {
        keystorePropsFile.inputStream().use { keystoreProps.load(it) }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val storeFilePath = (keystoreProps["storeFile"] as String?)?.trim().orEmpty()
                storeFile = rootProject.file(storeFilePath)
                storePassword = (keystoreProps["storePassword"] as String?)?.trim()
                keyAlias = (keystoreProps["keyAlias"] as String?)?.trim()
                keyPassword = (keystoreProps["keyPassword"] as String?)?.trim()
            }
        }
    }

    buildTypes {
        release {
            // Google Play requires a non-debug signature.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Keep local builds possible, but Play Console will reject this.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

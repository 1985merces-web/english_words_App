import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val isReleaseTask =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

if (isReleaseTask && !keystorePropertiesFile.exists()) {
    error("Missing android/key.properties for release signing. Create it to build signed release bundles/APKs.")
}

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mrcsglobal.volary"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    flavorDimensions += "dist"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mrcsglobal.volary"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    productFlavors {
        create("play") {
            dimension = "dist"
            applicationId = "com.mrcsglobal.volary"
        }
        create("site") {
            dimension = "dist"
            applicationId = "com.mrcsglobal.volary.site"
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath =
                (keystoreProperties["storeFile"] as String?) ?: error("Missing storeFile in android/key.properties")
            storeFile = rootProject.file(storeFilePath)
            storePassword =
                (keystoreProperties["storePassword"] as String?)
                    ?: error("Missing storePassword in android/key.properties")
            keyAlias =
                (keystoreProperties["keyAlias"] as String?) ?: error("Missing keyAlias in android/key.properties")
            keyPassword =
                (keystoreProperties["keyPassword"] as String?) ?: error("Missing keyPassword in android/key.properties")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}


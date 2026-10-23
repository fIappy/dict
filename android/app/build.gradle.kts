plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Kokoro model travels inside the APK: the app reads it from its own assets
// on first launch, so the engine works right after install — no computer, no
// download, no import step. The archive is produced by
// `python tool/fetch_kokoro_model.py --zip-only` and is not in git; without it
// the build still succeeds and the app reports that the model is missing.
val kokoroArchive = rootProject.layout.projectDirectory.file("../tts-models/kokoro.zip")
val bundledKokoroModels = layout.buildDirectory.dir("generated/kokoroModels")
val copyKokoroModels = tasks.register<Copy>("copyKokoroModels") {
    onlyIf { kokoroArchive.asFile.exists() }
    from(kokoroArchive) { into("") }
    into(bundledKokoroModels)
}
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }
    .configureEach { dependsOn(copyKokoroModels) }

android {
    namespace = "com.example.local_dict"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // AGP's SourceSet API refuses a Provider here; the directory is filled by
    // copyPiperModels, which every merge*Assets task depends on.
    sourceSets["main"].assets.srcDir(bundledKokoroModels.get().asFile)

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.local_dict"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

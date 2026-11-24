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

// The 5.4w COCA learning database travels the same way: the app copies it out
// of its own assets on first launch, so 查词 works offline right after install
// with no import step. Built by tool/build_coca_pack.py; absent on machines
// without content/ and the build still succeeds.
val cocaLexicon = rootProject.layout.projectDirectory.file("../content/coca-ai/pack/coca_learn.db")
val bundledCocaLexicon = layout.buildDirectory.dir("generated/cocaLexicon")
val copyCocaLexicon = tasks.register<Copy>("copyCocaLexicon") {
    onlyIf { cocaLexicon.asFile.exists() }
    from(cocaLexicon) { into("") }
    into(bundledCocaLexicon)
}
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }
    .configureEach { dependsOn(copyCocaLexicon) }

android {
    namespace = "com.example.local_dict"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // AGP's SourceSet API refuses a Provider here; the directory is filled by
    // copyPiperModels, which every merge*Assets task depends on.
    sourceSets["main"].assets.srcDir(bundledKokoroModels.get().asFile)
    sourceSets["main"].assets.srcDir(bundledCocaLexicon.get().asFile)

    androidResources {
        // Avoid double-deflating the already compressed 141 MB kokoro.zip bundle.
        noCompress += "zip"
    }

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

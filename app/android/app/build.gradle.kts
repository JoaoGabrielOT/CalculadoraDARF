plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val caminhoChave = System.getenv("ANDROID_KEYSTORE_PATH")
val senhaChave = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val temChave = !caminhoChave.isNullOrEmpty() && !senhaChave.isNullOrEmpty()

android {
    namespace = "io.github.joaogabrielot.calculadoradarf"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // exigido pelo flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.joaogabrielot.calculadoradarf"
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

    // O Flet usava a mesma senha para a keystore e para a chave.
    signingConfigs {
        create("release") {
            if (temChave) {
                storeFile = file(caminhoChave!!)
                storePassword = senhaChave
                keyAlias = "calculadoradarf"
                keyPassword = senhaChave
            }
        }
    }

    buildTypes {
        release {
            // Sem os segredos o build local assina com a chave de debug; o CI confere os segredos antes.
            signingConfig = signingConfigs.getByName(if (temChave) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

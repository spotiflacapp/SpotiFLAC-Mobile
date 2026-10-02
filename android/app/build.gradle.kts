import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val rustBackendDir = rootProject.file("../rust_backend")
val rustAndroidAbis = providers.environmentVariable("SPOTIFLAC_RUST_ANDROID_ABIS")
    .orElse("arm64-v8a,armeabi-v7a")
    .get()
    .split(",")
val supportedRustAndroidAbis = setOf("arm64-v8a", "armeabi-v7a")
require(rustAndroidAbis.size == rustAndroidAbis.toSet().size) {
    "SPOTIFLAC_RUST_ANDROID_ABIS must not contain duplicate ABIs"
}
require(rustAndroidAbis.all { it in supportedRustAndroidAbis }) {
    "SPOTIFLAC_RUST_ANDROID_ABIS must contain only arm64-v8a and/or armeabi-v7a"
}

android {
    namespace = "com.zarz.spotiflac"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets.getByName("main") {
        java.srcDir("src/rust/kotlin")
        java.srcDir(rustBackendDir.resolve("target/bindings/kotlin"))
        jniLibs.srcDir(rustBackendDir.resolve("target/android/jniLibs"))
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_25
        targetCompatibility = JavaVersion.VERSION_25
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_25)
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                // V4 lives in a separate .apk.idsig file used for
                // `adb install --incremental`; the APK itself is unchanged.
                enableV4Signing = true
            }
        }
    }

    defaultConfig {
        applicationId = "com.zarz.spotiflac.missingtracks"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        externalNativeBuild {
            cmake { arguments += "-DANDROID_STL=c++_static" }
        }

        ndk {
            abiFilters.clear()
            abiFilters += rustAndroidAbis
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            ndk {
                debugSymbolLevel = "FULL"
            }
        }

        getByName("profile") {
            ndk {
                debugSymbolLevel = "FULL"
            }
        }

        release {
            // For local builds: use release signing if key.properties exists
            // For CI builds: APK is signed by GitHub Action after build
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
    }

    // Split APKs by ABI for smaller individual downloads
    splits {
        abi {
            isEnable = true
            reset()
            include(*rustAndroidAbis.toTypedArray())
            isUniversalApk = true // Also generate universal APK
        }
    }
}

val buildRustBackend = tasks.register<Exec>("buildRustBackend") {
    workingDir(rootProject.projectDir.parentFile)
    commandLine("bash", "scripts/build_rust_backend.sh", "android")
    environment("SPOTIFLAC_RUST_ANDROID_ABIS", rustAndroidAbis.joinToString(","))
    environment(
        "ANDROID_NDK_HOME",
        System.getenv("ANDROID_NDK_HOME")
            ?: android.sdkDirectory.resolve("ndk/29.0.14206865").absolutePath,
    )
    inputs.files(fileTree(rustBackendDir) {
        include("**/*.rs", "**/*.toml", "**/*.lock", "**/*.js", "**/*.tsv", "**/*.pem")
        exclude("target/**", "smoke/**")
    })
    inputs.property("SPOTIFLAC_RUST_ANDROID_ABIS", rustAndroidAbis.joinToString(","))
    inputs.file(rootProject.file("../scripts/build_rust_backend.sh"))
    outputs.dir(rustBackendDir.resolve("target/bindings/kotlin"))
    outputs.dir(rustBackendDir.resolve("target/android/jniLibs"))
}
tasks.named("preBuild").configure { dependsOn(buildRustBackend) }

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("net.java.dev.jna:jna:5.19.1@aar")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
    implementation("androidx.documentfile:documentfile:1.1.0")
    implementation("androidx.activity:activity-ktx:1.13.0")
    // NativeDownloadFinalizer imports FFmpegKit APIs directly. The Flutter
    // plugin owns the runtime AAR; compileOnly avoids packaging it twice here.
    compileOnly("com.antonkarpenko:ffmpeg-kit-full:2.2.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}

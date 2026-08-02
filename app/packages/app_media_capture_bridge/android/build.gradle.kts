import java.util.Properties

plugins {
    id("com.android.library") version "8.9.1"
    id("org.jetbrains.kotlin.android") version "2.1.0"
}

fun flutterSdkRoot(): File {
    val explicit = providers.gradleProperty("flutter.sdk").orNull
        ?: System.getenv("FLUTTER_ROOT")
    if (!explicit.isNullOrBlank()) return file(explicit)

    val hostProperties = file("../../../apps/demo/android/local.properties")
    if (hostProperties.isFile) {
        val properties = Properties().apply { hostProperties.inputStream().use(::load) }
        val configured = properties.getProperty("flutter.sdk")
        if (!configured.isNullOrBlank()) return file(configured)
    }
    error("Flutter SDK not found. Set FLUTTER_ROOT or -Pflutter.sdk=<path>.")
}

val flutterRoot = flutterSdkRoot()
val flutterEngineVersion =
    "1.0.0-${file("${flutterRoot.path}/bin/cache/engine.stamp").readText().trim()}"

android {
    namespace = "com.example.media_capture"
    compileSdk = 35

    defaultConfig {
        minSdk = 23
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.isIncludeAndroidResources = true
    }

    lint {
        abortOnError = true
        warningsAsErrors = true
        checkDependencies = true
        disable += setOf("GradleDependency", "AndroidGradlePluginVersion")
    }
}

dependencies {
    val coroutinesVersion = "1.9.0"

    compileOnly("io.flutter:flutter_embedding_debug:$flutterEngineVersion")
    implementation(project(":media_capture_core"))
    implementation(project(":media_capture_ui"))
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$coroutinesVersion")

    testImplementation("io.flutter:flutter_embedding_debug:$flutterEngineVersion")
    testImplementation("junit:junit:4.13.2")
    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:$coroutinesVersion")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("androidx.test.ext:junit:1.2.1")
    testImplementation("org.robolectric:robolectric:4.14.1")

    androidTestImplementation("androidx.test:core-ktx:1.6.1")
    androidTestImplementation("androidx.test.ext:junit-ktx:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation(kotlin("test"))
}

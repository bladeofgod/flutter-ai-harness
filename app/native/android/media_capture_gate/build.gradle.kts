import com.android.build.api.dsl.LibraryExtension
import java.util.Properties

plugins {
    id("com.android.library") version "8.9.1"
    id("org.jetbrains.kotlin.android") version "2.1.0"
}

fun flutterSdkRoot(): File {
    val explicit = providers.gradleProperty("flutter.sdk").orNull
        ?: System.getenv("FLUTTER_ROOT")
    if (!explicit.isNullOrBlank()) return file(explicit)

    val hostProperties = file("../../../../apps/demo/android/local.properties")
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
    namespace = "com.example.mediacapture.gate"
    compileSdk = 35

    defaultConfig {
        minSdk = 23
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    lint {
        abortOnError = true
        warningsAsErrors = true
        checkDependencies = true
        disable += setOf("GradleDependency", "AndroidGradlePluginVersion")
    }
}

dependencies {
    compileOnly("io.flutter:flutter_embedding_debug:$flutterEngineVersion")
    implementation(project(":media_capture_core"))
    implementation(project(":media_capture_ui"))
    implementation(project(":media_capture_bridge"))

    androidTestImplementation("io.flutter:flutter_embedding_debug:$flutterEngineVersion")
    androidTestImplementation("androidx.activity:activity-ktx:1.10.1")
    androidTestImplementation("androidx.test:core-ktx:1.6.1")
    androidTestImplementation("androidx.test.ext:junit-ktx:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation(kotlin("test"))
}

project(":media_capture_core").plugins.withId("com.android.library") {
    project(":media_capture_core").extensions.configure<LibraryExtension> {
        sourceSets.getByName("test").java.srcDir(rootProject.file("src/coreTest/kotlin"))
    }
}

project(":media_capture_bridge").plugins.withId("com.android.library") {
    project(":media_capture_bridge").extensions.configure<LibraryExtension> {
        sourceSets.getByName("test").java.srcDir(rootProject.file("src/adapterTest/kotlin"))
        sourceSets.getByName("test").resources.srcDirs(
            rootProject.file("../../../../docs/infrastructure/contracts"),
            rootProject.file("../../../../docs/bridge/contracts"),
        )
    }
    project(":media_capture_bridge").dependencies.add(
        "testImplementation",
        "org.json:json:20240303",
    )
}

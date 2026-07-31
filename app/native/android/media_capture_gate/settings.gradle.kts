pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://storage.googleapis.com/download.flutter.io")
    }
}

rootProject.name = "media-capture-android-quality-gate"

include(":media_capture_core")
project(":media_capture_core").projectDir = file("../media_capture")

include(":media_capture_ui")
project(":media_capture_ui").projectDir = file("../media_capture_ui")

include(":media_capture_bridge")
project(":media_capture_bridge").projectDir = file("../../../packages/app_media_capture_bridge/android")

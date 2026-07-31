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

rootProject.name = "media-capture-android-bridge"

include(":media_capture_core")
project(":media_capture_core").projectDir = file("../../../native/android/media_capture")

include(":media_capture_ui")
project(":media_capture_ui").projectDir = file("../../../native/android/media_capture_ui")

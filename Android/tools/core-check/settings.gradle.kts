// Builds and tests only the shared game rules (:core), without the Android SDK:
//   gradle -p Android/tools/core-check :core:test
pluginManagement { repositories { mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { mavenCentral() } }
rootProject.name = "cnsnn-core-check"
include(":core")
project(":core").projectDir = file("../../core")

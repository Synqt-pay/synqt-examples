pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
// By default the demo installs the public base SDK from Maven Central, like a merchant's app, with no token.
// -Psynqt.card=true (or synqt.card=true in ~/.gradle/gradle.properties or local.properties) adds the `card`
// flavour with SYNQT's private card add-on, which needs access to it.
// -Psynqt.local=true builds the SDKs from the checkouts next to this repo instead, so SDK changes show up
// without publishing.
val localProperties = java.util.Properties().apply {
    file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
fun flag(name: String) = (providers.gradleProperty(name).orNull ?: localProperties.getProperty(name)).toBoolean()
val synqtLocal = flag("synqt.local")
val synqtCard = flag("synqt.card")
gradle.extra["synqt.card"] = synqtCard // read by build.gradle.kts

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        if (synqtCard && !synqtLocal) {
            // The card add-on is private: reading it needs a GitHub token with read:packages, never written into this repo.
            maven {
                name = "synqtAndroidCard"
                url = uri("https://maven.pkg.github.com/synqt-pay/synqt-android-card")
                credentials {
                    username = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).orNull
                    password = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).orNull
                }
                content { includeModule("com.synqt", "synqt-android-card") }
            }
        }
    }
}
rootProject.name = "synqt-android-demo"

if (synqtLocal) {
    // Check out synqt-android as `android` (and synqt-android-card as `android-card`, for card mode) next to this repo.
    includeBuild("../../android") {
        dependencySubstitution { substitute(module("com.synqt:synqt-android")).using(project(":synqt-sdk")) }
    }
    if (synqtCard) {
        includeBuild("../../android-card") {
            dependencySubstitution { substitute(module("com.synqt:synqt-android-card")).using(project(":synqt-sdk-card")) }
        }
    }
}

val synqtCard = gradle.extra["synqt.card"] as Boolean // set in settings.gradle.kts from synqt.card

plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.synqt.demo"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.synqt.demo"
        minSdk = 24
        targetSdk = 37
    }
    if (synqtCard) {
        // Card mode: one app, two flavours, base (the SDK alone) and card (plus the card add-on, for PCI DSS compliant merchants).
        flavorDimensions += "edition"
        productFlavors {
            create("base") { dimension = "edition" }
            create("card") { dimension = "edition" }
        }
    } else {
        sourceSets["main"].kotlin.directories += "src/base/kotlin" // the SDK alone, with no flavours
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("com.synqt:synqt-android:0.1.0") // with synqt.local=true, settings.gradle.kts builds it from the checkout
    if (synqtCard) "cardImplementation"("com.synqt:synqt-android-card:0.1.0") // the private card add-on, on top of the base SDK
    implementation(libs.androidx.activity) // ComponentActivity, which keeps the ViewModel through a rebuild
    implementation(libs.androidx.lifecycle.viewmodel.ktx) // viewModelScope
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.json) // android.jar's org.json is a stub in local unit tests
}

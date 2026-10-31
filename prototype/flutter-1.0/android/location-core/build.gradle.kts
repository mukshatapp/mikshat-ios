plugins { id("com.android.library") }
android {
    namespace = "app.organicmaps.sdk.location"
    compileSdk = 36
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets["main"].java.srcDir("../../vendor/organicmaps/android/sdk/location/core/src/main/java")
}
dependencies {
    implementation("androidx.annotation:annotation:1.10.0")
    implementation("androidx.core:core:1.17.0")
}

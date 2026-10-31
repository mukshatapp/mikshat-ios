plugins { id("com.android.library"); id("org.jetbrains.kotlin.android") }

android {
    namespace = "app.organicmaps.sdk"
    compileSdk = 36
    defaultConfig { minSdk = 24 }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    sourceSets["main"].apply {
        java.srcDir("../../vendor/organicmaps/android/sdk/src/main/java")
        res.srcDir("../../vendor/organicmaps/android/sdk/src/main/res")
    }
    androidResources { noCompress += listOf("mwm", "ttf", "bin") }
}

dependencies {
    api(project(":location-core"))
    api("androidx.lifecycle:lifecycle-process:2.9.4")
    api("androidx.recyclerview:recyclerview:1.4.0")
    api("androidx.fragment:fragment:1.8.9")
    implementation("androidx.annotation:annotation:1.10.0")
    implementation("androidx.core:core:1.17.0")
    implementation("androidx.media:media:1.7.1")
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }

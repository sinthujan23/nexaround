import java.util.Properties
import java.io.FileInputStream
import java.net.URL
import java.net.HttpURLConnection

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Resolve the Google Maps Android API key. Google's Maps SDK for Android reads the
// key ONLY from the manifest at build time — there is no runtime/DB API like iOS has.
// To keep the admin panel / DB as the single source of truth (no key in source),
// we resolve it in this order:
//   1) GOOGLE_MAPS_API_KEY env var          (CI secret / override)
//   2) GOOGLE_MAPS_API_KEY in gradle.properties (local/offline override)
//   3) backend /config/keys                 (admin-managed value stored in the DB)
fun resolveGoogleMapsApiKey(project: org.gradle.api.Project): String {
    val placeholder = "YOUR_GOOGLE_MAPS_API_KEY"
    System.getenv("GOOGLE_MAPS_API_KEY")
        ?.takeIf { it.isNotBlank() && it != placeholder }
        ?.let { return it }
    (project.findProperty("GOOGLE_MAPS_API_KEY") as? String)
        ?.takeIf { it.isNotBlank() && it != placeholder }
        ?.let { return it }
    return try {
        val conn = URL("https://api.nexaround.com/api/v1/config/keys")
            .openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 5000
        conn.readTimeout = 5000
        val body = conn.inputStream.bufferedReader().use { it.readText() }
        val key = Regex("\"google_maps_api_key\"\\s*:\\s*\"([^\"]+)\"")
            .find(body)?.groupValues?.get(1).orEmpty()
        if (key.isBlank()) {
            println("⚠️ google_maps_api_key not found in backend /config/keys response — Android map will be blank.")
        } else {
            println("✅ Google Maps Android key loaded from backend (admin-managed).")
        }
        key
    } catch (e: Exception) {
        println("⚠️ Could not fetch Google Maps key from backend (${e.message}); " +
            "Android map will be blank. Set GOOGLE_MAPS_API_KEY in gradle.properties to override.")
        ""
    }
}

android {
    namespace = "com.nexaround.nexaround_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
        freeCompilerArgs = freeCompilerArgs + "-Xskip-metadata-version-check"
    }

    defaultConfig {
        applicationId = "com.nexaround.nexaround_app"
        minSdk = 24 // Floor required by Mapbox/Firebase/ML Kit plugins
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Inject the admin-managed Google Maps key (env / gradle.properties / backend)
        // into the AndroidManifest placeholder used by the Maps SDK.
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = resolveGoogleMapsApiKey(project)
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Use the release signing config if key.properties exists, otherwise fallback to debug
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
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.1.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-analytics")
}

flutter {
    source = "../.."
}

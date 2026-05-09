import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.travelplan.travel_plan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.travelplan.travel_plan"
        // 高德部分设备需在 Manifest 中声明原生 Key；从 lib/config/amap_config.dart 的 _androidLocal 同步，避免两处手写。
        val amapDart = File(rootProject.projectDir, "../lib/config/amap_config.dart")
        val amapAndroidKey =
            if (amapDart.exists()) {
                val text = amapDart.readText()
                var k =
                    Regex("""_androidLocal\s*=\s*'([^']*)'""")
                        .find(text)
                        ?.groupValues
                        ?.get(1)
                        ?.trim()
                        .orEmpty()
                if (k.isEmpty()) {
                    k =
                        Regex("""_androidLocal\s*=\s*"([^"]*)"""")
                            .find(text)
                            ?.groupValues
                            ?.get(1)
                            ?.trim()
                            .orEmpty()
                }
                k
            } else {
                ""
            }
        manifestPlaceholders["AMAP_ANDROID_KEY"] = amapAndroidKey
        // 高德 3D 地图与定位插件建议 minSdk >= 21。
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keystorePropertiesFile.exists()) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
            // 高德地图 SDK 以 compileOnly 方式接入插件，开启 R8 会误报缺类；发布包关闭混淆。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

// 高德 3D 地图：amap_flutter_map 插件里对 SDK 使用 compileOnly，不会打进 APK，
// 运行时会 ClassNotFoundException（如 AMapOptions）。必须由宿主 implementation。
dependencies {
    implementation("com.amap.api:3dmap:8.1.0")
}

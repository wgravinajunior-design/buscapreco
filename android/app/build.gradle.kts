import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credenciais da keystore de release. O arquivo android/key.properties fica
// FORA do controle de versão (veja .gitignore) e deve conter:
//   storeFile=C:/caminho/para/buscapreco.jks
//   storePassword=...
//   keyAlias=buscapreco
//   keyPassword=...
// Sem esse arquivo o build de release continua funcionando assinado com a
// chave de debug, para não travar quem só quer rodar `flutter run --release`.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val temKeystoreDeRelease = keystorePropertiesFile.exists()
if (temKeystoreDeRelease) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.dusuco.buscapreco"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.dusuco.buscapreco"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (temKeystoreDeRelease) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (temKeystoreDeRelease) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "AVISO: android/key.properties não encontrado — o APK de release " +
                        "será assinado com a chave de DEBUG e não serve para distribuição."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

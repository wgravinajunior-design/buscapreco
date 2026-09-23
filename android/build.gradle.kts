allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Plugins antigos (ex.: flutter_bluetooth_serial, sem atualização desde 2021)
// não declaram "namespace" no build.gradle, exigido pelo Android Gradle
// Plugin atual. Preenche automaticamente a partir do "package" do
// AndroidManifest.xml do próprio plugin, sem precisar editar o pub cache.
subprojects {
    if (project.name == "app") return@subprojects
    afterEvaluate {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null) {
            android.compileSdkVersion(34)
            if (android.namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val pkg = groovy.xml.XmlSlurper().parse(manifestFile).getProperty("@package").toString()
                    if (pkg.isNotBlank()) {
                        android.namespace = pkg
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

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

// FORCE Kotlin version for older plugins (Fixed ar_flutter_plugin error)
subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin" && requested.name.startsWith("kotlin-gradle-plugin")) {
                useVersion("1.9.24")
            }
        }
    }
}

// Safer Auto-fix for older plugins missing 'namespace'
subprojects {
    val applyNamespaceFix = {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android") as? com.android.build.gradle.BaseExtension
            if (android != null && android.namespace == null) {
                android.namespace = "com.nexaround.${project.name.replace(":", ".")}"
            }
        }
    }

    if (project.state.executed) {
        applyNamespaceFix()
    } else {
        project.afterEvaluate { applyNamespaceFix() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

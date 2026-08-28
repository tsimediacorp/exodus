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

// flutter_webrtc pins `compileSdkVersion 31` in its own build.gradle, which is
// below what its androidx.fragment dependency demands — the AAR metadata check
// fails the build and there is nothing to edit inside a pub-cache package.
// Raising compileSdk only widens the APIs available at compile time; each
// module keeps its own minSdk, so nothing about runtime support changes.
//
// This has to run before the evaluationDependsOn below (which forces :app to
// evaluate during root configuration, after which registering an afterEvaluate
// hook throws), and from afterEvaluate rather than directly, so it lands after
// the plugin's own build script has set its lower value.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder {
            setProperty("compileSdk", 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

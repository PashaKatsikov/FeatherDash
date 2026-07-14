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

    // -----------------------------------------------------------------
    // Force every Android library plugin to compile against the same
    // compileSdk the app uses (36). Some plugin releases hard-code
    // compileSdk=34 while their transitive deps require 36, tripping
    // Gradle's CheckAarMetadata with:
    //   > Dependency 'foo' requires libraries to compile against
    //     version 36 or later of the Android APIs.
    //
    // The override MUST be registered BEFORE the
    // `evaluationDependsOn(":app")` block below — otherwise Gradle
    // throws "Cannot run Project.afterEvaluate(Action) when the
    // project is already evaluated".
    // -----------------------------------------------------------------
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

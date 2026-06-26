allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            project.extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileOptions {
                    isCoreLibraryDesugaringEnabled = true
                    sourceCompatibility = JavaVersion.VERSION_25
                    targetCompatibility = JavaVersion.VERSION_25
                }
                
                // Enable multidex for all subprojects
                defaultConfig {
                    multiDexEnabled = true
                }
            }
            
            // Add desugaring dependency to all Android subprojects
            project.dependencies.add("coreLibraryDesugaring", "com.android.tools:desugar_jdk_libs:2.1.5")
        }
        
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_25)
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

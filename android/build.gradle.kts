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

subprojects {
    fun configureAndroid(proj: Project) {
        val android = proj.extensions.findByName("android")
        if (android != null) {
            try {
                val compileMethod = android.javaClass.getMethod("compileSdkVersion", Integer.TYPE)
                compileMethod.invoke(android, 36)
            } catch (e: Exception) {
                try {
                    val compileMethod = android.javaClass.getMethod("compileSdkVersion", String::class.java)
                    compileMethod.invoke(android, "android-36")
                } catch (e2: Exception) {}
            }
            try {
                val defaultConfig = android.javaClass.getMethod("getDefaultConfig").invoke(android)
                if (defaultConfig != null) {
                    try {
                        val targetMethod = defaultConfig.javaClass.getMethod("setTargetSdkVersion", Integer.TYPE)
                        targetMethod.invoke(defaultConfig, 36)
                    } catch (e1: Exception) {
                        try {
                            val targetMethod = defaultConfig.javaClass.getMethod("targetSdkVersion", Integer.TYPE)
                            targetMethod.invoke(defaultConfig, 36)
                        } catch (e2: Exception) {}
                    }
                }
            } catch (e: Exception) {}
        }
    }

    val proj = this
    if (proj.state.executed) {
        configureAndroid(proj)
    } else {
        proj.afterEvaluate {
            configureAndroid(proj)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

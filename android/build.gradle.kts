// FILE: android/build.gradle.kts
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Dynamically injects 'namespace' into legacy plugins (like flutter_foreground_task 5.x)
subprojects {
    afterEvaluate {
        // Only target Android Library plugins
        if (project.plugins.hasPlugin("com.android.library")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                    val namespace = getNamespace.invoke(androidExt) as? String
                    
                    // If the plugin forgot to declare a namespace, we generate one for it
                    if (namespace.isNullOrEmpty()) {
                        val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                        val generatedNamespace = "com.example." + project.name.replace("-", "_")
                        setNamespace.invoke(androidExt, generatedNamespace)
                    }
                } catch (e: Exception) {
                    // Safe catch-all to prevent Gradle from crashing if an extension behaves weirdly
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

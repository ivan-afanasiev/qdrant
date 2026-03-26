# JNA uses reflection — keep its classes
-dontwarn java.awt.*
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }

# Keep UniFFI generated bindings
-keep class tech.qdrant.edge.** { *; }

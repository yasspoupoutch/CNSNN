# kotlinx.serialization: keep generated serializers of the shared models.
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class com.poupoutch.cnsnn.** { *** Companion; kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.poupoutch.cnsnn.**$$serializer { *; }

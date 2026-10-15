# PVC reading uses Latin OCR. The plugin references these optional,
# compile-only recognizers without bundling their language libraries.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# ML Kit finds its parts by class name (the registrars listed in the merged
# AndroidManifest.xml) and creates each one through its no-argument
# constructor. The Firebase rule that comes with ML Kit keeps only the
# classes, so R8 full mode removed those constructors: ML Kit then started
# without its settings store, and reading a PVC or a face crashed in release
# builds with a NullPointerException in InputImage.fromFilePath.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}

# Sound alerts run YAMNet through LiteRT (TensorFlow Lite). Its native
# library looks some of these classes up by name, which R8 cannot see.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Google Tink ships with amplify_secure_storage and is annotated with
# ErrorProne and JSR-305 annotations. Those are compile-time only and are not
# packaged into the app, so R8 reports them as missing classes and fails the
# release build. Nothing references them at runtime — silencing the warning is
# the whole fix.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**

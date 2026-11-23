# पारिवारिक बचत कोष — Source Update

This source archive includes the insurance annual-limit and fund-balance transaction-safety update.

Before publishing the app, read `INSURANCE_DEPLOYMENT.md` and run the one-time Firestore aggregate migration in `tools/initialize_insurance_aggregates.py`. Firestore Rules must also be merged and published in the Firebase Console; they are not deployed by building this ZIP.

The Flutter source has not been compiled in this environment because the Flutter/Dart SDK is unavailable here. Run `flutter pub get` and `flutter analyze` / `flutter build apk --release` in FlutLab or Cloud Shell before distributing an APK.


## Android update system

Android update detection and APK installation are configured through GitHub Releases. See `GITHUB_ANDROID_UPDATES.md` for the one-time signing-key setup and release-tag workflow. The same private release keystore must sign the first manually installed APK and every future update. Android will display its own confirmation screen for each update.

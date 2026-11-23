# Version 1.0.4+5

- Replaced the previous Firestore update lookup with GitHub Releases version checking.
- Added automatic latest-release detection on Android app launch.
- Added APK download to app-private storage and handoff to the Android package installer.
- Added the GitHub Actions workflow to build and publish signed APK releases from version tags.
- Added a permanent release-signing configuration; release builds no longer fall back to the machine-specific debug key.
- Preserved the existing application package ID and existing app screens/features.

Android requires user confirmation in the system installer. This release archive has not been compiled in this environment because Flutter/Dart SDK is unavailable here; run `flutter pub get`, `flutter analyze`, and `flutter build apk --release` after configuring the permanent release keystore.

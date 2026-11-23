# Android updates through GitHub Releases

The Android app checks the latest published GitHub Release on app launch. It compares the release `Version Code` with the installed Android build number, downloads the attached APK into app-private storage, and opens Android's package installer. Android always asks the user to approve the installation; silent installation is not supported.

Repository configured in `lib/app_update_service.dart`: `family-saving-fund/paribarik-bachat-kosh-apk-`. The repository must be public for the unauthenticated Releases API used by the app. Each release must attach an installable universal `.apk` asset.

## One-time signing setup

1. Create one dedicated Android release keystore in a private environment. Keep the `.jks` file and its passwords backed up securely. Do not put them in the source ZIP or commit them to GitHub.
2. For a local Cloud Shell build, create `android/app/release-keystore.jks` and `android/key.properties` with `storeFile=release-keystore.jks`, `storePassword=...`, `keyAlias=...`, and `keyPassword=...`.
3. Add these four GitHub Actions repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`. `ANDROID_KEYSTORE_BASE64` is the base64-encoded content of that exact `.jks` file.
4. The first installable APK and every future APK must be signed with this same keystore. Never regenerate or replace it.

## Publish a release

Increase the numeric build number in `pubspec.yaml` for every release, then commit and push the source. Create and push a matching tag, for example `v1.0.4+5`. GitHub Actions runs `flutter analyze`, builds a signed release APK, and publishes it as a GitHub Release asset. The app detects the new release on its next launch.

## Important Android behavior

- The new baseline APK is installed manually once.
- Later releases are detected and downloaded by the app; Android's installer asks the user to confirm each update.
- Updates install over the existing app only when the package ID and signing certificate remain identical.
- The first APK and all later APKs must use the permanent release keystore configured above.
- If Android asks to allow installs from this app, the user must enable that Android setting.
- A GitHub release without an attached APK, without a numeric version code, or signed with a different key cannot update the app.

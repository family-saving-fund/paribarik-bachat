# Version 1.0.3+4 changes

- Added member account deactivation controls for fixed date ranges and indefinite deactivation, with early manual reactivation.
- Added disabled-member dashboard redaction and member-side action guards.
- Added penalty pause / 10-day reactivation grace handling for fixed and indefinite deactivation modes.
- Updated Android launcher icons with a larger fully-contained logo and orange border.
- Added self-member birthday selection alongside family-member birthday selection.
- Added amount-based loan interest, overdue rates, and maximum durations. Existing loans without the new monthlyInterestRate field retain the previous rates.
- Added optional device biometric authentication using the phone's enrolled fingerprint / face authentication.

Build note: the Flutter SDK was not available in the editing environment, so a Flutter build and device-level biometric test could not be run here. Run `flutter pub get` and `flutter build apk --release` in the Flutter build environment before installing.

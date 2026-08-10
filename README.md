# PolaMove

A tricycle ride-hailing and transport management application for Polangui, Albay.

## Context

Capstone project for the Bachelor of Science in Information Systems program,
Bicol University Polangui Campus.

## Tech stack

- Flutter 3.29.3 (Dart SDK ^3.7.2)
- Firebase Authentication and Cloud Firestore
- OpenStreetMap tiles rendered with `flutter_map`
- Admin console in plain HTML and JavaScript, using the Firebase Web SDK

Other notable packages: `flutter_riverpod`, `go_router`, `geolocator`,
`image_picker`, `google_fonts`.

## Project structure

```
lib/
  core/
    constants/   app_colors.dart, polangui_barangays.dart
    services/    auth_service.dart, ride_service.dart, location_service.dart
    theme/       app_theme.dart
    utils/       validators.dart
  features/
    splash/          launch screen
    role_selection/  passenger or driver entry point
    auth/            passenger and driver sign-in and registration
    passenger/       home, booking, ride status, history, notifications, profile
    driver/          home, tracking, history, notifications, profile
    shared/          edit profile, change password, notification settings
  firebase_options.dart
  main.dart
admin/
  index.html                  admin console UI
  polamove_admin_firebase.js  Firestore data layer for the console
```

## Setup

Requires Flutter 3.29.3 and an Android device or emulator.

```
git clone <repository-url>
cd PolaMove
flutter pub get
flutter run
```

The Firebase project must already exist. The committed configuration
(`lib/firebase_options.dart`, `android/app/google-services.json`) points at
project `polamove-54ee1`, so a teammate who clones the repository connects to
the same backend without further setup.

`pubspec.lock` is committed so all three developers resolve identical
dependency versions.

## Admin console

The console lives in `admin/` and must be served over HTTP. Opening
`admin/index.html` directly with a `file://` URL does not work, because
`polamove_admin_firebase.js` is loaded as an ES module and browsers block
module imports from the `file://` origin.

Any static HTTP server works. The team uses the VS Code Live Server extension
(right-click `admin/index.html`, "Open with Live Server").

Admin access requires an `admins/{uid}` document in Firestore for the signed-in
account. Sign-in uses the same Firebase Authentication user pool as the mobile
app; an account without that document is signed out and rejected.

The console loads the Firebase Web SDK from `gstatic.com`, so it requires an
internet connection.

## Configuration and credentials

`lib/firebase_options.dart`, `android/app/google-services.json` and
`admin/polamove_admin_firebase.js` contain Firebase API keys and the project
ID. These are committed deliberately.

Firebase web and mobile API keys are public identifiers, not secrets. They
identify which Firebase project a client is talking to, and are visible to
anyone who inspects a shipped app or web page. They grant no access on their
own: access control is enforced by Firebase Authentication and Firestore
security rules. Removing them would make the repository unclonable for
teammates and add setup friction with no security benefit.

No service account keys, private key files, or Admin SDK credentials are stored
in this repository. Those are the credentials that must never be committed.

Firestore security rules are managed in the Firebase console and are not part
of this repository.

## Known limitations

- Driver documents are stored as device-local file paths rather than Cloud
  Storage download URLs, as Cloud Storage requires a billing-enabled Firebase
  plan. The paths resolve only on the device that submitted them.
- Driver positions are pinned to the Polangui service area behind the
  `kForcePolanguiLocation` flag in `lib/core/services/location_service.dart`.
  Live GPS is implemented and is enabled by setting the flag to `false`.
- SMS-based phone verification was not implemented, as it requires a
  billing-enabled plan. Identity is verified through admin review of submitted
  documents.
- The `notifications` create rule allows any authenticated user to write a
  notification to any uid. Restricting it further requires a document read
  inside the security rule.
- The `drivers` update rule permits a driver to modify their own `status`
  field, including approval status.
- Rating is not implemented; the field is a placeholder and is not calculated
  from completed rides.

## Team

- Ibet — lead developer
- Jaiden Nykluz M. Fermante
- Andrei Lloyd V. Sinfuego

Adviser: Vince Angelo E. Naz, DIT

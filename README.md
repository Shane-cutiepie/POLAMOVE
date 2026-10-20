# PolaMove

A tricycle ride-hailing and transport management application for Polangui, Albay.

## Context

Capstone project for the Bachelor of Science in Information Systems program,
Bicol University Polangui Campus.

## Tech stack

- Flutter 3.29.3 (Dart SDK ^3.7.2)
- Firebase Authentication and Cloud Firestore
- Google Maps for Flutter web/Android and the admin console; OpenStreetMap
  through `flutter_map` for iOS
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

Requires Flutter 3.29.3 and an Android device or emulator running API 24 or
newer.

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

## Deploy the Flutter web app to Cloud Run

This repository's app is Flutter/Dart. The web entry point is `web/index.html`,
and Cloud Run serves the release build from `build/web` using the root
`Dockerfile` and `nginx.conf`. The container includes only the Flutter app;
the separate `admin/` console is not deployed by this setup.

The Flutter web and Android app maps and the admin live-ride map use Google
Maps. The iOS app continues using OpenStreetMap; this setup does not require
the iOS Maps SDK.

Enable **Maps JavaScript API** and **Maps SDK for Android** in the Google Cloud
project that owns your Maps keys, and ensure billing is enabled. Create two
keys because browser referrer restrictions and Android app restrictions are
different:

- **Web key:** restrict the key to **Websites** and the Maps JavaScript API.
  Add `http://localhost:*/*`, `http://127.0.0.1:*/*`, the Cloud Run service
  hostname, and the admin console's hosted hostname.
- **Android key:** restrict the key to **Android apps** and Maps SDK for
  Android. Add this app's package name, `com.example.polamove`, and the SHA-1
  signing certificate fingerprints for each build you use. Get the debug
  fingerprint with `cd android; .\gradlew signingReport` in PowerShell.

For local Flutter web, replace the `YOUR_GOOGLE_MAPS_API_KEY` placeholder in
`web/maps-config.js` with the restricted web key. Configure the admin console
by copying `admin/maps-config.example.js` to `admin/maps-config.js` and using
that same web key. The Cloud Run deployment command below passes the web key
as a runtime environment variable, and the container injects it when it starts.

The key is necessarily visible in browser-delivered code. It is not a secret:
protect it with API and website restrictions, and do not use an unrestricted
key. The Android key is similarly embedded in the app and protected with its
Android app restriction. To configure Android locally, add
`googleMapsApiKey=YOUR_ANDROID_MAPS_KEY` to the ignored `android/local.properties`
file, or set the `GOOGLE_MAPS_ANDROID_API_KEY` environment variable when
building.

On Android, the pickup picker keeps the saved Polangui locations visible and
searchable alongside the Google Map. Those saved landmarks use their Google
Maps place coordinates. Select a named location to center its pin on the map,
tap a different point on the map, or drag the map under the center pin and
choose **Use the pin in the center of the map** for a custom point. Review the
coordinates and confirm the selection. Chosen coordinates are attached to the
ride request; no background passenger location is collected.

The admin console reads its key from `admin/maps-config.js`. Copy
`admin/maps-config.example.js` to that filename and replace the placeholder
with the restricted web key. The local config file is git-ignored. Ensure the
admin host is included in the web key's website restrictions when hosted.

Build and optionally preview the web output locally:

```
flutter run -d edge
flutter build web --release
```

Install the Google Cloud CLI and Docker if you want to build and test the
container locally. Authenticate and select the Google Cloud project that
should host the service. The app's Firebase configuration points to
`polamove-54ee1`; use that project if the deployed app should use the existing
Firebase backend, and confirm you have permission to deploy there.

```
gcloud auth login
gcloud config set project polamove-54ee1
gcloud config get-value project
```

Enable the Cloud Run source deployment services, then deploy from the
repository root, replacing the example Maps key with your restricted web key:

```
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
gcloud run deploy polamove --source . --region us-central1 --allow-unauthenticated --port 8080 --set-env-vars GOOGLE_MAPS_API_KEY=YOUR_WEB_MAPS_KEY
```

Cloud Build builds the Dockerfile, and Cloud Run prints the public service URL
after deployment. Source deployment and Cloud Run may require a billing-enabled
project and appropriate IAM permissions.
Add that service's URL to the web key's website restrictions after the first
deployment; the restriction update takes effect without rebuilding the app.

If Firebase Authentication sign-in is used on the deployed web app, add the
Cloud Run hostname (without a path) under **Firebase Console → Authentication
→ Settings → Authorized domains**. Keep local development hosts such as
`localhost` there as needed. This is Firebase Auth domain configuration; it is
separate from the web Maps key's HTTP-referrer restrictions. Browser location
access requires HTTPS, which the Cloud Run URL provides.

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

- Driver documents and profile photos are uploaded to Cloudinary (see
  `lib/core/services/cloudinary_service.dart`) rather than Firebase Cloud
  Storage, as Cloud Storage requires a billing-enabled Firebase plan.
  Cloudinary URLs are hosted at unguessable but not access-controlled
  addresses: anyone with a URL can view the file. This is a consequence of
  using an unsigned upload preset — the app has no server component to sign
  requests with, so there is no server-side hook to enforce access control
  on read.
- Replaced profile photos and documents are never deleted from Cloudinary,
  for the same reason: removal would require a signed (server-side) API
  call, which this app has no server to make. Old uploads accumulate in the
  Cloudinary account indefinitely.
- Drivers must grant location access and have location services enabled before
  going online. Their real GPS position is streamed to Firestore while online;
  the app does not substitute a town-centre or fabricated position when GPS is
  unavailable. Passenger and driver ride maps hide positions older than two
  minutes. Background tracking is not configured, so drivers need to keep the
  app active during a ride for continuous updates.
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
- The app displays research participation and permission disclosure screens
  required by the project's BUERB (ethics review board) submission. Every
  BUERB-specified string is centralised in
  `lib/core/constants/research_notice.dart`, pending final BUERB approval of
  the wording.

## Team

- Shane Yvette C. Penaflor — lead developer
- Jaiden Nykluz M. Fermante
- Andrei Lloyd V. Sinfuego

Adviser: Vince Angelo E. Naz, DIT

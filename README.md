# PeriodPilot by StackSeed

PeriodPilot helps schools manage staff, timetables, absences, substitute assignments, and reports. Firebase Authentication and school data are connected on Android and web. Firestore stores each account-to-school profile, school profile, teachers, classes, sections, and subjects. Existing SQLite entries remain on device until explicitly migrated.

## Run

```powershell
flutter pub get
flutter run
```

On Android and web, register a school from the sign-in screen to create a Firebase Auth administrator and Firestore school/profile. Use **Manage school setup** to manage cloud-synced school records. Existing local SQLite entries are preserved on device but are not migrated automatically. Desktop currently retains the prior local account and database flow.

## Getting started

1. Open the hosted web app at <https://teachersubstitute.web.app/> or run it locally with `flutter run -d chrome`. The hosted copy will keep its current branding until the web build is redeployed.
2. On the sign-in screen, select **Register a new school**. Enter the administrator name, school name, email, and a password with at least 10 characters, including a letter and a number. This creates the first administrator account for that school.
3. From the administrator dashboard, open **Manage teachers** to complete the school profile and add teachers, classes/sections, and subjects.
4. Open **Manage timetable** to add period times and assign subjects, teachers, classes, and sections to periods for each working day.
5. Use **Mark teacher absent** to record an absence. Then open **Assign substitute** to review affected periods and choose an available teacher. Review each suggestion before assigning; the app does not auto-finalize assignments.
6. Open **Reports** for daily, monthly, teacher, absence, and workload summaries; export a report using **Export CSV**.

Teacher and principal sign-in accounts are not created from the app yet. An administrator must create each account in Firebase Authentication and add the matching `/users/{uid}` Firestore profile with the role (`teacher` or `principal`), the school's `schoolId`, matching email, display name, and `active: true`. For the teacher dashboard, that email must also match a teacher record. Push delivery still needs a deployed Cloud Function and a Web Push VAPID key as described below.

Android releases can be installed with `adb install -r build/app/outputs/flutter-apk/app-release.apk` after building the signed APK. Desktop's legacy local accounts and records do not sync to the Firebase school data used on Android and web.

## Firebase setup

1. In Firebase Console, enable Email/Password under Authentication, enable the Cloud Firestore API, and create the Firestore database. Database region is a one-time choice; select the region required for your school's data residency and latency needs.
2. `lib/firebase_options.dart` and `.firebaserc` are configured for Android (`com.schooltools.teacher_substitute`) and web.
3. Deploy Firestore rules with `firebase deploy --only firestore:rules`. The checked-in rules enforce school-scoped access; test any rule changes with the Firebase Emulator before production.
4. Build and deploy web: `flutter build web --release` then `firebase deploy --only hosting`.

Firebase Hosting serves the Flutter web build. Android/iOS apps are installed through their app packages/stores; Firebase Auth and Firestore provide their cloud persistence. Firebase client configuration contains project identifiers, not private server credentials. Do not put service account keys in the app.

## Android release

The Android release configuration never uses the debug signing key. This workspace now has a password-protected upload key stored outside the project and a private, ignored `android/key.properties` file. Keep both safely backed up; losing them can prevent future app updates from using the same signing identity. The key properties file contains passwords and should not be committed or shared.

The current upload certificate fingerprints are SHA-1 `CB:0A:F9:0F:55:0F:26:3F:F6:C9:62:94:6E:5D:AC:48:33:09:06:6D` and SHA-256 `98:CC:CA:A7:B7:7C:2A:4F:1C:79:3E:BE:61:3D:65:B1:4D:91:6A:E3:83:0F:7C:46:D5:BA:53:91:79:51:22:68`. Register the relevant fingerprints in Firebase project settings if enabling an authentication provider that requires Android signing fingerprints. Google Play App Signing may use a separate app-signing certificate; add that certificate's fingerprints too if prompted.

On a different machine without the private signing files, the commands below create unsigned packages that cannot be uploaded to Google Play:

```powershell
flutter build apk --release
flutter build appbundle --release
```

Artifacts are written to `build/app/outputs/flutter-apk/app-release.apk` and `build/app/outputs/bundle/release/app-release.aab`.

To prepare a Play Store release, create and securely back up an upload keystore outside source control:

```powershell
keytool -genkey -v -keystore "$env:USERPROFILE\school-substitute-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

To configure signing on another machine, create `android/key.properties` with the following entries, replacing values locally. Keep this file and the `.jks` private and backed up; neither belongs in source control.

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:/Users/YOUR_NAME/school-substitute-upload.jks
```

Then run the two build commands above again. Bump `version:` in `pubspec.yaml` for each published release. Keep the upload key safe: losing it can prevent future updates from being signed consistently.

The web deployment remains separate: `flutter build web --release` then `firebase deploy --only hosting`. Firestore rules use `firebase deploy --only firestore:rules`. These commands publish to the configured Firebase project; review the project and build before running them. Cloud Functions deployment is separately gated by Firebase plan requirements described below.

## Authentication and local data

- Android and web use Firebase Authentication for accounts and Firestore for cloud school records.
- Existing desktop/local accounts and records still use SharedPreferences and SQLite. They are preserved, but no automatic local-to-cloud import is implemented yet.

Local account mode is retained only for desktop compatibility. It does not sync accounts or records to other devices.

## School setup

After signing in, select **Manage school setup** to edit the school profile and manage teachers, classes/sections, and subjects. Android and web use school-scoped Cloud Firestore. Desktop uses the existing local SQLite database. Windows and Linux use `sqflite_common_ffi`; Android and Apple platforms use `sqflite` for the legacy local store.

Firebase Cloud Firestore persistence is enabled for the Android and web app.

### Offline behavior and verification

- Firestore's persistent cache keeps documents the signed-in user has already loaded on that device/browser. Previously viewed school details and timetable data can therefore be read again without a connection; data never loaded on that device is not available offline.
- The app-wide offline banner follows the device's network-interface status. A connected Wi-Fi or mobile interface does not guarantee that the internet or Firebase is reachable.
- Firestore queues supported ordinary document writes and synchronizes them when connectivity returns. Substitution assignment creation, reassignment, and cancellation are deliberately online-only: they read current server state and use a transaction with uniqueness claims. An offline or stale client is rejected instead of overwriting a newer assignment.
- Firestore remains the source of truth. Clearing browser/app storage removes that device's cached copy but does not delete records stored in the school's Firestore database.

To verify offline behavior on Android or web, sign in while online, open the dashboard and timetable so their records are cached, then disconnect the device/network. Confirm the offline banner appears and previously loaded screens still show data. Try to create or cancel a substitution and confirm the operation reports that an internet connection is required. Reconnect and refresh; verify server data loads and the assignment list reflects the current server state. Repeat on each device/browser because Firestore caches are device-local. Automated connectivity-state checks are included in `flutter test`; Firestore reconnection behavior requires a signed-in Firebase environment.

## Push notifications

Firebase Messaging is configured for Android and web. A signed-in user can open **Notifications** and enable device alerts. Each device registration is stored under that user's `fcmInstallations` subcollection. The Firestore rules restrict those records to their owner, and notification history is readable only by its recipient or a school administrator.

Assignment messages are sent by `functions/index.js` when an active substitution is created or reassigned. The function matches the substitute teacher's email to an active Firebase Auth user profile (`/users/{uid}`) with role `teacher` in the same school. The user's teacher record and Firebase profile must use the same email address.

Before enabling delivery:

1. In Firebase Console, open **Project settings → Cloud Messaging → Web Push certificates** and copy the **public VAPID key**. It is a public key; do not use the private key in this app.
2. Rebuild and deploy web with that key: `flutter build web --release --dart-define=FCM_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY`, then `firebase deploy --only hosting`. Android does not need the VAPID key.
3. Cloud Functions are not deployed from this project yet. Firebase rejected deployment on the Spark plan because Functions require Blaze. If you choose to enable Blaze billing, review the plan and usage details in Firebase Console, then run `firebase deploy --only functions`. Ensure the function runtime service account can call the Firebase Cloud Messaging HTTP v1 API.
4. Create or link a teacher's Firebase Authentication account and `/users/{uid}` profile with `role: "teacher"`, matching `email`, the correct `schoolId`, and `active: true`. Sign in as that teacher, open **Notifications**, and enable alerts on each device.

Until Functions are deployed and Web has its VAPID key, the notification center is available but push delivery is not active. No service-account credentials are stored in Flutter.

To verify the notification flow after setup, run `npm --prefix functions run lint`, `flutter analyze`, and `flutter test`. Then enable notifications on a teacher account/device, assign a substitute duty from the administrator account, and confirm the notification appears in the teacher's **Notifications** history and as a push alert. In the foreground, the app shows an in-app alert; with the app backgrounded, the platform notification is displayed by FCM. Mark it read and confirm the history updates. If push is unavailable, the notification record reports whether there is no registered device or delivery is pending.

Teacher and subject records can be deactivated and reactivated. Class deletion also removes its sections. Staff IDs, class names, section names within a class, and subject names/codes are checked for duplicates within the school.

To check this module manually, save a school profile, add/edit/deactivate a teacher, add a class and sections, and add/edit/deactivate a subject. Close and reopen the app to confirm the records remain.

## Project layout

```text
lib/
  app/                       app shell and theme
  core/storage/              desktop database factory selection
  features/auth/
    data/                    Firebase and local authentication stores
    domain/                  roles and user profile model
    presentation/            setup, login, session gate, role home
  features/school/
    data/                    Firestore and SQLite school data stores
    domain/                  school, teacher, class, section, subject models
    presentation/            school setup and management screens
  main.dart
```

The current SQLite database is retained so existing entries are not erased. Legacy device records are not uploaded automatically; an explicit migration step is still needed for existing local schools.

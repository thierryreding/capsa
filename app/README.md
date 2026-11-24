# Capsa app (Flutter)

An experiment: the PWA in `web/` as a Flutter app for the web, Android and (later)
iOS. Same API, same synced data: both clients can be used side by side, and the
learning state and settings (choices, test plans, display name) are shared.

- `lib/learning/` is a line-by-line port of `web/src/lib/learning/` (matching,
  Leitner, sessions, multiple choice, test plans, statistics). It passes the same
  `vectors/*.json` as the TS client and the server.
- `lib/store/` keeps the data locally with sembast (IndexedDB on the web, a file on
  Android and iOS): one database per account, one per device, as the PWA does.
- `lib/api/client.dart` talks to the API. In the browser the browser keeps the
  session cookie; on Android and iOS the app asks for the server address at sign-in
  and keeps the cookie itself.
- `lib/ui/` has the screens, with the PWA's German strings (`lib/i18n.dart`) and
  colours (`lib/ui/theme.dart`).

## Develop

    cd app
    flutter test                     # logic, sync and widget tests
    tool/build.sh web                # build/web, version from ../VERSION
    tool/build.sh apk --release      # needs Android SDK 36 and JDK 17-27 (flutter config --jdk-dir)

The web build has to share the API's origin (no CORS, `SameSite=Strict` cookie).
For a local try-out, `tool/dev_server.py` serves the API and `build/web` together:

    export CAPSA_DATABASE_URL=sqlite:///dev.sqlite CAPSA_PROFILE_DIR=profiles/demo
    uv run capsa db upgrade
    uv run capsa user add lena && uv run capsa user grant lena demo-latin
    uv run python app/tool/dev_server.py      # http://127.0.0.1:8092

From the Android emulator the same server is `http://10.0.2.2:8092` (debug builds
allow plain HTTP; start the server with `--host 0.0.0.0`).

## Android release

    tool/build.sh apk --release --split-per-abi \
      --dart-define=CAPSA_SERVER=https://capsa.example.org   # optional: prefill the server

`build.sh` takes the version name from `../VERSION` and derives the version code
(`2026.11.1` → 20261101; split APKs add 1000 × ABI, e.g. +3000 for arm64), so every
release can update the installed one. Phones only need `app-arm64-v8a-release.apk`.

Release builds are signed with the upload key named in `android/key.properties`
(keystore path, alias, passwords; not in Git). Without that file they fall back to the
debug key and Gradle warns. Android only installs an update signed with the same key as
the installed app, so **back up the keystore and `key.properties` together**: without
them, the app can only be replaced by uninstalling it, which deletes the data on the
device that has not been synced yet. A new key is made with:

    keytool -genkeypair -keystore upload-keystore.jks -storetype PKCS12 -alias upload \
      -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Capsa"

## CI builds

`.github/workflows/ci.yml` runs `scripts/check.sh`, builds the Android APKs and the
unsigned iOS app (after starting it in the iPhone simulator), and on a tag `vYYYY.MM[.N]`
that matches `VERSION` publishes both in a GitHub release. It pins Flutter's master
revision in `FLUTTER_REVISION`; update it together with the local Flutter.

To sign the APKs with the upload key, add two repository secrets:

    base64 -w0 ~/.local/share/capsa/android/upload-keystore.jks   # ANDROID_KEYSTORE_BASE64
    grep storePassword android/key.properties                     # ANDROID_KEYSTORE_PASSWORD

The unsigned `.ipa` installs on an iPhone through AltStore or Sideloadly with an Apple
ID (free accounts: the install expires after 7 days); App Store or TestFlight builds
need the Apple Developer Program and its certificates.

## Differences from the PWA

- Offline on the web: Flutter no longer ships a working service worker (its
  `flutter_service_worker.js` only unregisters itself), so the web build does not
  load without a network yet. Android and iOS apps are offline by nature.
- Size: the web build loads about 4 MB of JavaScript plus a 3.5-7 MB rendering
  engine (WebAssembly) on the first visit; the PWA is about 300 KB in all.
- No install hint, update banner or `navigator.storage.persist()`: an installed
  Android app needs none of them.

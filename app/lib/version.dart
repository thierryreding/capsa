/// The release version from the repository's VERSION file, passed at build time
/// (tool/build.sh: --dart-define=CAPSA_VERSION=...), like the PWA's __APP_VERSION__.
const appVersion = String.fromEnvironment('CAPSA_VERSION', defaultValue: 'dev');

/// The server address to suggest at the first sign-in on Android and iOS, if the build
/// was given one (--dart-define=CAPSA_SERVER=https://...).
const defaultServer = String.fromEnvironment('CAPSA_SERVER');

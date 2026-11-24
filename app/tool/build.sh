#!/bin/sh
# Build the Flutter app with the release version from the repository's VERSION file.
#   app/tool/build.sh web            -> app/build/web
#   app/tool/build.sh apk [--debug]  -> app/build/app/outputs/flutter-apk/
# Extra arguments go to `flutter build`, e.g. --dart-define=CAPSA_SERVER=https://...
set -eu
cd "$(dirname "$0")/.."
target=${1:?usage: $0 web|apk|appbundle|ios [flutter build options]}
shift
version=$(cat ../VERSION)
# Android needs an increasing integer: YYYY.MM[.N] -> YYYYMM0N (2026.11.1 -> 20261101).
code=$(echo "$version" | awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }')
exec flutter build "$target" --dart-define=CAPSA_VERSION="$version" \
  --build-name="$version" --build-number="$code" "$@"

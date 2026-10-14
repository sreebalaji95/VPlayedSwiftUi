#!/bin/sh
# Builds the Kotlin Multiplatform shared layer and installs it into the local SharedKit package.
#
#   scripts/build-shared.sh            release XCFramework (default)
#   scripts/build-shared.sh debug      debug XCFramework (faster to build, larger)
#
# Needs the kmp repository next to this one (../kmp) and JDK 25. Android Studio's bundled JBR works:
#   export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
set -eu

configuration="${1:-release}"
case "$configuration" in
    release) task="assembleSharedReleaseXCFramework" ;;
    debug) task="assembleSharedDebugXCFramework" ;;
    *) echo "usage: $0 [release|debug]" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
kmp="${KMP_DIR:-$root/../kmp}"
destination="$root/SharedKit/Shared.xcframework"

if [ ! -x "$kmp/gradlew" ]; then
    echo "error: kmp repository not found at $kmp (set KMP_DIR)" >&2
    exit 1
fi

(cd "$kmp" && ./gradlew ":shared:$task" --console=plain)

rm -rf "$destination"
cp -R "$kmp/shared/build/XCFrameworks/$configuration/Shared.xcframework" "$destination"
echo "Installed $configuration Shared.xcframework into SharedKit/"

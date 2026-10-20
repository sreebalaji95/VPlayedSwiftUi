#!/bin/sh
# Builds the Kotlin Multiplatform shared layer and installs it into the local SharedKit package,
# with the shared string catalog (SharedKit/compose-resources, copied into the app bundle).
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
resources="$root/SharedKit/compose-resources"

if [ ! -x "$kmp/gradlew" ]; then
    echo "error: kmp repository not found at $kmp (set KMP_DIR)" >&2
    exit 1
fi

(cd "$kmp" && ./gradlew ":shared:$task" --console=plain)

rm -rf "$destination"
cp -R "$kmp/shared/build/XCFrameworks/$configuration/Shared.xcframework" "$destination"
echo "Installed $configuration Shared.xcframework into SharedKit/"

# The string catalog (Compose Multiplatform Resources) is inside each framework slice, but a static
# framework's files are not embedded in the app. The VPlayed target copies this folder into the app
# bundle as `compose-resources/`, where the shared layer reads it. Every slice holds the same files.
rm -rf "$resources"
mkdir -p "$resources"
cp -R "$destination/ios-arm64/Shared.framework/composeResources" "$resources/composeResources"
echo "Installed the shared string catalog into SharedKit/compose-resources/"

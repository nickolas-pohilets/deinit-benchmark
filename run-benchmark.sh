set -ue

MY_DIR="$(readlink -f "$(dirname $0)")"

DEBUG_SUFFIX=""
if [ "${1:-}" == "--debug" ]
then
    DEBUG_SUFFIX="-debug"
    shift 1
fi

if [ -z "${DEVELOPER_DIR+x}" ]
then
    DEVELOPER_DIR=$(xcode-select -p)
fi

if [ -z "${RELEASE_BUILD_DIR+x}" ]
then
    RELEASE_BUILD_DIR="$MY_DIR/../build/Ninja-ReleaseAssert/swift-macosx-arm64"
fi

if [ -z "${DEBUG_BUILD_DIR+x}" ]
then
    DEBUG_BUILD_DIR="$MY_DIR/../build/Ninja+cmark-DebugAssert+llvm-RelWithDebInfoAssert+swift-DebugAssert+stdlib-DebugAssert/swift-macosx-arm64"
fi

if [ -z "${BUILD_DIR+x}" ]
then
    if [ -z "$DEBUG_SUFFIX" ]
    then
        BUILD_DIR="$RELEASE_BUILD_DIR"
    else
        BUILD_DIR="$DEBUG_BUILD_DIR"
    fi
fi

OUTPUT_NAME="$MY_DIR/deinit-benchmark$DEBUG_SUFFIX.out"

SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
    $BUILD_DIR/bin/swiftc \
        -target arm64-apple-macosx10.13  \
        -F "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
        -toolchain-stdlib-rpath \
        -Xlinker -rpath -Xlinker "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
        -Xlinker -rpath -Xlinker /usr/lib/swift \
        -Xlinker -headerpad_max_install_names \
        -swift-version 4 \
        -parse-as-library \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 9999:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.0:macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.1:macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.2:macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.3:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.4:macOS 11.3, iOS 14.5, watchOS 7.4, tvOS 14.5' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.5:macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.6:macOS 12.3, iOS 15.4, watchOS 8.5, tvOS 15.4' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.7:macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.8:macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4' \
        -Xfrontend -define-availability -Xfrontend 'SwiftStdlib 5.9:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999' \
        -F "$BUILD_DIR/lib" \
        -Xlinker -rpath -Xlinker "$BUILD_DIR/lib" \
        -module-cache-path $BUILD_DIR/swift-test-results/arm64-apple-macosx10.13/clang-module-cache \
        deinit-benchmark.swift \
        -Xfrontend -disable-availability-checking \
        -g -Onone \
        -o "$OUTPUT_NAME" \
        -module-name main && \
codesign -s - -v -f --entitlements "$MY_DIR/entitlements.plist" "$OUTPUT_NAME" && \
/usr/bin/env DYLD_LIBRARY_PATH="$BUILD_DIR/lib/swift/macosx" "$OUTPUT_NAME" "$@"

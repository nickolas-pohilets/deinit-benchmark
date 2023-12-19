set -ue

if [ -z "${RELEASE_BUILD_DIR+x}" ]
then
    DEVELOPER_DIR=$(xcode-select -p)
fi

if [ -z "${RELEASE_BUILD_DIR+x}" ]
then
    RELEASE_BUILD_DIR="$(readlink -f "$(dirname $0)/../build/Ninja-ReleaseAssert/swift-macosx-arm64")"
fi

xcrun --toolchain default --sdk "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
    $RELEASE_BUILD_DIR/bin/swiftc \
        -target arm64-apple-macosx10.13  \
        -module-cache-path "$RELEASE_BUILD_DIR/swift-test-results/arm64-apple-macosx10.13/clang-module-cache" \
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
        -F "$RELEASE_BUILD_DIR/lib" \
        -Xlinker -rpath -Xlinker "$RELEASE_BUILD_DIR/lib" \
        -module-cache-path $RELEASE_BUILD_DIR/swift-test-results/arm64-apple-macosx10.13/clang-module-cache \
        deinit-benchmark.swift \
        -Xfrontend -disable-availability-checking \
        -g -Onone \
        -o deinit-benchmark.out \
        -module-name main && \
/usr/bin/env DYLD_LIBRARY_PATH="$RELEASE_BUILD_DIR/lib/swift/macosx" ./deinit-benchmark.out "$@"

#!/bin/sh
set -eu

# Test-without-building reuses the binary produced by build-for-testing.
# It may run in an environment without the checked-out source tree.
if [ "${CI_XCODEBUILD_ACTION:-}" = "test-without-building" ]; then
    exit 0
fi

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
version_file="$repository_path/Config/Version.xcconfig"
: "${CI_BUILD_NUMBER:?Xcode Cloud must supply CI_BUILD_NUMBER}"
case "$CI_BUILD_NUMBER" in
    ''|*[!0-9]*) printf 'CI_BUILD_NUMBER must be a positive integer.\n' >&2; exit 1 ;;
esac
if [ "$CI_BUILD_NUMBER" -lt 1 ]; then
    printf 'CI_BUILD_NUMBER must be a positive integer.\n' >&2
    exit 1
fi
if [ ! -f "$version_file" ]; then
    printf 'Missing build-version configuration: %s\n' "$version_file" >&2
    exit 1
fi
if [ "$(/usr/bin/grep -c '^CURRENT_PROJECT_VERSION = ' "$version_file")" -ne 1 ]; then
    printf 'Expected exactly one CURRENT_PROJECT_VERSION setting.\n' >&2
    exit 1
fi
/usr/bin/sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER/" "$version_file"
printf 'Building Hermes Pocket with CFBundleVersion %s.\n' "$CI_BUILD_NUMBER"

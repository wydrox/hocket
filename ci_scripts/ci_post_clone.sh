#!/bin/sh
set -eu

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
cd "$repository_path"

for required_path in HermesPocket.xcodeproj/project.pbxproj HermesPocket.xcodeproj/xcshareddata/xcschemes/HermesPocket.xcscheme Config/Info.plist Config/Version.xcconfig Sources/App/HermesPocketApp.swift Tests/HermesPocketTests; do
    if [ ! -e "$required_path" ]; then
        printf 'Missing required project input: %s\n' "$required_path" >&2
        exit 1
    fi
done
if ! /usr/bin/find Tests/HermesPocketTests -name '*.swift' -type f -print | /usr/bin/grep -q .; then
    printf 'The shared scheme requires committed Swift unit tests.\n' >&2
    exit 1
fi
/usr/bin/plutil -lint Config/Info.plist
/usr/bin/plutil -lint HermesPocket.xcodeproj/project.pbxproj
/usr/bin/xcodebuild -version
printf 'Checked-in project and shared HermesPocket scheme are ready for Xcode Cloud.\n'

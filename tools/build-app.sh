#!/bin/bash
# Build an ad-hoc signed local .app. Usage: tools/build-app.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."
args=(-c release)
if [[ $# -gt 1 ]]; then
    echo "Usage: tools/build-app.sh [--universal]" >&2
    exit 1
elif [[ "${1:-}" == "--universal" ]]; then
    args+=(--arch arm64 --arch x86_64)
elif [[ $# -gt 0 ]]; then
    echo "Usage: tools/build-app.sh [--universal]" >&2
    exit 1
fi
# Keep the lock across compilation and packaging, not just SwiftPM's build phase.
# The shell owns fd 9; the kernel releases the lock even if the shell is killed.
mkdir -p .build
exec 9>.build/macz-build.lock
if ! lockf -s -t 0 9; then
    echo "Could not acquire the MacZ build lock. Wait for any other build to finish and try again." >&2
    exit 1
fi
swift build "${args[@]}" 9>&-
bin_dir="$(swift build "${args[@]}" --show-bin-path 9>&-)"
mkdir -p dist
destination="dist/MacZ.app"
staging="$(mktemp -d dist/.macz-build.XXXXXX)"
cleanup() {
    result=$?
    # Restore the previous bundle if the final rename failed or was interrupted.
    if [[ ! -e "$destination" && ! -L "$destination" ]] && [[ -e "$staging/previous.app" || -L "$staging/previous.app" ]]; then
        if ! mv "$staging/previous.app" "$destination"; then
            echo "Could not restore the previous app; it remains at $staging/previous.app" >&2
            exit 1
        fi
    fi
    rm -rf "$staging"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
app="$staging/MacZ.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/MacZ" "$app/Contents/MacOS/MacZ"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp Sources/MacZ/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>MacZ</string>
    <key>CFBundleIdentifier</key><string>app.macz.MacZ</string>
    <key>CFBundleName</key><string>MacZ</string>
    <key>CFBundleDisplayName</key><string>MacZ</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 MacZ contributors. MIT licence.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
if [[ -e "$destination" || -L "$destination" ]]; then
    mv "$destination" "$staging/previous.app"
fi
mv "$app" "$destination"
echo "Built $destination"

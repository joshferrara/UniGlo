#!/bin/bash

set -euo pipefail

infer_repository_slug() {
    local remote_url
    remote_url="$(git config --get remote.origin.url 2>/dev/null || true)"
    if [[ -z "$remote_url" ]]; then
        return 1
    fi

    echo "$remote_url" | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##'
}

REPOSITORY_SLUG="${GITHUB_REPOSITORY_SLUG:-$(infer_repository_slug || true)}"

if [[ -z "${APP_VERSION:-}" || -z "${APP_BUILD:-}" ]]; then
    echo "error: APP_VERSION and APP_BUILD must be set" >&2
    exit 1
fi

if [[ -z "${SPARKLE_FEED_PATH:-}" ]]; then
    echo "error: SPARKLE_FEED_PATH must point to the gh-pages working copy" >&2
    exit 1
fi

if [[ -z "$REPOSITORY_SLUG" ]]; then
    echo "error: GITHUB_REPOSITORY_SLUG is required (example: joshferrara/UniGlo)" >&2
    exit 1
fi

if [[ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    echo "error: SPARKLE_PUBLIC_ED_KEY is required" >&2
    exit 1
fi

if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    echo "error: SPARKLE_PRIVATE_KEY_FILE must point to exported private EdDSA key" >&2
    exit 1
fi

if [[ -z "${DEVELOPER_ID_APP_CERT:-}" ]]; then
    echo "error: DEVELOPER_ID_APP_CERT is required" >&2
    exit 1
fi

if [[ -z "${TEAM_ID:-}" ]]; then
    echo "error: TEAM_ID is required" >&2
    exit 1
fi

if [[ -z "${NOTARIZATION_APPLE_ID:-}" || -z "${NOTARIZATION_PASSWORD:-}" ]]; then
    echo "error: NOTARIZATION_APPLE_ID and NOTARIZATION_PASSWORD are required" >&2
    exit 1
fi

sign_component() {
    local component_path="$1"
    if [[ ! -e "$component_path" ]]; then
        echo "error: component not found for codesigning: $component_path" >&2
        exit 1
    fi

    codesign --force --options runtime \
        --sign "$DEVELOPER_ID_APP_CERT" \
        --timestamp \
        "$component_path"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/dist"
APP_NAME="UniGlo"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ARCHIVE_NAME="$APP_NAME-$APP_VERSION.zip"
NOTARIZATION_ARCHIVE_PATH="$BUILD_DIR/$APP_NAME-notarization.zip"
ARCHIVE_PATH="$BUILD_DIR/$ARCHIVE_NAME"
GENERATE_APPCAST_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
GH_PAGES_DIR="$SPARKLE_FEED_PATH"
ARCHIVES_DIR="$GH_PAGES_DIR/releases"
REPOSITORY_OWNER="${REPOSITORY_SLUG%%/*}"
REPOSITORY_NAME="${REPOSITORY_SLUG##*/}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://$REPOSITORY_OWNER.github.io/$REPOSITORY_NAME/appcast.xml}"
GITHUB_RELEASE_TAG="${GITHUB_RELEASE_TAG:-v$APP_VERSION}"
GITHUB_RELEASES_URL_PREFIX="${GITHUB_RELEASES_URL_PREFIX:-https://github.com/$REPOSITORY_SLUG/releases/download/$GITHUB_RELEASE_TAG/}"
ASSET_MANIFEST_PATH="$BUILD_DIR/release-assets.txt"
MARKER_PATH="$BUILD_DIR/.asset-marker"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$ARCHIVES_DIR"

pushd "$ROOT_DIR" >/dev/null

SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
APP_VERSION="$APP_VERSION" \
APP_BUILD="$APP_BUILD" \
./build_app.sh

mv "$ROOT_DIR/UniGlo.app" "$APP_BUNDLE"

SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
sign_component "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
sign_component "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
sign_component "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
sign_component "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
sign_component "$SPARKLE_FRAMEWORK"

codesign --force --options runtime --sign "$DEVELOPER_ID_APP_CERT" --timestamp "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARIZATION_ARCHIVE_PATH"

NOTARY_SUBMISSION="$(/usr/bin/xcrun notarytool submit "$NOTARIZATION_ARCHIVE_PATH" --apple-id "$NOTARIZATION_APPLE_ID" --password "$NOTARIZATION_PASSWORD" --team-id "$TEAM_ID" --wait)"
echo "$NOTARY_SUBMISSION"

/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"

touch "$MARKER_PATH"
cp "$ARCHIVE_PATH" "$ARCHIVES_DIR/"

"$GENERATE_APPCAST_BIN" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "$GITHUB_RELEASES_URL_PREFIX" \
    "$ARCHIVES_DIR"

cp "$ARCHIVES_DIR/appcast.xml" "$GH_PAGES_DIR/appcast.xml"

find "$ARCHIVES_DIR" -maxdepth 1 -type f \
    \( -name "$ARCHIVE_NAME" -o -name '*.delta' \) \
    -newer "$MARKER_PATH" \
    | sed "s#^$ARCHIVES_DIR/##" \
    | sort > "$ASSET_MANIFEST_PATH"

echo "Feed URL: $SPARKLE_FEED_URL"
echo "Release asset base URL: $GITHUB_RELEASES_URL_PREFIX"
echo "Appcast generated/updated in $GH_PAGES_DIR/appcast.xml"
echo "Archives and delta cache stored in $ARCHIVES_DIR"
echo "GitHub release assets to upload are listed in $ASSET_MANIFEST_PATH"

echo "Release artifacts prepared in $BUILD_DIR"

popd >/dev/null

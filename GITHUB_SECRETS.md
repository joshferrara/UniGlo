# GitHub Secrets for Automated Sparkle Releases

Configure these repository secrets in GitHub under:

`Settings` → `Secrets and variables` → `Actions`

## Required secrets

### `MACOS_CERTIFICATE_BASE64`

Your exported `Developer ID Application` certificate as base64-encoded `.p12`.

### `MACOS_CERTIFICATE_PASSWORD`

The password used when exporting the `.p12`.

### `KEYCHAIN_PASSWORD`

A temporary keychain password for the GitHub Actions runner.

### `SIGNING_IDENTITY`

Your full signing identity string.

Example:

```text
Developer ID Application: Your Name (TEAMID)
```

### `NOTARIZATION_APPLE_ID`

The Apple ID email used for notarization.

### `NOTARIZATION_TEAM_ID`

Your Apple Developer Team ID.

### `NOTARIZATION_PASSWORD`

An app-specific password for notarization.

### `SPARKLE_PRIVATE_KEY`

The Sparkle EdDSA private key contents.

Do not commit this key. Keep it secret.

### `SPARKLE_PUBLIC_ED_KEY`

The matching Sparkle EdDSA public key that goes into the app bundle.

## Workflow behavior

The workflow in
[`.github/workflows/release.yml`](.github/workflows/release.yml)
does this on every push to `main`, on release tags, or on manual dispatch:

1. Imports your signing certificate into a temporary keychain.
2. Checks out the `gh-pages` branch into a temp directory.
3. Runs [`scripts/release.sh`](scripts/release.sh) to:
   - build the app
   - sign and notarize it
   - generate/update the Sparkle appcast
   - write `dist/release-assets.txt`
4. Creates or updates the GitHub release for `v<version>`.
5. Uploads the generated `.zip` and `.delta` assets listed in `dist/release-assets.txt`.
6. Commits and pushes the updated `gh-pages` feed.

For normal `main` pushes, the workflow uses the latest `v*` tag as the display
version, the GitHub run number as the Sparkle build number, and a unique
`main-<run>-<sha>` prerelease tag for the downloadable assets. This gives
Sparkle a fresh build on every `main` update without requiring a hand-created
release tag.

## Expected repository setup

- Default branch: `main`
- GitHub Pages branch: `gh-pages`
- Optional stable release tags: `v1.0.0`, `v1.0.1`, etc.

## Recommended first test

1. Add all secrets.
2. Push to `main` or run the workflow manually with a throwaway version.
3. Confirm these exist afterward:
   - GitHub release assets
   - `https://joshferrara.com/UniGlo/appcast.xml`
   - updated `gh-pages/releases/` cache

# Sparkle + GitHub Pages Setup

This project can use the same public Sparkle layout as `Hardlinker`:

- GitHub Pages hosts the feed. UniGlo currently uses `https://joshferrara.com/UniGlo/appcast.xml`.
- GitHub Releases hosts the actual `.zip` update archives and `.delta` files
- The `gh-pages` branch keeps a local `releases/` cache so `generate_appcast` can build deltas across versions

## Expected `gh-pages` layout

```text
gh-pages/
├── appcast.xml
├── index.html                # optional landing page
└── releases/
    ├── UniGlo-1.0.0.zip
    ├── UniGlo-1.0.1.zip
    ├── UniGlo2-1.delta
    ├── UniGlo3-2.delta
    └── appcast.xml
```

The root `appcast.xml` is the public feed URL the app should use. The `releases/`
directory is the working cache Sparkle uses to generate future deltas.

## Required release inputs

- `APP_VERSION`
- `APP_BUILD`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_KEY_FILE`
- `DEVELOPER_ID_APP_CERT`
- `TEAM_ID`
- `NOTARIZATION_APPLE_ID`
- `NOTARIZATION_PASSWORD`
- `SPARKLE_FEED_PATH`

Optional:

- `SPARKLE_FEED_URL`
- `GITHUB_REPOSITORY_SLUG`
- `GITHUB_RELEASE_TAG`
- `GITHUB_RELEASES_URL_PREFIX`

If the optional values are omitted, the release script derives them from the `origin`
remote and defaults to:

- feed URL: `https://<owner>.github.io/<repo>/appcast.xml`
- release tag: `v<APP_VERSION>`
- release asset prefix: `https://github.com/<owner>/<repo>/releases/download/v<APP_VERSION>/`

## One-time setup

1. Generate or export your Sparkle EdDSA keypair.

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key
```

2. Create or update the `gh-pages` branch.

```bash
git worktree add ../UniGlo-gh-pages gh-pages
```

3. Make sure the app build uses the GitHub Pages feed URL.

Example:

```bash
export SPARKLE_FEED_URL="https://joshferrara.com/UniGlo/appcast.xml"
```

4. Put the matching public key into the release environment:

```bash
export SPARKLE_PUBLIC_ED_KEY="..."
```

## Build a new Sparkle release

Assuming `../UniGlo-gh-pages` is a checkout of the `gh-pages` branch:

```bash
APP_VERSION=1.0.0 \
APP_BUILD=1 \
SPARKLE_FEED_PATH=../UniGlo-gh-pages \
SPARKLE_PRIVATE_KEY_FILE=./sparkle_private_key \
SPARKLE_PUBLIC_ED_KEY="..." \
DEVELOPER_ID_APP_CERT="Developer ID Application: Your Name (TEAMID)" \
TEAM_ID="TEAMID" \
NOTARIZATION_APPLE_ID="you@example.com" \
NOTARIZATION_PASSWORD="app-specific-password" \
./scripts/release.sh
```

This produces:

- `dist/UniGlo-<version>.zip`
- `dist/release-assets.txt`
- updated `../UniGlo-gh-pages/appcast.xml`
- updated `../UniGlo-gh-pages/releases/`

## Publish the release

The GitHub Actions workflow handles this automatically on `v*` release tags and
manual workflow dispatches.

UniGlo follows the same release flow as `Hardlinker`: ordinary pushes to `main`
do not publish a GitHub Release. To publish, push a `v<version>` tag or run the
workflow manually with the desired version and build number.

Manual local publishing works like this:

1. Create the GitHub release tag if it does not already exist.

2. Upload every asset listed in `dist/release-assets.txt` from the local
   `gh-pages/releases/` directory to the GitHub release for tag `v<APP_VERSION>`.

Example:

```bash
while IFS= read -r asset; do
  gh release upload "v1.0.0" "../UniGlo-gh-pages/releases/$asset" --clobber
done < dist/release-assets.txt
```

3. Commit and push the `gh-pages` branch updates:

```bash
cd ../UniGlo-gh-pages
git add appcast.xml releases
git commit -m "Update appcast for v1.0.0"
git push origin gh-pages
```

## Verify the feed

```bash
curl -I https://joshferrara.com/UniGlo/appcast.xml
curl https://joshferrara.com/UniGlo/appcast.xml | head
```

Then install an older copy of UniGlo and run `Check for Updates…`.

## Notes

- The `gh-pages/releases/` directory is a generation cache, not the canonical
  download location.
- The public appcast entries point at GitHub Release assets, matching the
  `Hardlinker` setup.
- Sparkle compares the build number generated from the GitHub run number, so a
  tagged release with the same marketing version can still supersede an older
  build.
- Keep the private Sparkle key out of git.

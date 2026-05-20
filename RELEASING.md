# Releasing Hertz

Releases are fully automated. Push a version tag — GitHub builds the app and
publishes it, and every installed copy auto-updates within 24 hours.

## Cut a release

1. Land your changes on `main`.
2. Pick the next [semver](https://semver.org) version, e.g. `0.3.0`.
3. Tag and push:

   ```sh
   git tag v0.3.0
   git push origin v0.3.0
   ```

That's it.

## What happens

The `release.yml` workflow triggers on the `v*` tag:

1. A macOS runner checks out the tag.
2. `scripts/bundle.sh` builds `Hertz.app` — the version is stamped from the
   tag (`HERTZ_VERSION`), so the in-app updater compares correctly.
3. The bundle is zipped (`ditto`) to `Hertz.app.zip`.
4. A GitHub Release is created for the tag with the zip attached.

## How users get it

- **New install** — `install.sh` pulls `releases/latest` and downloads the zip.
- **Existing install** — the app checks `releases/latest` on launch and every
  24h; a newer tag triggers a silent download, swap, and relaunch.

So a release reaches everyone within a day, no action on their part.

## Versioning

- `vMAJOR.MINOR.PATCH`. The leading `v` is required for the tag; it is stripped
  for `CFBundleShortVersionString`.
- The updater does a numeric comparison — `v0.10.0` is correctly newer than
  `v0.9.0`.
- Don't reuse a tag. To redo a release, bump the patch number.

## Rolling back

Publishing an older-numbered tag won't help — the updater only moves forward.
To pull a bad release: ship a fix as a higher version (e.g. `v0.3.1`).

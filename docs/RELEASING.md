# Releasing a Mac update

BYE uses [Sparkle 2](https://sparkle-project.org) for in-app updates. Both GitHub repositories are
private, so installed copies read `https://bye-website.jack-truong2k1.workers.dev/updates/appcast.xml`
from the BYE website (a Cloudflare Worker) and download the update zip from the same folder.
Every update zip must be signed with BYE's EdDSA key or installed copies refuse it.

## One-time setup

- **Signing key.** The private key lives in the release Mac's login Keychain under the account
  `bye-before-you-enroll`. The public key is `UPDATE_PUBLIC_ED_KEY` in `scripts/update-config.sh`.
  Back up the private key to offline storage, never into the repository:

  ```sh
  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account bye-before-you-enroll -x bye-sparkle.edkey
  ```

  If the key is lost, installed copies can no longer update; testers would have to reinstall by hand.
  Restore it on another Mac with `generate_keys --account bye-before-you-enroll -f bye-sparkle.edkey`.
- **Developer ID (optional, later).** After joining the Apple Developer Program, store notarization
  credentials once and export the signing settings before building:

  ```sh
  xcrun notarytool store-credentials BYE_NOTARY --apple-id <apple-id> --team-id <team-id>
  export BYE_SIGN_IDENTITY="Developer ID Application: <Name> (<team-id>)"
  export BYE_NOTARY_PROFILE=BYE_NOTARY
  ```

  Without these variables builds stay ad-hoc signed. Changing the signing identity later is safe
  because the EdDSA key stays the same.
- **Public `/updates/` folder.** The website is behind Cloudflare Access, which installed apps
  cannot sign in to. In the Cloudflare dashboard, open **Zero Trust → Access → Applications → Add an
  application → Self-hosted**, set the domain to `bye-website.jack-truong2k1.workers.dev` with path
  `updates`, and give it a policy with action **Bypass** and include **Everyone**. The rest of the
  site stays behind sign-in. Check it without signing in:

  ```sh
  curl -I https://bye-website.jack-truong2k1.workers.dev/updates/appcast.xml
  ```

  It must answer `200`, not a `302` redirect to `cloudflareaccess.com`.

## Each release

1. Bump `BETA_VERSION` and **increase** `BETA_BUILD` in `scripts/beta-version.sh`. Sparkle compares
   the build number; `make-appcast.py` refuses a build lower than the newest one in the feed.
2. Write the release's `## What changed` bullets in `docs/GITHUB_PRERELEASE.md`. They become the
   update's release notes in the app.
3. Build and package:

   ```sh
   ./scripts/build-app.sh
   ./scripts/package-beta.sh
   ```

   This creates the DMG (first installs), the update zip, both `.sha256` files in `dist/`, and adds
   the release to the repo-root `appcast.xml`, which keeps every release's record.
4. Copy the release into the website repository:

   ```sh
   python3 scripts/publish-to-website.py ~/Documents/Project/repos/<website-repo>
   ```

   It copies the zip and `appcast.xml` into the site's `updates/` folder and the DMG into its
   downloads folder, and adds a 5-minute cache rule for the appcast to `_headers`. It checks the
   appcast, sizes and checksums first, and never commits or deploys.
5. In the website repository, point the download button at the new DMG, review the diff, then commit
   and deploy. The zip and the appcast go live in the same deploy, so installed copies never see an
   appcast that names a missing zip. They find the update at their next daily check, or immediately
   through Check for Updates….
6. Commit the source repository's `appcast.xml` and version bump as the release record.

## Local update test (no publishing)

Build an isolated copy with a different bundle identifier and `SUFeedURL` set to
`http://127.0.0.1:<port>/appcast.xml`, then serve a higher build's zip and an appcast from a
scratch folder with `python3 -m http.server`. Write the test appcast to the scratch folder with
`BYE_APPCAST`, or by calling `scripts/make-appcast.py` directly, so the repository `appcast.xml`
stays untouched. Record results in `docs/verification/`.

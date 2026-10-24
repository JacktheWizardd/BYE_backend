# Retirement handoff — local source commits; unpublished release

The latest behavior is a shutdown notice plus updater. Mac removal is manual through Trash. Windows has Uninstall BYE, using its existing interactive registered uninstaller, or Installed apps for missing/unsafe registration; portable-copy removal remains manual. No custom cleanup or self-delete feature ships.

## Artifacts and local preview

- `test/BYE Test.app`: minimal local preview, updates disabled by default.
- `dist/retirement/BYE-0.5.1-AppleSilicon.zip`: signed Mac update.
- `dist/retirement/BYE-0.5.1-AppleSilicon.dmg`: local ad-hoc signed Mac installer image.
- `dist/retirement/appcast.xml`: prepared feed, not installed in the website.
- `dist/retirement/BYE-Retirement-0.5.1-windows-x64.zip`: portable Windows build, pending real Windows acceptance.
- Artifact checksum sidecars are beside each package. Ignore everything in `superseded-do-not-publish` and verification/staging directories.

## GitHub Desktop — legacy application repository

Summary:
```text
Prepare minimal BYE 0.5.1 retirement applications
```

Description:
```text
Add a separate Swift/Sparkle retirement product and minimal Electron retirement package. Remove legacy features from the distributed builds while preserving source history, saved data and existing release archives. Show a shutdown notice, version, update check, application-folder control and quit. Windows can open BYE's validated registered interactive uninstaller, falling back to Installed apps. No custom cleanup or self-deletion ships.

Route Mac 0.5.1/build 11 build/test/package scripts to the minimal product. Prepare signed local artifacts and support explicit retirement artifact/feed paths in website staging tooling.

Verified: 258 native tests; final 3-test native policy rerun; 8 retirement JS tests; 42 Python tooling tests; Mac upgrade rehearsals from 0.4.0 and 0.5.0; package signatures/checksums; browser renderer fixtures at 390/1280. Actual Windows and remaining release gates are pending. Local source commits authorized; release unpublished.
```

Include only retirement changes: `Package.swift`, `.gitignore`, the added retirement source/test/app directories, release scripts, retirement notes/verification and the new AGENTS current-state note. Preserve unrelated existing `docs/codex-prompt-seat-freshness.md` and `docs/verification/updater-0.5.0-2026-10-22.json`; they predated this task. Generated packages, test output, caches and keys must stay out of Git.

## GitHub Desktop — website repository

Summary:
```text
Preserve BYE shutdown and prepare retirement update delivery
```

Description:
```text
Keep the existing offline work and add a global uncached retirement gate for public pages, old assets, downloads and website API handlers. Preserve exact Mac feed/archive access. Prepare Windows 0.5.1 metadata and a narrowly scoped portable-package download behind a disabled readiness gate. Make normal builds verify the holding pages instead of regenerating the active application.

Verified: typecheck, 104 tests, build/static checks and Chromium/WebKit retirement fixtures at 390/1280. Windows delivery remains disabled pending native acceptance and artifact hosting. No deployment or release publication was performed; reconcile local changes with remote main's earlier shutdown commit before any later push.
```

The landing download flags, ordinary download redirects, holding page/CSS and copied public pages already had another agent's offline changes. Preserve them; retirement copy was updated in place. Include the new gate, release-state JSON, tests, build/static protection, browser acceptance script and operations notes with the reviewed combined shutdown change.

## Release preparation after review

Do not publish until platform gates in the verification note are satisfied. The website staging tool now accepts `--dist dist/retirement --appcast dist/retirement/appcast.xml`; it still only copies files and never commits or deploys. This command has not been run against the website here. Keep Windows readiness false until its exact portable ZIP is hosted and native launch/uninstall acceptance is recorded. A push to the production website can deploy it and needs a separate explicit request.

## Authorized publication record — October 23

After staging the combined RMP-removal/shutdown release, the owner explicitly approved publishing Mac and requested Windows publication too. Earlier unpublished/hold statements above describe preparation; this new instruction supersedes the publication hold without changing native test evidence. Windows remains unverified on a real Windows machine, and the reported existing uninstaller integrity error is unresolved. The original verification note and generated package report are historical evidence and remain unchanged.

Publish only the final Windows portable ZIP and checksum to public BYE-releases v0.5.1. SHA-256: `8116d58d617ae0cc1bb29c32c0f1ce630c5ffbc6e847d421629eaf17dc305cb2`. Extract into a fresh folder; this package does not automatically replace or clean the old installation. Do not publish the superseded cleanup prototype. Mac's final signed ZIP/feed were staged using the release script. Website metadata enables only the exact retirement download; all public features/APIs remain closed.

GitHub Desktop Summary:
```text
Record authorized Mac and Windows retirement publication
```

Description:
```text
Record the owner's authorization to publish the prepared 0.5.1 retirement builds on Mac and Windows. Preserve earlier verification evidence and explicitly retain the Windows native-testing limitation and reported existing uninstaller integrity error. Windows uses the checked portable ZIP, not a new installer; Mac uses the signed Sparkle feed.

Rechecked final artifact checksums and ZIP integrity. No application code, service keys, databases or unrelated files changed in this follow-up.
```

# BYE 0.5.1 retirement verification — October 23, 2026

## Current outcome

Prepared locally and unpublished. The owner subsequently authorized local source commits only; publication and deployment remain separate. Mac version 0.5.1/build 11 retains the existing bundle identity, public update feed and Sparkle signing key. The Keychain signing account worked; the private-key backup was not opened or copied.

The owner revised the behavior to a retirement notice with manual removal. The custom Windows cleanup installer prototype was removed from source; its ignored local artifact was moved to `dist/retirement/superseded-do-not-publish`. Final Windows delivery is `BYE-Retirement-0.5.1-windows-x64.zip`. Neither application contains a self-delete operation.

## Checks run here

- All 258 native XCTest tests passed, including the three new retirement policy tests. After final Mac notice-copy changes, the three retirement tests passed again.
- Eight retirement JavaScript tests passed; syntax checks passed for main, preload, renderer, updater policy and uninstall modules.
- Forty-two existing Python release/tooling tests passed after adding explicit artifact/feed arguments to the website staging script.
- Mac app allowlist, excluded legacy-code markers, distribution privacy checks, deep strict codesign verification, DMG integrity and artifact SHA-256 checks passed.
- The final update ZIP's EdDSA signature verified using the existing Keychain account; changing a byte caused verification to fail. This is a cryptographic verification test, not a full in-app corrupt-update rehearsal.
- Real Mac Sparkle updates were rehearsed on isolated archive copies of 0.4.0 and 0.5.0. Both installed version 0.5.1/build 11, matched the corresponding minimal executable and removed the old RMPReader.js resource. Neighbor sentinel files remained unchanged. Explicitly reopening each updated app showed only the retirement UI. The 0.4.0 rehearsal used an earlier notice-copy draft of the same minimal product; 0.5.0 used the final manual-removal copy.
- A first 0.4.0 attempt under a loopback-only process sandbox downloaded the signed archive but failed to submit Sparkle's launchd installer job. Retrying through the normal OS updater on the isolated copy succeeded. Old 0.4.0 may directly request public PCC semester metadata before updating; it is not controlled by schedule-key revocation. No search, professor selection or account sign-in was performed.
- The real Mac test app rendered the notice; Show application folder selected precisely `test/BYE Test.app` in Finder. Test builds omit the update feed unless explicitly enabled. Verification copies use separate bundle identities; original release archives were preserved.
- Windows x64 Electron 44.7.0 runtime ZIP matched the pinned package's checksum before extraction. The portable package was built on Mac with electron-builder 26.0.12, its ZIP integrity/checksum passed, and its ASAR contains only the minimal application, license/font assets and uninstall launcher. No AI dependency, search/account/API implementation or cleanup helper is packaged.
- Windows renderer fixtures passed Chromium/WebKit at 390 and 1280 pixels: retirement notice, update status, Installed apps fallback status, 44px controls, no horizontal overflow, no external renderer requests. These are browser tests, not actual Windows acceptance.
- Website typecheck, all 104 tests, retirement-preserving build and static verification passed. Holding-page fixtures passed Chromium/WebKit at 390/1280, with no horizontal overflow/external requests and uncached API rejection.

## Boundaries and limitations

Actual Windows 0.4.0/0.5.0 launch, registry lookup, interactive uninstaller execution/cancellation, junction rejection and Installed apps fallback must be checked on Windows before publication. BYE quits after successfully opening the registered uninstaller so it does not block removal. The existing Windows uninstaller controls its standard cleanup, including shortcuts/registration and the BYE installation folder; BYE adds no deletion code or silent/data-removal arguments. Personal files placed inside that old installation folder may be removed by the standard uninstaller. Portable copies are removed manually.

The Mac builds are ad-hoc signed, not Developer ID notarized. Full in-app corrupt-update rejection, clean-machine/Gatekeeper checks, production delivery and packet-capture network acceptance are pending. Source/package inspection and local feed observations support the retirement network claim; no packet capture was performed.

Windows delivery remains disabled in website `retirement-release.json`. The Mac feed stays on its previous public record until an explicitly approved release copies the signed ZIP/feed. Existing service-key revocation was reported by the owner; this implementation did not revoke or inspect keys, change databases or deploy backend services. Previously downloaded copies and source history remain available.

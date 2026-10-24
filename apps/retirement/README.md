# Minimal BYE retirement application

Version 0.5.1. Ships only the retirement notice, version, bounded manual update check, show-folder, quit and Windows Uninstall BYE launcher. No runtime npm dependencies, legacy app imports, AI implementation, saved-data migration or custom file deletion.

Use the pinned lock with `npm ci --offline --ignore-scripts`, `npm test`, and `npm run typecheck` (JavaScript syntax checks). `node tests/browser-acceptance.mjs` uses the existing pinned Playwright tooling from `apps/cross-platform` in this repository; it does not run a Windows uninstaller. Actual Windows acceptance remains required.

For packaging, set `BYE_RETIREMENT_ELECTRON_DIST` to the checksum-verified Electron 44.7.0 Windows x64 runtime and run `npm run package:win`. Existing artifacts are not overwritten. Extract the portable ZIP into a fresh folder, without overlaying an old installation.

Uninstall BYE reads only the fixed existing BYE HKCU registration, validates DisplayName, root/path, file kind and absence of links, and accepts only the quoted Uninstall BYE.exe command with optional /currentuser. It adds no /S, /allusers or --delete-app-data arguments and invokes no shell. After successful launch BYE quits so the standard uninstaller can proceed. Invalid or missing registration opens Installed apps instead. Windows controls its usual interactive confirmation and cleanup; personal files inside the old installation folder may also be removed. Portable copies can be removed manually.

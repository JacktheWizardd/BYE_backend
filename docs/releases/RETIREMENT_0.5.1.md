# BYE 0.5.1 retirement

Prepared locally; not published. The owner chose a notice and manual removal on October 23, 2026 after disabling the service key independently.

## What changed

- BYE has shut down. The replacement application displays a retirement notice and retains application updates.
- Search, ratings, reviews, accounts, schedules and AI implementation are absent from the new package.
- The application contains no automatic file-removal or self-deletion feature.
- Mac: quit and move BYE to the Trash. Windows: use Uninstall BYE to open its existing registered, interactive Windows uninstaller. If unavailable, Installed apps opens with manual portable-copy instructions. No silent or delete-app-data flags are added. Show application folder reveals the running copy.
- Saved data outside the application folder remains in place. Previous downloads and backups remain in the user's control.

## Release gates

Actual Windows packaged runtime and manual-update checks are required before release. Delivery is a portable ZIP, with no custom installer or file-cleanup helper. Users remove the previous Windows app folder manually and extract the new package into a fresh folder; never overlay it onto the old folder.

Mac in-app upgrades from both old versions and corrupt-signature rejection must be recorded. No publication, credential changes or database changes are performed by build scripts. The retired application may make update requests; it has no service API clients.

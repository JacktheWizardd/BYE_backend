# BYE Apple AI Beta 0.3.0-beta.3

An early macOS beta for finding PCC classes and comparing professor ratings and reviews, with experimental Apple on-device summaries.

**Download `BYE-0.3.0-beta.3-AppleSilicon.dmg` from this release's Assets.** The automatically generated source-code ZIP files are for developers, not the installer.

## Install

1. Open the DMG and drag **BYE Apple AI Beta** into **Applications**.
2. Eject the DMG, then open the app from Applications.
3. This beta is locally signed and **not Apple-notarized**. If macOS blocks it, only if you trust this download, follow [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) to approve it in System Settings → Privacy & Security. Managed Macs may not permit approval.

To update, quit the existing Apple AI beta before replacing it in Applications. Saved beta data is retained. The original BYE app remains separate. No terminal commands or additional AI application are required.

## Requirements

- Apple Silicon Mac (M-series); macOS 14 or later for ratings and reviews.
- Apple summaries: macOS 26.4 or later, Apple Intelligence enabled, and its system model ready. macOS supplies the model and may download it initially; model weights are not bundled in this DMG.
- Internet for PCC/RMP data. No Ollama, account or API key is required by BYE.

## Fixes

- Removed identifying local build paths from the distributed app.

- Type `math 5a`, `math5a` or `MATH 005A` to find the official PCC course.
- Equivalent leading-zero review labels now count toward This course and summary evidence. Different subjects and course suffixes stay distinct.
- Clicking the app after closing its window restores the current search/report. Minimized windows come forward without duplicates.
- Search-screen footer simplified to “One simple search.”

## What to expect

Apple summaries are experimental. They can fail, omit valid themes, or show no verified recurring theme. Retry summary is available; ratings and source reviews remain usable. Check any summary against the original reviews. Generation speed varies; a 2–3 second useful-summary experience is not guaranteed.

RMP retrieval uses an unofficial endpoint and may fail or change. BYE reduces request exposure by avoiding RMP webpage trackers, persistent cookies and login state. RMP still sees your public IP and requested queries/profiles; this is not anonymity. Summary generation runs locally with no automatic cloud/Ollama fallback. External source links open separately in your browser.

Credits and license notices are included at `BYE Apple AI Beta.app/Contents/Resources/THIRD_PARTY_NOTICES.txt`.

## Feedback for this beta

Please report your macOS version and Mac chip, the course/semester, what happened, and what you expected. Useful checks: install from the browser download, search `math 5a`, close and reopen the window, try a report/summary, and quit/relaunch to check cached results. Avoid attaching private files or unrelated personal information.

Local install checks do not verify security prompts on another Mac or an actual GitHub browser download. Those remain early-tester checks until results are recorded.

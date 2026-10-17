# BYE development handoff

Updated October 16, 2026.

## Review database foundation verified October 16

The Supabase review database is live with 1,425 PCC professor entries and 1,531 course entries. Jack verified PCC submissions, duplicate and invalid-answer rejection, reviewer-ID privacy, public fields/counts, non-PCC submission/report rejection, one report per user, visibility after two reports, hiding after three, and cleanup of the temporary users and their test data. Codex ran 51 isolated PostgreSQL checks with mocked Supabase auth and four checks for the helper permission fix; concurrent reporting and real email delivery were not tested.

Jack applied the approved helper permission fix and refreshed Security Advisor. Only the intentional authenticated `submit_review` warning remains. Email-code delivery/settings, the student-facing login and review form, Swift comparison statistics, and Mac app integration are still pending. No native app changes or commits were made during this database work.

Student reviews are live at bye-before-you-enroll.pages.dev/reviews/ for PCC students; see the [Review launch record](review-launch-record.md). See [Review database explained](review-database-explained.md) for the plain-language guide and [Supabase status and plan](supabase-plan.md) for migrations, test details, and next steps. The hosted schedule-cache service remains a separate proposal.

## Redesign (0.4.0-beta.1, in progress)

**0.4.0-beta.1 (build 8)** is packaged locally in ignored `dist/` (DMG, signed update zip, checksums) and recorded in `appcast.xml`; it is not published to the website yet. The Mac app adopts the new BYE design system: ivory/linen/stone grounds, Jet Black type and buttons, warm grey secondary text, and yellow only for the wordmark swipe, rating bars and the progress meter. It is light mode only. BYE deliberately does not single out a "best" or recommended professor (a "Top pick" label was tried and removed). For the same reason no professor opens automatically: results start on a neutral course overview (`CourseOverview` in ContentView.swift), and a filter that hides the open professor returns there. Libre Baskerville (SemiBold and Bold, under the OFL, listed in the third-party notices) is bundled for headlines and scores and registered at launch. The theme and shared components live in `Sources/Classwise/Views/Components.swift`. The app icon is the wordmark on ivory (`assets/branding/AppIcon.png`, reproducible with `scripts/render-wordmark-icon.swift`).

Class cards add data PCC's `classSchedule` feed already sent but BYE ignored: `seatsAvail`, `maxEnrl`, `waitCount`, `waitCapacity`, `ptrmDesc` (term part), `campDesc` and `creditHrLow`. These are parsed into the optional `Section.details` (`SectionDetails`); older caches decode with `details == nil`. The format label (In person, Hybrid, Online · live, Online · async) is derived from the existing schedule codes, and filtering behaviour is unchanged. Design references are the design-system and prototype artifacts linked in the commit notes. The class-day filter changes meaning in 0.4.0: a section matches when it meets on every picked day (it may meet on other days too). Before 0.4.0 it had to meet only within the picked days. Fully online sections still always match, and sections with no announced days still never match (`Section.fits(availableDays:)`). The website redesign is not started.

## Current application

Beta.4 baseline (superseded by beta.5 below, which adds in-app updates): **BYE Beta 0.3.0-beta.4 (build 6)**, Apple Silicon, macOS 14+. AI summaries are paused: normal launches skip provider construction, model prewarm, generation, summary retry, and cached-summary display. Raw reviews and profile choices remain usable, and existing summary files are retained. The visible app name changes from BYE Apple AI Beta to BYE Beta; the bundle identifier and `BYEAppleAIBeta` storage directory stay compatible. Export filename: `BYE-0.3.0-beta.4-AppleSilicon.dmg`. Publishing is a separate manual step. Historical beta records below describe those versions’ behavior.

- Production RMP retrieval uses the dedicated Swift **BYEAPI** module and native URLSession, independently of AI. Legacy WebKit code remains only for comparison/regression tests; there is no automatic browser fallback.
- Shared client transport: two concurrent requests, 100 ms start spacing, 15-second request / 25-second resource timeout, at most three attempts for transient network/selected HTTP failures. Retry-After is respected up to 30 seconds; longer waits produce a recoverable failure. Cursor progress and page-size checks prevent unbounded pagination.
- Initial lookups, discovery, retries and chosen-profile verification share two preview readers; detail retrieval has a single-worker queue; the retained summary queue is disabled in ordinary beta.4 launches. New optional jobs pause while preview work is pending. Cancellation and search/professor/profile/evidence checks prevent stale publication or cache writes.
- Verify source ID, name and PCC identity on each retrieved profile page. Deduplicate candidate IDs; preserve compound surnames. Multiple eligible same-name profiles always require explicit selection regardless of department, rating or AI. Retain candidates after later search-page failures; at most three additional search pages.
- Keep profiles separate. Chooser dismissal leaves unresolved identities unresolved. Change profile preserves existing data until confirmation, then clears the old report immediately and retains PCC sections. Fresh ambiguity also clears a prior automatic report.
- Manual choices persist by normalized instructor name and subject; fresh retrieval reverifies them. Temporary failures retain choices, identity mismatches invalidate them and return to selection. Individual Try again bypasses the professor's identity-cache lookup without discarding other results.

## In-app updates (beta.5)

Current locally prepared beta: **BYE Beta 0.3.0-beta.5 (build 7)**, the first build that updates itself. It includes all unpublished beta.4 changes; beta.4 users install beta.5 by hand once.

- Sparkle 2.10.0 (MIT, pinned exactly) is embedded at `Contents/Frameworks/Sparkle.framework`; its optional XPC services are removed because BYE is not sandboxed. The executable gets an `@executable_path/../Frameworks` rpath from `Package.swift`.
- `AppUpdater` (`Sources/Classwise/Updater.swift`) starts Sparkle only when Info.plist has an HTTPS `SUFeedURL` (or a localhost verification feed) and `SUPublicEDKey`. `BYE Test.app`, DEBUG runs, and audit/evaluation builds stay inert and never contact the feed.
- Defaults: automatic daily checks, background download, install on quit, no system profiling. "Check for Updates…" is in the app menu; Settings has toggles for checks and automatic installation.
- Feed: both GitHub repositories are private, so updates are served from the website on Cloudflare Pages at `https://bye-before-you-enroll.pages.dev/updates/appcast.xml`, with zips beside it. (It briefly used the `bye-website.jack-truong2k1.workers.dev` Worker before any build was distributed; that Worker is kept as a backup.) `scripts/package-beta.sh` builds and signs the zip and updates the repo-root `appcast.xml` (the release record); `scripts/publish-to-website.py <website-repo>` copies the appcast, zip and DMG into `public/` and adds a 5-minute cache rule in `_headers`. The feed address is built into each release, so it must keep working once a build is installed. Release steps and key backup are in `docs/RELEASING.md`.
- The EdDSA private key is in the login Keychain (account `bye-before-you-enroll`); only the public key is in `scripts/update-config.sh`. Signing is ad-hoc by default; `BYE_SIGN_IDENTITY` and `BYE_NOTARY_PROFILE` turn on Developer ID signing with hardened runtime, notarization and stapling.
- Privacy: update checks contact the BYE website (Cloudflare Pages) about once a day; Cloudflare sees the public IP address and app version. This is the only new network destination.

Verification: 177 Swift tests (173 earlier + 4 updater) and 16 Python script tests passed (including 5 for the website publish script). After the switch to website hosting, the local 7 → 8 update test passed again. A local end-to-end test with an isolated bundle identifier and localhost feed confirmed automatic check, download, install on quit (build 7 → 8), rejection of a byte-tampered build 9 that had a valid signature for the original bytes, then installation of the restored build 9 and a successful relaunch. Record: `docs/verification/updater-beta5-2026-10-14.json`. Live check on `bye-before-you-enroll.pages.dev` (October 14, 2026, no sign-in): the website's appcast matches the build, the zip downloads with a matching checksum and valid EdDSA signature, `/download` serves the beta.5 DMG byte for byte, and the appcast is cached for at most 5 minutes. Not yet tested: a real installed-copy update from the live site (needs beta.6), a browser-quarantined first install followed by an update, Developer ID signing/notarization, and another Mac.

## Cache and review courses

Retained Apple summaries use a separate v5 cache scoped by provider/OS/policy, profile, subject, course and exact whole-review evidence, with a 24-hour generated-summary lifetime. Beta.4 skips summary cache reads/writes and preserves these files; research builds retain provider-specific validation. Legacy Ollama summaries are misses for Apple. Beta data lives separately in `~/Library/Application Support/BYEAppleAIBeta`. Version 4 raw caches use school/profile ID, last 24 hours and are reused across courses. Automatic identity indexes use normalized instructor name and subject. Course summaries are separate and require matching profile/course/subject/review evidence; changed text invalidates a summary even if review IDs are unchanged. Incompatible v3 and older files remain untouched as misses. Refresh bypasses caches; partial review coverage/cursors persist across restart.

The Review course menu offers This course, All courses and original source labels/counts. Switching filters and revealing more downloaded reviews are local. Only **Find more for this class** sends a class filter to RMP. Keep three-review previews and a maximum of 50 source ratings retrieved per filter; combined cached raw data may exceed 50 when different classes are explicitly requested. Blank comments can make downloaded text counts lower than source-rating coverage. Overall source scores remain professor-wide.

## Privacy and attribution

RMP gets an ephemeral session with no cookie/credential store, persistent URL cache or redirects. Minimal typed requests fetch required data without webpage ads, scripts or analytics. Student comparisons, sorting, preferences, schedule context and summary prompts remain local. RMP still sees the public IP, timing and query/profile; this is exposure reduction, not anonymity. User-clicked source links open their browser separately. PCC networking remains unchanged.

Amaan's MIT license, copyright and reference revision are in THIRD_PARTY_NOTICES.md and the app resources. No code with an unverified license was borrowed. No hosted server, proxy, Tor, OHTTP or cloud AI was added.

## Beta.4 export verification

**173 Swift tests and five Python distribution tests passed.** Disabled-mode tests cover zero provider/prewarm calls, review expansion/retry, cached-summary suppression, and preservation of summary files. Release, audit, and model-evaluation debug builds compile. The evaluation build’s debug storage override is isolated from normal launch verification.

The local beta.4 app and DMG pass strict signature, arm64, privacy, integrity, and checksum checks. Mounted app files match the exported bundle byte for byte; version/build, installation text, Applications link, and bundled notices were verified. Native UI checks confirmed the pause notice, original reviews, six sort options, weekday filtering/clearing, and window reopening. The updated stable test app is in `test/BYE Test.app`.

Export assets are in ignored `dist/`; upload the `.dmg` and `.dmg.sha256` manually with `docs/GITHUB_PRERELEASE.md`. No release was published. Another-Mac and browser-download/quarantine checks remain pending. Record: `docs/verification/beta4-export-2026-10-12.json`.

## Beta.3 privacy cleanup and local commit

Removed identifying local paths from the relocation verification record. The old generated app is no longer tracked; all of `dist/` is ignored, while local original apps, older DMGs and ignored history archives remain preserved. Source, tests, scripts, documentation and third-party notices remain included.

Release compilation remaps project/home paths to neutral build paths and strips debug records before signing. Release resource lookup avoids SwiftPM's generated accessor, which embeds an absolute build directory; DEBUG tests retain the accessor. A recursive byte-level packaging gate checks personal home/temp paths, local username, UTF-8/UTF-16 and common credential markers in the app/staging/mounted image. This is a targeted check, not proof that every possible secret or identifier is absent.

**140 Swift tests and five Python privacy-gate tests passed.** Release, strict app/DMG signatures, DMG integrity/checksum, arm64, notices and installed-build byte equality passed. Installation from the beta.3 image preserved existing application data; ejection and launch passed. Shorthand `math 5a` found Winter 2027 MATH 005A (8 sections/7 professors); 10 same-course reviews remain recognized; close/reactivate restored the same report. No new AI speed/quality claim. Remapped debug-module warnings occurred during compilation; stripped distribution app passed launch checks.

Local beta.3 DMG/checksum and updated prerelease notes are prepared. The published beta.2 installer and downloaded copies retain previous paths. Older Git commits also retain them. No history rewrite, push, tag change or release upload is included. Actual GitHub browser download, another Mac, physical Dock click and full VoiceOver remain unverified. Record: `docs/verification/privacy-beta3-2026-10-10.json`.

## Historical beta.2 installer verification

**140 tests passed, zero failures** after the window lifecycle adjustment. Release and DMG signatures, checksum/integrity, arm64 architecture, source archive hashes and bundled notices verified. Updated `/Applications/BYE Apple AI Beta.app` from the DMG, ejected it, and launched it; existing application data was unchanged by installation. The original 0.2.0 executable still matches its baseline hash.

Course shorthand resolves through the selected semester catalog to its official label. The shared comparison ignores leading numeric zeros without rewriting source labels/cache keys. Suggestions, This course filtering, evidence selection and course counts use this equivalence. Apple’s provider policy identity changed so previous summaries are misses, while raw reviews remain reusable. The retained main window restores the current app model after closing and reactivation; minimized windows come forward. New search also brings the window forward.

Installed Winter 2027 checks: `math 5a` and `math5a` found MATH 005A, 8 sections/7 professors. Anahit Asadyan: 10 MATH5A reviews of 47 downloaded are now recognized as same-course; summary analyzed all 10 and returned no verified theme. Two close/reactivate cycles and minimize/reactivate restored `main-AppWindow-1` and its report. Footer is “One simple search.” Activation used LaunchServices through computer-use controls; a physical Dock click and full VoiceOver session were not tested.

Single build metadata source: `scripts/beta-version.sh`. Local assets: `dist/BYE-0.3.0-beta.2-AppleSilicon.dmg` and its SHA-256 file. GitHub prerelease notes: `docs/GITHUB_PRERELEASE.md`. Not notarized; no tag, commit or upload. Actual GitHub download/quarantine and another-Mac testing remain pending. Record: `docs/verification/dmg-beta2-2026-10-10.json`.

## Historical Apple beta.1 verification

Full suite: **136 tests passed, zero failures**. Release and DMG signatures passed. Mounted the DMG, copied the beta into Applications, ejected it, and launched the installed copy. Restart retained the Anahit Asadyan summary. Hoa Ly initially returned a recoverable generation error; Retry summary completed while preserving ratings and reviews. See the Apple installation, speed, quality and trial records in `docs/verification/`.

Apple generation measured 2.828 seconds on first process use and 2.866 seconds for a prewarmed report using previously retrieved verified evidence. Both produced a conservative no-theme result, so these are **not useful-summary latency**. Cache read took 0.762 ms and cached report selection logic 0.012 ms; neither is screen-rendering time. Fresh network-to-report latency was not measured for this beta. The real sample used 19 complete reviews of 47 downloaded and zero exact-course labels. Five fictional quality cases yielded two supported positives and three conservative results, including an omitted valid concern. The grounding gate reduces misleading output but can discard useful themes; semantic correctness is not proven.

No separate AI host or Ollama fallback is used. The system supplies model weights; they are not bundled in the DMG and may require an initial macOS download. Another Mac, downloaded-app quarantine prompts, a genuinely OS-cold model and packet-level traffic capture remain unverified.

## Historical 0.2.0 verification

- Full suite: **125 XCTest tests passed, zero failures**. Coverage includes transport privacy/size bounds, retries/cooldown/cancellation/concurrency, native identity and pagination, local filtering and explicit course jobs, partial retry cursors, shared cache/subject isolation/restart, ambiguity recovery, and stale reviews/summaries. Existing legacy WebKit regressions also pass. On the test Mac the browser tests required an unsandboxed test process; sandboxed attempts stalled and were stopped before the successful complete run.
- Release build and strict deep code-signature checks passed; notices were compared byte-for-byte with the bundled copy. Build scripts automatically save before/after snapshots under ignored archive/app-history/. Archived executable/source hashes were verified against their manifest.
- Live Winter 2027: Daniel Hamman (POLSC 1000) and Jose Lopez (ETH 014) each returned two eligible profiles and required selection. All four identities were individually verified. Isolated app-model checks passed dismissal, persisted preferences, fresh verification, wrong-identity recovery to selection, replacement and cross-course cache reuse. An unavailable loopback summary endpoint preserved API data without using or changing a running Ollama service.
- Native visual checks used a temporary app/storage: Winter 2027 Daniel ambiguity, chooser dismissal/reopening, Political Science selection, actual quit/relaunch persistence, Change profile to History, correct replacement source/reviews, original course-label menu/counts, local All courses filtering, explicit POLS001 expansion from 24 downloaded to the 50-rating limit against 86 reported by RMP, unchanged overall scores, and failed-summary retry retaining data. Temporary preferences were removed afterward. The release UI uses the same views; the acceptance-only storage/failure flags are DEBUG-only.
- Fresh MATH 005A / Fall 2026 native ratings pass: **2.05 seconds first result, 6.44 seconds overall**, 35 sections, 26 professors, 21 verified previews, three ambiguous and two unavailable. Every preview was capped at three. Earlier WebKit observation: 2.83/16.81 seconds. These are separate runs, not a controlled benchmark or latency guarantee.
- Live known-profile previews were approximately 0.14 seconds. Cross-course raw-cache reads after store recreation were approximately 0.0013–0.0020 seconds in the last isolated run; these do not measure complete app startup or a full-course cached search.
- Records: docs/verification/native-api-matching-2026-10-10.json, native-api-speed-2026-10-10.json and native-api-acceptance-2026-10-10.json. Earlier matching milestones remain in the October 9 records.

## History and remaining limitations

The pre-implementation app/source baseline was preserved. Each build now saves a prior-app/current-source snapshot before building and a matched app/source snapshot after successful signing. Manifests distinguish these associations; snapshots exclude private user data and do not roll back Application Support.

RMP's endpoint is undocumented and can change or reject requests; client tests cannot guarantee future server availability. A forced live RMP outage/rate limit and packet-level traffic capture were not performed. Failure/retry/cooldown/cookie/header behavior was inspected with deterministic URLProtocol tests, plus live identity-mismatch recovery. A complete VoiceOver session, another Mac, notarization/distribution and Windows remain unverified. The toolchain still emits its existing native SwiftPM-backend deprecation warning.

Leading-zero shorthand is implemented for searches and downloaded review matching. Apple on-device summaries are now experimental in the separate beta; Ollama remains only for explicit legacy regression checks.

No commit or upload was performed.

## Separate Windows cross-platform beta — October 10, 2026

`apps/cross-platform` now contains an independent Electron/React/TypeScript 0.1.0-beta.1 application with direct PCC/RMP requests, explicit profile selection, separate job queues, persistent evidence-aware caches and bundled CPU Qwen3-4B inference. Swift application files remain unchanged. Windows ZIP packaging includes the model and licenses; see `apps/cross-platform/VERIFICATION.md` for measured results and limitations. The initial packaged startup failure was corrected by preserving required inference metadata and deferring native AI imports. The Windows beta remains unsigned and requires clean-machine acceptance before being described as release-ready. No Mac package of this separate application is claimed.


# BYE — Before You Enroll

**Find classes. Compare professors. Enroll with more confidence.**

BYE (Before You Enroll) is a free, independent desktop application that helps college students research classes and compare professors before enrolling.

Instead of opening dozens of browser tabs to check class schedules, professor ratings, difficulty scores, and student reviews, BYE brings that information together in one place.

Currently designed for **Pasadena City College (PCC)**, BYE is available in beta for **macOS and Windows**.

> [!NOTE]
> BYE is an independent student project and is not affiliated with Pasadena City College or Rate My Professors.

## Download

**Latest public beta: v0.3.0-beta.4**

Download BYE from the official GitHub Releases page:

**[Download BYE for macOS](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases/latest)**

Since the current public release is a prerelease, you can also access it directly:

[BYE v0.3.0-beta.4](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases/tag/v0.3.0-beta.4)

No programming experience is required to use the packaged application.

Currently there is no plan for windows development but you can access it here:
[BYE V0.3.0-beta.3](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases#release-v0.3.0-beta.3)

## Features

### Course and semester search

Search for PCC courses using familiar course codes, such as `math 5a` or `math5a`.

- Browse available class sections.
- View schedules and delivery formats.
- Filter for fully online classes.
- Find the professors teaching each course.

### Professor comparisons

Compare professors without switching between websites.

- Overall professor ratings.
- Reported difficulty scores.
- Student rating counts.
- "Would take again" percentages.
- Sorting by rating, difficulty, and relevant review coverage.

### Student reviews

Read student feedback directly within the application.

- Filter reviews for your selected course.
- View feedback from other courses.
- Browse additional available reviews.
- Open original Rate My Professors profiles for more context.

Overall professor scores remain separate from course-specific reviews.

### AI summaries temporarily paused

The locally prepared Mac **v0.3.0-beta.4** disables AI summaries while a better solution is evaluated. It shows a short notice and keeps ratings, original reviews, sorting, weekday filters, and retrieval retries available. No summary model is initialized or prewarmed; cached summaries are hidden and their files are retained.

Apple Intelligence, Ollama, and an API key are not required for this Mac build. Earlier published Mac betas retain their original experimental Apple summary behavior. Windows/Electron `0.1.0-beta.2` also has summaries disabled.

See the [prepared beta.4 release notes](docs/GITHUB_PRERELEASE.md). The latest public download remains linked above until beta.4 is published.

### Faster searches and recovery

- Reuse locally cached professor information.
- Load available results progressively.
- Retry failed searches and review retrieval.
- Choose between ambiguous professor profiles.
- Change previously selected profiles.
- Refresh information when necessary.

BYE does not intentionally combine ratings or reviews from different professor profiles.

## Installation

Choose the instructions for your operating system.

### macOS — Apple Silicon

**Requirements**

- Apple Silicon Mac (M-series).
- macOS 14 or newer for ratings and reviews.
- Apple Intelligence is not required for the prepared beta.4 build; older Apple AI betas require macOS 26.4+ for their experimental summaries.
- Internet connection for class schedules and professor data.

**Steps**

<<<<<<< HEAD
1. Open the [BYE v0.3.0-beta.3 release](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases/tag/v0.3.0-beta.3).
2. Expand **Assets**.
3. Download `BYE-0.3.0-beta.3-AppleSilicon.dmg`.
=======
1. Open the [BYE v0.3.0-beta.4 release](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases/tag/v0.3.0-beta.4).
2. Expand **Assets**.
3. Download `BYE-0.3.0-beta.4-AppleSilicon.dmg`.
>>>>>>> 5fc567fce570ba43cb10cc857e260363473f98c9
4. Open the downloaded DMG.
5. Drag **BYE Apple AI Beta** into the Applications folder.
6. Eject the DMG and launch the application.

For the locally prepared beta.4, use `BYE-0.3.0-beta.4-AppleSilicon.dmg` and install **BYE Beta**. Quit the old beta first; after confirming the new app works, remove **BYE Apple AI Beta** to avoid opening the previous version. Saved beta data is reused. See the [beta.4 installation and update notes](docs/GITHUB_PRERELEASE.md#install-or-update).

**macOS security notice**

BYE is locally signed but not currently Apple-notarized.

macOS may display a security warning. If you trust the downloaded application, review the warning in:

**System Settings → Privacy & Security**

Only approve software from sources you trust.

**Updating**

Starting with v0.3.0-beta.5, BYE updates itself. It checks for a new version about once a day, downloads it in the background, and installs it when you quit. Choose **BYE Beta → Check for Updates…** to check now, or **BYE Beta → Settings…** to turn automatic checks or installation off. Each update is verified against BYE's release signature before it is installed.

Earlier betas (beta.4 and older) cannot update themselves: install beta.5 from its DMG once, and later versions arrive automatically.

### Windows — ZIP package

**Requirements**

- A compatible Windows computer.
- Ability to extract ZIP archives.
- Internet connection for class schedules and professor data.

**Steps**

1. Open the [BYE v0.3.0-beta.3 release](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases/tag/v0.3.0-beta.3).
2. Expand **Assets**.
3. Download the Windows ZIP package.
4. Right-click the downloaded file and select **Extract All**.
5. Open the extracted folder.
6. Double-click the BYE `.exe` application.
7. Keep the extracted application files together.

**Windows security notice**

Because BYE is an early beta, Windows SmartScreen or antivirus software may display a warning.

Only launch the application if you trust the source. Do not disable your system's security protections.

**Updating**

Close BYE before extracting and replacing the previous version's application files.


## Privacy

BYE is designed to minimize unnecessary data collection.

- Cached professor information is stored locally.
- Remembered professor profile selections are stored locally.
- Rate My Professors data is retrieved through direct requests rather than loading webpage advertisements, scripts, or analytics.
- No RMP account credentials are required.
- On macOS (beta.5 and later), update checks contact the BYE website about once a day. Its host, Cloudflare, sees your public IP address and app version; no system profile or other information is sent. Automatic checks can be turned off in Settings.

**macOS AI privacy**

The prepared Mac beta.4 does not generate AI summaries or initialize a summary model. Older Mac betas use Apple’s on-device summary generation; summary prompts are not sent to a cloud AI service.

Windows AI processing should be evaluated according to the implementation used by the Windows build.

**Important:** Local processing does not make online searches anonymous.

PCC and Rate My Professors still receive the network requests required to retrieve information. Rate My Professors may observe your public IP address and requested profiles or searches.

External source links open separately in your web browser.

## Known limitations

BYE is still in beta.

- Professor information depends on the availability of external data sources.
- Rate My Professors uses an unofficial endpoint that may change or become unavailable.
- AI-generated summaries may omit relevant information or fail to identify recurring themes.
- Some professor profiles may require manual selection.
- Intel Mac builds are not currently provided.
- Windows is distributed as a ZIP package rather than a traditional installer.
- Compatibility and security prompts may vary across computers.

Always verify important course information using official college resources before enrolling.


## Feedback and bug reports

BYE is actively being developed and tested.

Bug reports, compatibility issues, and feature suggestions are welcome.

**[Report an issue or suggest a feature](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/issues)**

When reporting a bug, please include:

- Your operating system and version.
- The BYE version you are using.
- The course and semester searched, if applicable.
- A description of the problem.
- Steps to reproduce the issue.
- Screenshots, if available.

Please remove unrelated personal information from screenshots.

## Testing and experiment records

BYE keeps records of trials, measurements, failed approaches, and the decisions
that follow. These records explain what was tested, what worked, what failed,
and what remains unverified. Experimental results are kept separate from claims
about published releases.

### Local summarization trials — October 11–12, 2026

The first screening tested LFM2.5-1.2B-Instruct, Qwen3.5-0.8B, and
SmolLM2-360M-Instruct. A later comparison tested nine candidates across twelve
GGUF variants, completing 4,401 development pipelines before testing was stopped.
These counts include failed attempts and repeated runs.

**Outcome:** no tested configuration earned a release recommendation. Observed
problems included unsupported claims, incorrect citation support, lost
disagreements, and incomplete summaries. The remaining tests were cancelled;
unfinished work is explicitly marked as untested. Existing releases were unchanged.

| Record | What you can inspect |
| --- | --- |
| [Experiment overview](docs/experiments/2026-10-11-local-summarization/README.md) | Goals, model lists, protocol, process, findings, and lessons learned |
| [Results and comparisons](docs/experiments/2026-10-11-local-summarization/RESULTS.md) | Timing, memory, prototype bundle sizes, quality findings, and limitations |
| [Recorded data and examples](docs/experiments/2026-10-11-local-summarization/data/README.md) | CSV/JSON measurements, model identities, and fictional input/output examples |
| [Reusable test dataset](benchmarks/datasets/bye-summary-2026-10-11/README.md) | Fixture locations, frozen local corpus, expected facts, and instructions for future testing |
| [Validation record](docs/experiments/2026-10-11-local-summarization/VALIDATION.md) | Checks performed, passing tests, build results, and unverified behavior |
| [App performance audit](docs/verification/bye-app-audit-2026-10-11.md) | Bounded collection, app responsiveness, resource observations, and audit failures |
| [CPU measurement correction](docs/verification/bye-cpu-accounting-erratum-2026-10-11.md) | A discovered accounting error, its impact, and the correction |

One lesson was to introduce an earlier quality stop/go decision before spending
hours on performance repetitions. Future options include extractive summaries,
templates, small classifiers, and fine-tuning; none has been selected or validated
as the replacement.

Public records include numeric results and clearly labeled fictional examples.
Raw student reviews, user caches, model weights, and full machine-specific logs
remain in local storage and are excluded from Git.

## Development transparency

BYE is built with the assistance of AI coding tools while I continue learning software development.

Features are iteratively implemented, reviewed, and tested as the project evolves.

The goal is to build a practical tool that makes college course selection easier and more accessible.

---

**BYE — Before You Enroll**

*One simple search. Fewer tabs.*

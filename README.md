
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

Currently there is no plan for windows development, but you can access it here:
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

### Experimental AI review summaries

BYE can analyze available student feedback and highlight recurring positives and concerns.

- Summaries are based on retrieved student reviews.
- The number of reviews analyzed is displayed.
- Unsupported themes may be excluded.
- Original reviews remain accessible for verification.

**AI availability and processing depend on the operating system.**

On supported Macs, BYE uses Apple's on-device Foundation Models framework. No separate Ollama installation or API key is required.

AI summaries are temporarily disabled in Windows/Electron version `0.1.0-beta.2`, whose ZIP omits inactive model weights. Ratings and original reviews remain available; the summary implementation, development model files and local caches are retained. Native Mac AI and existing published releases retain their original behavior.

AI summaries are experimental and should not replace reading the original reviews.

### Faster searches and recovery

- Reuse locally cached professor information.
- Load available results progressively.
- Retry failed searches and summaries.
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
- macOS 26.4 or newer with Apple Intelligence enabled for AI summaries.
- Internet connection for class schedules and professor data.

**Steps**

1. Open the [BYE v0.3.0-beta.2 release](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases/tag/v0.3.0-beta.2).
2. Expand **Assets**.
3. Download `BYE-0.3.0-beta.2-AppleSilicon.dmg`.
4. Open the downloaded DMG.
5. Drag **BYE Apple AI Beta** into the Applications folder.
6. Eject the DMG and launch the application.

**macOS security notice**

BYE is locally signed but not currently Apple-notarized.

macOS may display a security warning. If you trust the downloaded application, review the warning in:

**System Settings → Privacy & Security**

Only approve software from sources you trust.

**Updating**

Quit the existing application before replacing it with a newer version.

### Windows — ZIP package

**Requirements**

- A compatible Windows computer.
- Ability to extract ZIP archives.
- Internet connection for class schedules and professor data.

**Steps**

1. Open the [BYE v0.3.0-beta.2 release](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/releases/tag/v0.3.0-beta.2).
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

**macOS AI privacy**

On supported Macs, Apple's AI summary generation runs on-device. Summary prompts are not sent to a cloud AI service.

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

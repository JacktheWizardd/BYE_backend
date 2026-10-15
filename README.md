# BYE — Before You Enroll

**BYE is an independent student software project** focused on making college course selection easier. It currently helps Pasadena City College (PCC) students search for classes and compare professors before enrolling.

This is the **private source-code repository**, mainly for development and learning. The separate BYE website is where public information and app downloads belong.

## What BYE can do today

The current app helps students:

- Search PCC courses and see available class sections.
- Review class schedules and filter by meeting days or delivery format.
- Compare professor ratings and difficulty information.
- Read original student reviews and sort available results.
- Choose the correct professor when multiple profiles are similar.

Information comes from PCC and Rate My Professors (RMP). BYE is not affiliated with either organization, and official college information should be checked before making enrollment decisions.

**Current focus:** a native macOS app built with Swift/SwiftUI. There is also a separate Electron/React/TypeScript Windows-oriented beta under `apps/cross-platform/`. Both are experimental; see [project status](docs/PROJECT_STATUS.md) for version details and limitations. AI-generated review summaries are temporarily disabled in the prepared betas.

## What comes later

These are **ideas and plans, not finished features**:

- Let students submit their own professor ratings and reviews to a BYE-owned database.
- Explore a separate hosted PCC class-schedule API/cache to improve speed and reduce repeated requests.
- Eventually let students upload education plans and check transfer requirements and recommended courses.

The two database/API initiatives are separate projects, described in [database plans](docs/database.md). The transfer-planning vision is not yet part of the working app.

## Getting started with the code

### macOS (main development track)

You need a Mac with a compatible Xcode installation and macOS SDK. From the repository root:

~~~sh
./scripts/swift.sh build
./scripts/build-test-app.sh
~~~

This builds a local test application at `test/BYE Test.app`. Open that app to try your changes. It is generated locally and is not committed to Git.

To run the existing Swift tests when you want to check a change:

~~~sh
./scripts/swift.sh test
~~~

### Windows-oriented Electron beta

On Windows x64, install Node 24 LTS (or Node 22.16+) and npm, then:

~~~powershell
cd apps/cross-platform
npm ci
npm run runtime:fetch
npm run dev
~~~

See the [Windows development guide](apps/cross-platform/README.md) for its separate setup and test commands. These commands are for development, not publishing a release.

## Finding your way around

| Location | What's there |
| --- | --- |
| `Sources/Classwise/` | Native Mac app and interface |
| `Sources/ClasswiseCore/` | Reusable course and schedule logic |
| `Sources/BYEAPI/` | Code that retrieves professor information |
| `Tests/` | Existing Swift tests |
| `apps/cross-platform/` | Separate Windows-oriented application |
| `scripts/` | Build and packaging tools |
| `docs/` | Technical notes, plans, experiments, and past verification records |

## How this project is being developed

BYE is currently a student-led project. I define the goals, choose features, and use AI coding tools to help implement parts of the application while I learn programming and software engineering.

The repository contains architecture notes, test suites, and development tools. **Having these files does not mean I personally wrote every part or already follow a formal professional engineering workflow.** They are references I can study and practices I can gradually learn to use.

My long-term goal is to understand, modify, test, and maintain the application more independently—not just have AI generate code.

## Technical notes (for learning when needed)

You **don't need to read these all at once**. Start with the app, then open a guide when you encounter a related question.

- [Development notes](docs/development.md) — how to run the app and optional Git habits to learn.
- [Architecture](docs/architecture.md) — how the pieces of BYE fit together.
- [Testing](docs/testing.md) — what the existing checks do and how to use them.
- [API and integrations](docs/api.md) — where schedule and professor data come from.
- [Database plans](docs/database.md) — the two proposed Supabase-related projects.
- [Project status](docs/PROJECT_STATUS.md) — implementation history, verification, and known limits.
- [Release notes and procedure](docs/RELEASING.md) — advanced reference for preparing Mac releases.

## Privacy and distribution

Do not commit passwords, API service-role keys, personal student data, private caches, model weights, or generated builds. Keep production release steps separate from ordinary local development; see [release documentation](docs/RELEASING.md).

The source repository stays private. Public product information and downloads are maintained separately. RMP is accessed through an undocumented interface that may change; technical access does not automatically grant rights to redistribute its data.

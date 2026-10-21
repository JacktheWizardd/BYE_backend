
# BYE — Before You Enroll

**A student-built course planning project for Pasadena City College.**

BYE (Before You Enroll) helps students explore class sections, compare professor information, and read reviews before registering for classes.

I started BYE as a personal project to make choosing classes less frustrating. What began as a desktop application has expanded into an ongoing experiment in software engineering, including native applications, web development, APIs, databases, and infrastructure.

This repository contains BYE's desktop applications, schedule API, supporting services, tests, and engineering documentation.

> **Development repository:** BYE is an independent student project, not an official PCC application. This repository is private. Public-facing information is available on the [BYE website](https://bye-before-you-enroll.pages.dev).

## Project status

*Updated October 20, 2026.*

BYE is under active development. Different components are at different stages of testing and release.

| Component | Current status |
|---|---|
| macOS application | Native SwiftUI beta; 0.4.0-beta.1 prepared locally |
| Windows application | Electron/React beta; v3 redesign merged into main |
| Public website | Deployed through Cloudflare Pages |
| Browser demo | Available with clearly labeled sample data |
| Student reviews | Live submission system using PCC email verification |
| PCC schedule API | Deployed with Fall 2026 data |
| API dashboard | Hosted owner dashboard with key management |
| Desktop API integration | Pending |
| AI review summaries | Temporarily disabled |
| Transfer planning | Long-term idea, not implemented |

A component being implemented or deployed does not necessarily mean it has been released to students.

## What BYE does

### Course and professor research

The desktop applications are designed to help students:

- Search PCC courses and sections.
- Filter classes by schedule preferences.
- View section information, including available enrollment details when provided.
- Compare professor ratings and original reviews.
- Explore reviews associated with specific courses.
- Resolve professors with similar names without automatically selecting the wrong profile.

BYE provides information to help students make their own decisions. It does not designate a professor as the best choice.

### Student-submitted reviews

BYE also maintains its own review database.

PCC students can visit the [review page](https://bye-before-you-enroll.pages.dev/reviews/) and verify their `@go.pasadena.edu` email address using a one-time code.

Students can then submit ratings and written feedback. The database implements submission restrictions, duplicate prevention, review reporting, and automatic hiding after the configured reporting threshold.

This system is separate from Rate My Professors. BYE reviews are not imported RMP reviews.

The desktop application continues to use its existing professor-information integration while the original BYE review collection grows.

### Centralized PCC schedule API

BYE has an independently deployed schedule service built with Supabase.

Instead of eventually having every application retrieve and process the same PCC schedule independently, the goal is to share validated schedule data through one versioned API.

The backend includes:

- A structured Fall 2026 schedule database.
- Course, section, and availability endpoints.
- Scheduled and demand-driven synchronization.
- Data freshness and cache controls.
- A shared application-key registry.
- Key creation, rotation, disabling, and revocation.
- A separately hosted owner dashboard.

**Current limitation:** Windows, macOS, and the public website have not yet completed migration to the centralized schedule API.

See [Schedule API documentation](services/schedule-api/README.md).

## Repository structure

| Path | Purpose |
|---|---|
| `Sources/Classwise/` | Native macOS application |
| `Sources/ClasswiseCore/` | Shared Swift models and schedule logic |
| `Sources/BYEAPI/` | Native RMP client |
| `apps/cross-platform/` | Windows Electron application |
| `apps/web/` | Historical migration pointer to website source |
| `services/schedule-api/` | Supabase schedule backend and administration |
| `supabase/` | Review and database SQL records |
| `Tests/` | Swift tests |
| `scripts/` | Build, packaging, and release scripts |
| `benchmarks/` | Performance experiments and evaluations |
| `docs/` | Architecture, decisions, tests, and project history |

The landing page, browser application, and canonical shared React packages are maintained separately in `BYE_website`.

## Development

### macOS

Requires a compatible Mac, Xcode, and the macOS SDK.

From the repository root:

```bash
./scripts/swift.sh build
./scripts/swift.sh test
./scripts/build-test-app.sh
```

The final command builds the local test application. It does not publish a release.

See [Development setup](docs/development.md).

### Windows

Requires Windows x64, Node.js 24 LTS (or Node 22.16+), and npm.

```powershell
cd apps/cross-platform
npm ci
npm run runtime:fetch
npm run dev
```

See the [Windows development guide](apps/cross-platform/README.md) for testing, packaging, and limitations.

### Schedule API

From `services/schedule-api/`:

```bash
npm ci
npm test
npm run test:db
npm run check
```

Deployment and live synchronization are separate operations and should only be performed intentionally.

## Architecture and design

BYE consists of several independently developed components:

**Desktop applications:** The macOS application uses Swift and SwiftUI. The Windows application uses Electron, React, and TypeScript. They share product goals but have separate runtimes.

**Website:** Cloudflare Pages hosts BYE's landing page, sample-data demo, review submission experience, and distribution infrastructure.

**Student review database:** Supabase handles student verification, review records, and database access controls.

**Schedule backend:** A separate Supabase service stores validated PCC schedule data, provides a versioned API, and supports centralized synchronization.

**Administration:** A Cloudflare-hosted owner dashboard manages shared schedule API keys without requiring a local development server.

The schedule backend and student-review system serve different purposes. Their access controls and data flows must remain separate.

## Security and privacy

Security is an ongoing development responsibility, particularly because BYE handles student email addresses and submitted feedback.

Development principles include:

- Never commit API secrets, service-role keys, credentials, or private user data.
- Keep privileged operations on trusted backend services.
- Restrict database operations through appropriate authentication and authorization.
- Maintain separate permissions for student reviews and schedule administration.
- Avoid collecting personal data that the application does not need.
- Test changes affecting authentication, access controls, and data exposure before deployment.
- Do not treat a private GitHub repository as a security boundary.

Existing tests and audits document specific protections; they are not a guarantee that the application is free of vulnerabilities.

## Cross-platform direction (proposal, October 20, 2026)

BYE is evaluating a move from independent Windows Electron/React and macOS SwiftUI frontends toward **one shared React + TypeScript application**. This is a proposal, **not an implemented framework migration**. The existing Windows v3 redesign is the working reference; the macOS app and its update flow remain supported in their current form while alternatives are tested.

The proposed candidate is **Tauri 2 for Windows and macOS**, with **Capacitor considered later for iOS and Android**. Using shared React with Electron on both desktop systems is also an important lower-risk alternative. BYE will compare actual application behavior, startup/resource usage, native integration, accessibility, security, packaging, updates and rollback before selecting a runtime.

The project already shares React screens, domain helpers and tokens from `BYE_website` through a vendored snapshot in Windows. We are also evaluating whether to keep the two repositories with clearer versioned handoffs or eventually put client apps together in a single frontend workspace. **No repository consolidation, app replacement, AI reactivation or public rollout has been approved.** The schedule backend and student review service remain separate, and deployed API services do not mean all clients are integrated.

See the [cross-platform migration proposal and repository options](docs/cross-platform-migration-proposal.md) and the [current UI parity record](docs/UI_PARITY.md).

## Documentation

Start with the [engineering documentation index](docs/README.md).

Important references:

- [Project status](docs/PROJECT_STATUS.md)
- [Architecture](docs/architecture.md)
- [Cross-platform proposal and repository options](docs/cross-platform-migration-proposal.md)
- [Development setup](docs/development.md)
- [Testing](docs/testing.md)
- [Review database](docs/review-database-explained.md)
- [Review launch history](docs/review-launch-record.md)
- [Schedule API](services/schedule-api/docs/README.md)
- [Schedule API delivery record](services/schedule-api/docs/records/2026-10-19-delivery.md)
- [Implementation history](docs/IMPLEMENTATION_HISTORY.md)
- [Mac release procedure](docs/RELEASING.md)

Historical documents preserve decisions and test results from the dates when they were recorded. Newer implementation records take precedence when describing current behavior.

## Development philosophy

BYE is a personal learning project.

It is an opportunity to experiment with software architecture, native applications, APIs, databases, user-interface design, testing, and deployment.

The project uses AI-assisted development alongside testing, documentation, and manual review. As it grows, the goal is to understand how real software systems are designed and maintained without losing the freedom to experiment.

Features, architectures, and tools may change as the project evolves.

## Disclaimer

BYE is independently developed and is not affiliated with or endorsed by Pasadena City College or Rate My Professors.

Course schedules, enrollment availability, professor information, and ratings may change. Students should confirm official enrollment information through PCC.

Rate My Professors uses an unofficial integration that may change or become unavailable. Technical access to third-party information does not imply permission to redistribute it.

Third-party acknowledgments are maintained in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

**BYE — Before You Enroll**

Built by a student, for students.

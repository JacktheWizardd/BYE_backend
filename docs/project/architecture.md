# BYE architecture

This guide describes the checked-in application structure as of October 2026. See [Project Status](PROJECT_STATUS.md) for the latest verified implementation details. Local client integration and independently deployed backend services are described separately; neither implies a new installed-app release.

## Current application boundaries

### Native macOS application (primary Mac track)

- `Package.swift` defines the Swift executable target `Classwise`, the `ClasswiseCore` domain target, the `BYEAPI` library target, and associated tests.
- `Sources/Classwise/` contains the native app, UI/state management, PCC request/section handling, review presentation, and update integration.
- `Sources/ClasswiseCore/` contains reusable Swift domain logic.
- `Sources/BYEAPI/` implements the typed native RMP client. It is a **local Swift module**, not an HTTP service hosted by BYE.
- `Sources/Classwise/Updater.swift` integrates Sparkle for **configured distribution builds**. Debug and local test apps omit the update feed and remain inert.

Typical lookup flow:

~~~text
Student course/term search
        |
        v
Native Swift app + course/schedule logic
        |
        +--> PCC schedule/catalog requests --> course sections + meeting days
        |
        +--> BYEAPI --> RMP professor candidates, profiles, reviews
        |
        v
Identity validation / explicit ambiguity resolution
        |
        v
Sorting, filtering, on-device cache + native UI
~~~

PCC and RMP network requests are direct in the current Mac application. There is no BYE-hosted schedule proxy or Supabase-backed review source in this production flow. Consult [API and integrations](../schedules/api.md) for request boundaries and reliability constraints.

### Separate cross-platform prototype

`apps/cross-platform/` contains the Electron/React/TypeScript implementation. Electron main owns network access and local persistence; the typed preload bridge mediates renderer requests. The renderer is sandboxed and context-isolated. The package targets Windows x64 in its existing documentation. It does **not** share native Mac storage or packaging.

Read [its README](../../apps/cross-platform/README.md) and [verification guide](../../apps/cross-platform/VERIFICATION.md) for exact supported behavior.

Windows main now reads the standalone BYE schedule API and public BYE review endpoints, then independently retrieves RMP information. See [Windows integration](../windows/WINDOWS_API_INTEGRATION.md) for the implementation and recorded verification. Canonical React UI and domain packages belong to the sibling website repository.

## Storage and privacy boundaries

Current application caching and manual profile choices live on the user's device. Native Mac beta storage is under `~/Library/Application Support/BYEAppleAIBeta`; Windows beta storage is separately maintained under `%LOCALAPPDATA%\BYECrossPlatformBeta`. Existing summary caches can persist while AI summary presentation/generation is disabled.

The documented RMP transport avoids persistent credential/cookie storage and follows bounded request/retry rules. Direct connections still disclose ordinary network metadata to the external services; local processing does not make requests anonymous.

Windows source uses the independently deployed schedule backend and public BYE review reads. BYE review text stays in bounded session memory; schedule data has a bounded local cache. Native Mac retains its direct PCC/RMP flow. Existing installed app releases are separate from this local implementation.

## Update and release boundary

The Mac beta uses Sparkle with an EdDSA-verified update feed hosted on the separate BYE website (Cloudflare Pages). The source repository is private, so the feed/ZIP must be accessible to already-installed applications without GitHub authentication. Signing material must never be committed. Follow [Releasing](../releases/RELEASING.md) for build, verification, and publishing steps.

## Backend and future product boundaries

The standalone schedule service lives in `services/schedule-api/`; its [canonical documentation](../../services/schedule-api/docs/README.md) covers storage and synchronization. The website owns student review routes and writing. BYE reviews remain separate from RMP evidence.

Educational plans and transfer evaluation remain future goals. AI summaries remain disabled; see the [roadmap](roadmap.md). Keep credentials, permissions, deployment paths and release gates distinct.

# BYE architecture

This guide describes the checked-in application structure as of October 2026. See [Project Status](PROJECT_STATUS.md) for the latest verified implementation details. Planned services are described separately below; they are **not currently production components**.

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

PCC and RMP network requests are direct in the current Mac application. There is no BYE-hosted schedule proxy or Supabase-backed review source in this production flow. Consult [API and integrations](api.md) for request boundaries and reliability constraints.

### Separate cross-platform prototype

`apps/cross-platform/` contains the Electron/React/TypeScript implementation. Electron main owns network access and local persistence; the typed preload bridge mediates renderer requests. The renderer is sandboxed and context-isolated. The package targets Windows x64 in its existing documentation. It does **not** share native Mac storage or packaging.

Read [its README](../apps/cross-platform/README.md) and [verification guide](../apps/cross-platform/VERIFICATION.md) for exact supported behavior.

## Storage and privacy boundaries

Current application caching and manual profile choices live on the user's device. Native Mac beta storage is under `~/Library/Application Support/BYEAppleAIBeta`; Windows beta storage is separately maintained under `%LOCALAPPDATA%\BYECrossPlatformBeta`. Existing summary caches can persist while AI summary presentation/generation is disabled.

The documented RMP transport avoids persistent credential/cookie storage and follows bounded request/retry rules. Direct connections still disclose ordinary network metadata to the external services; local processing does not make requests anonymous.

No student review database or hosted school schedule cache is part of the currently checked-in app flow. Do not treat prototypes, experimental scripts, or future plans as deployed infrastructure.

## Update and release boundary

The Mac beta uses Sparkle with an EdDSA-verified update feed hosted on the separate BYE website (Cloudflare Pages). The source repository is private, so the feed/ZIP must be accessible to already-installed applications without GitHub authentication. Signing material must never be committed. Follow [Releasing](RELEASING.md) for build, verification, and publishing steps.

## Proposed future services — not implemented

1. **Student-submitted review service:** A BYE-owned review/rating dataset, designed independently of RMP data; see [Database plans](database.md).
2. **PCC schedule API and cache:** A server-side refresh/cache layer intended to reduce repeated upstream requests and improve client response time, subject to PCC's permitted access patterns; see [API and integrations](api.md).
3. **Education-plan and transfer evaluation:** Upload/parse plans, check official articulation/transfer sources, and display missing or strongly recommended requirements. This is a product roadmap direction, not a supported current feature.

Keep data models, credentials, permissions, deployment paths, and release gates distinct until a design has been reviewed and implemented.

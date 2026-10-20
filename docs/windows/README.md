# Windows app

## What we built and why

The separate Electron/React/TypeScript app reads schedules through BYE's API. Main-process networking keeps credentials and source requests outside the renderer. A typed Bridge preserves UI isolation and lets canonical website-owned components serve both web and Windows.

BYE reviews start first and RMP loads automatically through its existing bounded pipeline. Their ratings, text, loading states and errors stay independent so neither source is presented as the other. Semester/course state, refresh recovery and freshness handling preserve a student's current comparison.

## How it works

- [App setup and commands](../../apps/cross-platform/README.md)
- [Integration decisions, behavior and recorded verification](WINDOWS_API_INTEGRATION.md)
- [UI parity](UI_PARITY.md)
- [App verification guide](../../apps/cross-platform/VERIFICATION.md)
- [Canonical shared UI documentation in the sibling website repo](../../../BYE_website/docs/shared-ui/README.md)

Desktop owns Electron main/preload/renderer integration. Website owns shared React source; changes are synced using the existing vendoring script.

## What remains

Implementation and local builds are separate from a distributed Windows release. A BYE/RMP source toggle is a follow-up UI request, not part of this documentation change. Backend freshness must be checked independently of UI polling. AI summaries remain disabled.

[All documents](../README.md)

# PCC schedules and API

## What we built and why

The standalone schedule service normalizes PCC's published schedule into a shared stored dataset. A background worker collects upstream data so individual searches do not each fetch PCC. Catalog and availability versions are separate; stale enrollment counts are hidden rather than presented as current registration facts.

## How it works

| Guide | Purpose |
| --- | --- |
| [Integration overview](api.md) | Mac, Windows, review and release-service boundaries |
| [Original PCC pilot](pcc-schedule-pilot.md) | Import history and original evidence |
| [Canonical service documentation](../../services/schedule-api/docs/README.md) | Backend architecture, keys, operations and delivery records |
| [Synchronization and operations](../../services/schedule-api/docs/guide.md) | Daily baseline, demand-driven checks, budgets and rollback |
| [Windows integration](../windows/WINDOWS_API_INTEGRATION.md) | Client polling, caching and failure behavior |

Desktop owns `services/schedule-api/`; its technical guides stay beside that service. The supported imported term is Fall 2026. Native Mac and website schedule integrations have separate source paths and rollout requirements.

## What remains

Additional terms and client integrations require their own work. A configured scheduler is not evidence of a recent successful source check. The October 20 read-only API probe returned stale availability with `sourceCheckedAt` October 19, 2026 at 10:00 UTC; diagnosing that is a separate operations task. No backend state was changed for this documentation reorganization.

[All documents](../README.md)

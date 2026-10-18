# Schedule API documentation

This folder is the documentation home for the independently deployed BYE
schedule API. The backend is implemented; client integration is not yet done.

Read in this order:

1. [Architecture](architecture.md) — what runs where and how data moves.
2. [Setup and operations](guide.md) — use, test, deploy, inspect, pause and roll back.
3. [API keys](api-keys.md) — configure the existing public key and understand the limits.
4. [Verification](verification.md) — evidence from implementation and hosted checks.
5. [Roadmap](roadmap.md) — agreed boundaries and future work.
6. [Commit guide](commit-guide.md) — review the pending changes before committing.

The [OpenAPI specification](../openapi.json) stays at the package root so tooling
and contract tests can use its stable path. Its source is
[src/contract.ts](../src/contract.ts). Code, migrations and tests remain beside the
docs in the standalone package; no client implementation is imported.

## Current snapshot

| Item | Implemented state |
| --- | --- |
| Database | Existing BYE Supabase project; schedule data separate from reviews |
| Semester | Fall 2026 only, `202670` |
| Public reads | Six v1 endpoints, publishable key, no student login |
| Source refresh | Daily metadata/catalog check; shared availability checks during demand |
| Active collection | Five-minute minimum, normally five to six minutes with timer timing |
| Stale values | Availability suppressed after fifteen minutes without a successful check |
| Client keys | One configured key; replacement requires backend redeployment |
| Clients | Existing Windows, Mac and website behavior unchanged |
| Verification | 11 unit/contract/transport tests, 15 database scenarios, 8 hosted scenarios recorded |

This table describes the delivered implementation, not a fresh production health
check. The verification report records dated measurements; live data can change.

## Related project documents

- [PCC database pilot](../../../docs/pcc-schedule-pilot.md): source preservation,
  original import workflow and first snapshot verification.
- [Repository documentation index](../../../docs/README.md): application,
  database and release guides.
- [Windows verification](../../../apps/cross-platform/VERIFICATION.md): earlier
  suggestions and profile-dialog fixes, separate from this backend phase.

Update the operations guide when behavior changes, the verification report when
checks are actually run, and the roadmap when queued work becomes implemented.
Do not describe a future key manager or client integration as already shipped.

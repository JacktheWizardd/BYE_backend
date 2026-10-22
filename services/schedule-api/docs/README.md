# Schedule API documentation

**October 20 client follow-up:** Windows source integration is implemented locally, with BYE student reviews first and automatic, separate RMP retrieval. See [Windows integration and verification](../../../docs/windows/WINDOWS_API_INTEGRATION.md). No backend migration/deployment or client release is part of this follow-up. The October 19 acceptance below remains the backend delivery record.

Start with the plain-language records. They explain the result and the reasons
behind it; the technical guides below explain how to operate or change it.

| Document | What it answers |
| --- | --- |
| [Delivery record](records/2026-10-19-delivery.md) | What did we build, why, and what was verified? |
| [Owner and developer handoff](records/handoff.md) | How do I use it or take over the next task? |
| [Record index](records/README.md) | How should future milestones be documented? |
| [Architecture](architecture.md) | What runs where, and which component owns each responsibility? |
| [API operations](guide.md) | How do endpoints, synchronization, deployment and rollback work? |
| [Key guide](api-keys.md) | What do the different keys mean, and how does their lifecycle work? |
| [Hosted dashboard](hosted-owner-dashboard.md) | How is the Cloudflare admin site deployed and protected? |
| [Owner access and local development](owner-dashboard.md) | How do bootstrap, recovery, the management API and localhost work? |
| [Verification](verification.md) | What evidence and limitations were recorded? |
| [Roadmap](roadmap.md) | What is delivered and what remains separate work? |
| [Commit handoff](commit-guide.md) | What belongs in the pending commit, and what text can I paste? |
| [OpenAPI contract](../openapi.json) | What is the precise machine-readable v1 interface? |

## Accepted state — October 19, 2026

The schedule API and owner key manager are deployed. The owner dashboard is at
**https://bye-admin.jack-truong2k1.workers.dev** on Cloudflare Free. Owner sign-in,
key operations and operation without the localhost server were verified.

| Area | Delivered behavior |
| --- | --- |
| Schedule coverage | Fall 2026 only (`202670`), in the existing Supabase project |
| Read API | Six v1 endpoints; registered BYE key; no student login for browsing |
| PCC synchronization | Daily check and shared activity-driven collection, with a five-minute minimum between semester fetches |
| Freshness | Stale availability is suppressed after fifteen minutes without a successful source check |
| Key management | Shared application keys; registry changes require no API redeployment |
| Admin hosting | Separate Cloudflare site; owner-only management; optional local development server |
| Client integration | Pending for Windows, Mac and the public website |
| Replacement delivery | Pending for installed clients; rotation does not deliver new configuration |

Recorded verification includes 21 offline tests, a full Cloudflare runtime test,
22 database scenarios from key-management work, and eight hosted schedule checks.
The verification report distinguishes phases and limitations. This documentation
update does not claim those tests or live checks were rerun.

The [PCC database pilot](../../../docs/schedules/pcc-schedule-pilot.md) explains the original
import foundation. The [repository documentation index](../../../docs/README.md)
links to app development and review-system work. Public website source and its
own guides are in the separate `BYE_website` repository.

Maintain this index and the handoff when accepted behavior changes. Add dated
records for milestones, preserve historical evidence, and keep future work clearly
separate from delivered features.

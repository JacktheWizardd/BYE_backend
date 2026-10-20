# BYE documents

Start with an area below. Each overview explains **what we built, why we chose it, how it works, and what remains**. These are private engineering documents, not release announcements.

| Area | What you will find |
| --- | --- |
| [Project](project/README.md) | Current status, architecture, setup, testing, history and product roadmap |
| [Windows app](windows/README.md) | Electron integration, BYE/RMP review behavior and UI parity |
| [Student reviews](reviews/README.md) | BYE database, identity, privacy, submission and launch history |
| [PCC schedules and API](schedules/README.md) | PCC import, integration boundaries and canonical backend guides |
| [Design](design/README.md) | App mockup, design history and shared design ownership |
| [Releases](releases/README.md) | Mac installation, packaging, updates and prepared notes |
| [AI experiments](experiments/README.md) | Preserved summary research; AI summaries remain disabled |
| [Verification records](verification/README.md) | Dated test evidence and its limitations |

For current implementation, start with [Project status](project/PROJECT_STATUS.md). For future capabilities, see the [roadmap](project/roadmap.md). Dated evidence describes the version tested at that time; implementation, deployment and release are separate milestones.

The [sibling website documentation](../../BYE_website/docs/README.md) owns the landing page, browser app, shared React packages and public review routes. Service-specific docs remain [beside the schedule API](../services/schedule-api/docs/README.md); app and package READMEs remain beside their code.

When an area changes, update its overview and link the detailed decision or verification record. Keep one canonical guide for each responsibility; link across repositories rather than copying it.

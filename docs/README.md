# BYE documents

This repository owns backend contracts and the standalone schedule service;
`BYE_website` owns the shared frontend and Tauri preview. Website API and source
Worker implementations remain there during the transition. Start with the
[current repository map](REPOSITORY_MAP.md) and [contract workspace](../packages/api-contracts/README.md).
Backend deployment does not imply that legacy clients have been connected.

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

## Shared application architecture

- [Agreed migration and acceptance gates](cross-platform-migration-proposal.md) — React/TypeScript, Tauri desktop candidate, later Capacitor, frontend/backend ownership and gated cutover. Electron is legacy only.
- [Existing UI parity](windows/UI_PARITY.md) — legacy platform differences to validate before replacement.

## Application development

The [sibling website documentation](../../BYE_website/docs/README.md) owns the landing page, browser app, shared React packages and public review routes. Service-specific docs remain [beside the schedule API](../services/schedule-api/docs/README.md); app and package READMEs remain beside their code.

When an area changes, update its overview and link the detailed decision or verification record. Keep one canonical guide for each responsibility; link across repositories rather than copying it.

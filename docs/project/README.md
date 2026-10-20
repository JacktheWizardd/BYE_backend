# Project

## What we built and why

BYE helps PCC students compare course sections and independently sourced professor information. The native Mac app and separate Windows app have different runtimes and release processes; documenting them separately prevents a backend deployment from being mistaken for an installed-app update.

## How it works

| Guide | Purpose |
| --- | --- |
| [Project status](PROJECT_STATUS.md) | Recorded implementation, verification and blockers |
| [Architecture](architecture.md) | Ownership, data flow, storage and service boundaries |
| [Development](development.md) | Platform setup, commands and configuration hygiene |
| [Testing](testing.md) | Appropriate checks and offline/live evidence boundaries |
| [Implementation history](IMPLEMENTATION_HISTORY.md) | Earlier decisions and work records |
| [Roadmap](roadmap.md) | Implemented behavior versus future product goals |

Desktop owns native Swift code, Windows Electron code and the standalone schedule service. The [website repository](../../../BYE_website/docs/README.md) owns browser source and canonical shared React packages.

## What remains

Windows API integration is implemented locally; that does not replace installed releases. Native Mac service integration, transfer evaluation and educational plans remain separate work. AI summaries remain disabled. Check dated evidence before making deployment or release claims.

[All documents](../README.md)

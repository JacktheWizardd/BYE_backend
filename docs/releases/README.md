# Releases

## What we built and why

Mac distribution uses signed packages and a Sparkle update feed. Packaging and publishing remain separate from local development so a passing build does not silently replace installed releases.

## How it works

- [Release procedure](RELEASING.md)
- [Installation text used by packaging](BETA_INSTALLATION.txt)
- [Prepared prerelease notes used by packaging](GITHUB_PRERELEASE.md)
- [Windows app build and packaging guide](../../apps/cross-platform/README.md)

Desktop scripts own release generation. Only `scripts/publish-to-website.py` writes website release files under `public/updates/` and `public/downloads/`. Preserve the installed-app update domain, `/updates/appcast.xml` and `/download`.

## What remains

Each commit, push, deployment and release needs authorization covering that action. Windows integration is locally implemented; this documentation work creates no package, installed-client update or release. Mac packaging cannot be exercised on this Windows machine.

[All documents](../README.md)

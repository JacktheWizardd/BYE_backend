#!/usr/bin/env node
// Copies the shared BYE packages from the website repository into the Windows app:
//   ../BYE_website/packages/{tokens,core,ui}  ->  apps/cross-platform/vendor/bye-shared/
//   ../BYE_website/public/fonts (Schibsted Grotesk, JetBrains Mono woff2) -> vendor/bye-shared/fonts/
// and the Mac app's tokens:
//   ../BYE_website/packages/tokens/generated/BYETokens.swift  ->  Sources/Classwise/Views/BYETokens.swift
// and records the website commit in vendor/bye-shared/SOURCE.json. The website is the source of truth for these
// files: edit them there, commit, then run `node scripts/sync-bye-shared.mjs` here. Never edit vendor/ by hand.
// Usage: node scripts/sync-bye-shared.mjs [path-to-website] [--allow-dirty]
import { cp, mkdir, rm, writeFile, readdir } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const website = path.resolve(process.argv.slice(2).find(a => !a.startsWith('--')) ?? path.join(repo, '..', 'BYE_website'))
const target = path.join(repo, 'apps', 'cross-platform', 'vendor', 'bye-shared')
const packages = ['tokens', 'core', 'ui']
const fonts = ['schibsted-grotesk-latin-400-normal.woff2', 'schibsted-grotesk-latin-600-normal.woff2', 'schibsted-grotesk-latin-700-normal.woff2', 'jetbrains-mono-latin-500-normal.woff2']

const git = (...args) => execFileSync('git', ['-C', website, ...args], { encoding: 'utf8' }).trim()
const commit = git('rev-parse', 'HEAD'), branch = git('rev-parse', '--abbrev-ref', 'HEAD')
const dirty = git('status', '--porcelain', '--', ...packages.map(p => `packages/${p}`), ...fonts.map(f => `public/fonts/${f}`))
if (dirty && !process.argv.includes('--allow-dirty')) {
  console.error(`The website has uncommitted changes in shared files:\n${dirty}\nCommit them first (so SOURCE.json names a real commit), or pass --allow-dirty for a local trial.`)
  process.exit(1)
}

await rm(target, { recursive: true, force: true })
for (const name of packages) await cp(path.join(website, 'packages', name), path.join(target, name), { recursive: true })
await mkdir(path.join(target, 'fonts'), { recursive: true })
for (const font of fonts) await cp(path.join(website, 'public', 'fonts', font), path.join(target, 'fonts', font))
// The Mac app compiles its own copy; TokenDriftTests checks it against the vendored one.
await cp(path.join(target, 'tokens', 'generated', 'BYETokens.swift'), path.join(repo, 'Sources', 'Classwise', 'Views', 'BYETokens.swift'))
await writeFile(path.join(target, 'SOURCE.json'), JSON.stringify({
  about: 'Copied from the BYE website repository by scripts/sync-bye-shared.mjs. Do not edit; change the website and sync again.',
  repository: 'JacktheWizardd/BYE_website', branch, commit, uncommittedChanges: Boolean(dirty), packages, fonts,
}, null, 2) + '\n')
const count = async dir => (await readdir(dir, { recursive: true, withFileTypes: true })).filter(e => e.isFile()).length
console.log(`Synced ${await count(target)} files from BYE_website ${branch}@${commit.slice(0, 7)}${dirty ? ' (with uncommitted changes)' : ''} into apps/cross-platform/vendor/bye-shared and Sources/Classwise/Views/BYETokens.swift.`)

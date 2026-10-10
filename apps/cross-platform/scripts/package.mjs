import { build, Platform, Arch } from 'electron-builder'
import { createReadStream } from 'node:fs'
import { readFile, mkdir, writeFile, rename, readdir, stat, cp, unlink, mkdtemp, rm } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import { createRequire } from 'node:module'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { extractAll } from '@electron/asar'
import { scan } from './privacy.mjs'
const require = createRequire(import.meta.url), { path7za } = require('7zip-bin')
const root = path.resolve(import.meta.dirname, '..'), repo = path.resolve(root, '../..'), dist = path.join(repo, 'dist')
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8')), manifest = JSON.parse(await readFile(path.join(root, 'models/manifest.json'), 'utf8'))
async function digest(file) { const hash = createHash('sha256'); for await (const chunk of createReadStream(file)) hash.update(chunk); return hash.digest('hex') }
export function run(file, args, cwd = root) { return new Promise((resolve, reject) => { const child = spawn(file, args, { cwd, stdio: 'inherit', windowsHide: true }); child.on('error', reject); child.on('exit', code => code === 0 ? resolve() : reject(new Error(`${path.basename(file)} failed (${code})`))) }) }
if (process.platform !== 'win32' || process.arch !== 'x64') throw new Error('Build the first release on Windows x64.')
const model = path.join(root, 'models', manifest.filename)
if ((await stat(model)).size !== manifest.bytes || await digest(model) !== manifest.sha256) throw new Error('Bundled model is missing or corrupt. Run npm run model:fetch.')
await mkdir(dist, { recursive: true })
const reuse = process.argv.indexOf('--reuse-stage')
const stage = reuse >= 0 ? path.resolve(process.argv[reuse + 1] ?? '') : await mkdtemp(path.join(dist, 'cross-platform-build-'))
if (!stage.startsWith(dist + path.sep)) throw new Error('Staging directory must be inside dist.')
const notices = [await readFile(path.join(repo, 'THIRD_PARTY_NOTICES.md'), 'utf8')]
notices[0] = notices[0].replace('No third-party model or OHTTP implementation is bundled in this milestone.', 'This separate cross-platform beta includes Qwen3-4B (Apache-2.0) and node-llama-cpp (MIT); model and dependency licenses are bundled.')
async function licenses(folder) {
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name === '.bin') continue
    const directory = path.join(folder, entry.name)
    if (entry.name.startsWith('@')) { await licenses(directory); continue }
    try {
      const info = JSON.parse(await readFile(path.join(directory, 'package.json'), 'utf8'))
      const names = (await readdir(directory)).filter(n => /^(license|licence|copying|notice)(\.|$|-)/i.test(n))
      notices.push(`\n---\n${info.name} ${info.version}\nLicense: ${typeof info.license === 'string' ? info.license : JSON.stringify(info.license) ?? 'See upstream package'}\n`)
      for (const name of names) if ((await stat(path.join(directory, name))).isFile()) notices.push(await readFile(path.join(directory, name), 'utf8'))
      try { await licenses(path.join(directory, 'node_modules')) } catch (e) { if (e.code !== 'ENOENT') throw e }
    } catch (e) { if (e.code !== 'ENOENT') throw e }
  }
}
await licenses(path.join(root, 'node_modules'))
await writeFile(path.join(stage, 'THIRD_PARTY_NOTICES.txt'), notices.join('\n'))
await writeFile(path.join(stage, 'START_HERE.txt'), `BYE Cross-platform beta ${pkg.version}\n\nExtract this entire ZIP to a folder, then double-click BYE.exe. Keep all supporting files together.\nWindows 11 x64 (Intel/AMD). 16 GB RAM recommended for CPU-only AI; no dedicated GPU required.\nThe approximately 2.5 GB AI model is included. No Ollama, model download, installer, or administrator setup is required.\nPCC and RMP retrieval need internet. AI generation stays local and works with cached reviews offline.\nPreferences and caches: %LOCALAPPDATA%\\BYECrossPlatformBeta. App-folder replacement preserves them.\nThis unsigned beta may show Windows security prompts. No automatic updates are included.\nAI is experimental; verify claims against original reviews.\nSee VERIFICATION.md for measured results and remaining checks.\n`)
await cp(path.join(root, 'VERIFICATION.md'), path.join(stage, 'VERIFICATION.md'))
if (reuse < 0) await build({ projectDir: root, targets: Platform.WINDOWS.createTarget('dir', Arch.x64), config: {
  appId: 'org.bye.crossplatform.beta', productName: 'BYE', electronVersion: pkg.devDependencies.electron, electronDist: path.join(root, 'node_modules/electron/dist'),
  directories: { output: stage }, npmRebuild: false, asar: true,
  files: ['out/**', 'package.json', '!**/*.map', '!**/*.ts', '!**/*.lib', '!node_modules/@node-llama-cpp/win-arm64/**', '!node_modules/@node-llama-cpp/*cuda*/**', '!node_modules/@node-llama-cpp/*vulkan*/**', ...['addon', 'cmake', 'patches', 'profiles', 'toolchains', 'xpack'].map(name => `!node_modules/node-llama-cpp/llama/${name}/**`), '!node_modules/node-llama-cpp/llama/gitRelease.bundle', '!node_modules/node-llama-cpp/templates/**'],
  asarUnpack: ['node_modules/@node-llama-cpp/**/*', '**/*.node', '**/*.dll'],
  extraResources: [{ from: path.join(root, 'models'), to: 'models', filter: ['manifest.json', manifest.filename, 'LICENSE-QWEN.txt'] }],
  extraFiles: ['START_HERE.txt', 'THIRD_PARTY_NOTICES.txt', 'VERIFICATION.md'].map(name => ({ from: path.join(stage, name), to: name })),
  win: { executableName: 'BYE', signAndEditExecutable: false, target: [{ target: 'dir', arch: ['x64'] }] }
} })
const app = path.join(stage, 'BYE')
if (reuse < 0) await rename(path.join(stage, 'win-unpacked'), app)
else for (const name of ['START_HERE.txt', 'THIRD_PARTY_NOTICES.txt', 'VERIFICATION.md']) await cp(path.join(stage, name), path.join(app, name))
if (await digest(path.join(app, 'resources/models', manifest.filename)) !== manifest.sha256) throw new Error('Staged model checksum mismatch.')
await scan(app)
const inspection = await mkdtemp(path.join(dist, 'asar-inspection-'))
try {
  extractAll(path.join(app, 'resources/app.asar'), inspection)
  for (const name of ['binariesGithubRelease.json', 'llama.cpp.info.json']) {
    const metadata = JSON.parse(await readFile(path.join(inspection, 'node_modules/node-llama-cpp/llama', name), 'utf8'))
    if (!metadata || typeof metadata !== 'object') throw new Error(`Missing AI runtime metadata: ${name}`)
  }
  await scan(inspection)
}
finally { if (!path.resolve(inspection).startsWith(path.resolve(dist) + path.sep)) throw new Error('Unsafe inspection directory.'); await rm(inspection, { recursive: true, force: true }) }
const zip = path.join(dist, `BYE-CrossPlatform-${pkg.version}-windows-x64.zip`)
await mkdir(path.join(root, 'test-results'), { recursive: true })
await writeFile(path.join(root, 'test-results/staged.json'), JSON.stringify({ appDirectory: path.relative(repo, app) }, null, 2))
if (process.argv.includes('--stage-only')) { console.log(`Staged ${app}`); process.exit(0) }
try { await unlink(zip) } catch (e) { if (e.code !== 'ENOENT') throw e }
await run(path7za, ['a', '-tzip', '-mx=5', zip, 'BYE'], stage)
await run(path7za, ['t', zip])
await writeFile(zip + '.sha256', `${await digest(zip)}  ${path.basename(zip)}\n`)
await writeFile(path.join(root, 'test-results/package.json'), JSON.stringify({ date: new Date().toISOString(), zip: path.basename(zip), bytes: (await stat(zip)).size, sha256: await digest(zip), appDirectory: path.relative(repo, app), unsigned: true, privacy: 'app directory and unpacked ASAR passed', model: manifest }, null, 2))
console.log(`Created ${zip}`)

import { readFile, stat, mkdir, mkdtemp, writeFile } from 'node:fs/promises'
import { createReadStream } from 'node:fs'
import { createHash } from 'node:crypto'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url), { path7za } = require('7zip-bin')
const root = path.resolve(import.meta.dirname, '..'), repo = path.resolve(root, '../..'), dist = path.join(repo, 'dist')
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8')), zip = path.join(dist, `BYE-CrossPlatform-${pkg.version}-windows-x64.zip`)
const hash = createHash('sha256'); for await (const chunk of createReadStream(zip)) hash.update(chunk)
const actual = hash.digest('hex'), expected = (await readFile(zip + '.sha256', 'utf8')).split(/\s/)[0]
if (actual !== expected) throw new Error('ZIP checksum mismatch.')
const folder = await mkdtemp(path.join(dist, 'Extracted BYE 测试 '))
await new Promise((resolve, reject) => { const child = spawn(path7za, ['x', zip, '-o' + folder, '-y'], { stdio: 'inherit', windowsHide: true }); child.on('error', reject); child.on('exit', code => code === 0 ? resolve() : reject(new Error('ZIP extraction failed'))) })
const app = path.join(folder, 'BYE'), manifest = JSON.parse(await readFile(path.join(app, 'resources/models/manifest.json'), 'utf8'))
if ((await stat(path.join(app, 'resources/models', manifest.filename))).size !== manifest.bytes) throw new Error('Model is incomplete in extracted ZIP.')
const modelHash = createHash('sha256')
for await (const chunk of createReadStream(path.join(app, 'resources/models', manifest.filename))) modelHash.update(chunk)
if (modelHash.digest('hex') !== manifest.sha256) throw new Error('Extracted model checksum mismatch.')
await mkdir(path.join(root, 'test-results'), { recursive: true })
await writeFile(path.join(root, 'test-results/extracted.json'), JSON.stringify({ appDirectory: path.relative(repo, app), checksum: actual, executableExists: (await stat(path.join(app, 'BYE.exe'))).size > 0, pathContainsSpacesAndUnicode: true }, null, 2))
console.log(`Verified extraction: ${app}`)

import { readFile, stat, mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { createRequire } from 'node:module'
import { extractAll } from '@electron/asar'
import { digest, verifyPackage } from './package-policy.mjs'
import { scan } from './privacy.mjs'
const require = createRequire(import.meta.url), { path7za } = require('7zip-bin')
const root = path.resolve(import.meta.dirname, '..'), repo = path.resolve(root, '../..'), dist = path.join(repo, 'dist')
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'))
const zip = process.argv[2] ? path.resolve(process.argv[2]) : path.join(dist, `BYE-CrossPlatform-${pkg.version}-windows-x64.zip`)
const actual = await digest(zip), expected = (await readFile(zip + '.sha256', 'utf8')).split(/\s/)[0]
if (actual !== expected) throw new Error('ZIP checksum mismatch.')
const folder = await mkdtemp(path.join(dist, 'Extracted BYE 测试 '))
await new Promise((resolve, reject) => { const child = spawn(path7za, ['x', zip, '-o' + folder, '-y'], { stdio: 'inherit', windowsHide: true }); child.on('error', reject); child.on('exit', code => code === 0 ? resolve() : reject(new Error('ZIP extraction failed'))) })
const app = path.join(folder, 'BYE'), info = await verifyPackage(app)
await scan(app)
const inspection = await mkdtemp(path.join(dist, 'asar-inspection-'))
try { extractAll(path.join(app, 'resources/app.asar'), inspection); await scan(inspection) }
finally { if (!path.resolve(inspection).startsWith(dist + path.sep)) throw new Error('Unsafe inspection directory.'); await rm(inspection, { recursive: true, force: true }) }
await mkdir(path.join(root, 'test-results'), { recursive: true })
await writeFile(path.join(root, 'test-results/extracted.json'), JSON.stringify({ appDirectory: path.relative(repo, app), checksum: actual, buildInfo: info, executableExists: (await stat(path.join(app, 'BYE.exe'))).size > 0, pathContainsSpacesAndUnicode: true, privacy: 'extracted files and unpacked ASAR passed', structure: 'passed' }, null, 2))
console.log(`Verified extraction: ${app}`)

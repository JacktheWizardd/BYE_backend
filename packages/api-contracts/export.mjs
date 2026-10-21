import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const root = path.dirname(fileURLToPath(import.meta.url))
const check = process.argv.includes('--check')
const destination = process.argv.slice(2).find(x => !x.startsWith('--'))
if (!destination) throw new Error('Pass the explicit frontend contracts directory. Add --check for a read-only verification.')
const target = path.resolve(destination)
if (target === root || target.startsWith(root + path.sep)) throw new Error('Export destination must be outside the contract source package.')
const files = ['api.ts', 'types.ts', 'reviews.ts', 'schedule.openapi.json']
const hashes = {}
const outputs = new Map()
for (const file of files) {
  const bytes = await readFile(path.join(root, 'src', file))
  hashes[file] = createHash('sha256').update(bytes).digest('hex')
  outputs.set('src/' + file, bytes)
}
const packageInfo = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'))
delete packageInfo.scripts
outputs.set('package.json', Buffer.from(JSON.stringify(packageInfo, null, 2) + '\n'))
const manifest = { repository: 'JacktheWizardd/BYE_Before_You_Enroll', package: '@bye/contracts', version: '1.0.0-preview.1', files: hashes }
outputs.set('SOURCE.json', Buffer.from(JSON.stringify(manifest, null, 2) + '\n'))
for (const [file, expected] of outputs) {
  const out = path.join(target, file)
  if (check) {
    if (!(await readFile(out)).equals(expected)) throw new Error('Contract snapshot differs: ' + file)
  } else { await mkdir(path.dirname(out), { recursive: true }); await writeFile(out, expected) }
}
console.log(`${check ? 'Verified' : 'Exported'} @bye/contracts 1.0.0-preview.1; ${files.length} source hashes match.`)

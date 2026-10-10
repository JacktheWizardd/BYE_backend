import { readFile, mkdir, rename, stat, writeFile } from 'node:fs/promises'
import { createReadStream, createWriteStream } from 'node:fs'
import { createHash } from 'node:crypto'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import path from 'node:path'
const root = path.resolve(import.meta.dirname, '..'), directory = path.join(root, 'models')
const manifest = JSON.parse(await readFile(path.join(directory, 'manifest.json'), 'utf8'))
export async function digest(file) {
  const hash = createHash('sha256'); for await (const chunk of createReadStream(file)) hash.update(chunk); return hash.digest('hex')
}
await mkdir(directory, { recursive: true })
const file = path.join(directory, manifest.filename)
if (await stat(file).then(s => s.size === manifest.bytes).catch(() => false) && await digest(file) === manifest.sha256) console.log('Pinned model already verified.')
else {
  const response = await fetch(`https://huggingface.co/${manifest.repository}/resolve/${manifest.revision}/${manifest.filename}`, { signal: AbortSignal.timeout(1800000) })
  if (!response.ok || !response.body) throw new Error(`Model download failed: HTTP ${response.status}`)
  let bytes = 0, last = Date.now()
  const meter = new TransformStream({ transform(chunk, controller) { bytes += chunk.length; if (Date.now() - last > 15000) { console.log(`Model: ${(bytes / 1e6).toFixed(0)} / ${(manifest.bytes / 1e6).toFixed(0)} MB`); last = Date.now() } controller.enqueue(chunk) } })
  await pipeline(Readable.fromWeb(response.body.pipeThrough(meter)), createWriteStream(file + '.part'))
  if ((await stat(file + '.part')).size !== manifest.bytes || await digest(file + '.part') !== manifest.sha256) throw new Error('Downloaded model failed pinned integrity check.')
  await rename(file + '.part', file); console.log('Pinned model downloaded and verified.')
}
const license = await fetch(`https://huggingface.co/${manifest.repository}/raw/${manifest.revision}/LICENSE`)
if (!license.ok) throw new Error('Could not download model license.')
await writeFile(path.join(directory, 'LICENSE-QWEN.txt'), await license.text())

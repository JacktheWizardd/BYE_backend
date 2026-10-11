import { createReadStream } from 'node:fs'
import { readFile, readdir, stat, access } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import path from 'node:path'
import { extractFile, listPackage } from '@electron/asar'

export function buildInfo(version, policy) {
  if (typeof policy.aiSummariesEnabled !== 'boolean' || typeof version !== 'string' || !version) throw new Error('Invalid build policy.')
  return { schemaVersion: 1, version, aiSummariesEnabled: policy.aiSummariesEnabled, weightsBundled: policy.aiSummariesEnabled }
}
export function validateInfo(info) {
  if (!info || info.schemaVersion !== 1 || typeof info.version !== 'string' || !info.version || typeof info.aiSummariesEnabled !== 'boolean' || info.weightsBundled !== info.aiSummariesEnabled) throw new Error('Invalid package build metadata.')
  return info
}
export function assertPolicy(actual, expected) {
  validateInfo(actual); validateInfo(expected)
  for (const key of ['schemaVersion', 'version', 'aiSummariesEnabled', 'weightsBundled']) if (actual[key] !== expected[key]) throw new Error(`Staging/build policy mismatch: ${key}. Build a fresh staging directory.`)
}
export async function digest(file) { const hash = createHash('sha256'); for await (const chunk of createReadStream(file)) hash.update(chunk); return hash.digest('hex') }
export async function refuseOverwrite(file) {
  try { await access(file) } catch (error) { if (error.code === 'ENOENT') return; throw error }
  throw new Error(`Refusing to overwrite existing artifact: ${path.basename(file)}`)
}
export async function verifyWeights(directory, manifest, info) {
  validateInfo(info)
  const weights = []
  async function walk(folder) {
    for (const item of await readdir(folder, { withFileTypes: true })) {
      const file = path.join(folder, item.name)
      if (item.isDirectory()) await walk(file)
      else if (/\.gguf$/i.test(item.name)) weights.push(file)
    }
  }
  await walk(directory)
  if (!info.weightsBundled) { if (weights.length) throw new Error('Disabled package contains GGUF weights.'); return }
  const model = path.join(directory, 'resources/models', manifest.filename)
  if (weights.length !== 1 || weights[0] !== model || (await stat(model)).size !== manifest.bytes || await digest(model) !== manifest.sha256) throw new Error('Bundled model is missing or corrupt.')
}
export async function verifyPackage(directory, expected) {
  const info = validateInfo(JSON.parse(await readFile(path.join(directory, 'resources/build-info.json'), 'utf8')))
  if (expected) assertPolicy(info, expected)
  const archive = path.join(directory, 'resources/app.asar')
  const archivedFile = file => extractFile(archive, file.split('/').join(path.sep))
  const archived = JSON.parse(archivedFile('out/main/build-info.json').toString())
  assertPolicy(archived, info)
  if (JSON.parse(archivedFile('package.json').toString()).version !== info.version) throw new Error('Package version mismatch.')
  const files = listPackage(archive)
  if (files.some(file => /\.gguf$|^[\\/]?(?:scripts|test-results|\.cache)[\\/]|offline-entry/i.test(file))) throw new Error('Unexpected weights or verification files inside ASAR.')
  for (const file of ['out/main/index.js', 'out/main/bootstrap.js', 'out/preload/index.cjs', 'out/renderer/index.html']) if (!archivedFile(file).length) throw new Error(`Missing application file: ${file}`)
  for (const name of ['binariesGithubRelease.json', 'llama.cpp.info.json']) JSON.parse(archivedFile(`node_modules/node-llama-cpp/llama/${name}`).toString())
  const manifest = JSON.parse(await readFile(path.join(directory, 'resources/models/manifest.json'), 'utf8'))
  await verifyWeights(directory, manifest, info)
  for (const file of ['BYE.exe', 'resources/models/LICENSE-QWEN.txt', 'START_HERE.txt', 'THIRD_PARTY_NOTICES.txt', 'VERIFICATION.md']) if (!(await stat(path.join(directory, file))).size) throw new Error(`Missing package file: ${file}`)
  return info
}

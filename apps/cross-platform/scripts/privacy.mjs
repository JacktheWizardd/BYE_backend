import { createReadStream } from 'node:fs'
import { readdir } from 'node:fs/promises'
import path from 'node:path'
import os from 'node:os'
import { fileURLToPath } from 'node:url'
export function violations(text, username = path.basename(os.homedir())) {
  const found = new Set()
  // Upstream public CI paths and literal template examples are not personal build paths.
  if (/(?:[A-Z]:[\\/]+Users[\\/]+(?!Public[\\/]|Default[\\/]|runneradmin[\\/]|runner[\\/])[^\\/\s\x00-\x1f"'<>]+[\\/])|\/Users\/(?!runner\/|shared\/)[^/\s\x00-\x1f"'<>]+\/|\/(?:private\/)?var\/folders\//i.test(text)) found.add('personal filesystem path')
  if (username.length >= 4 && new RegExp('(?<![\\w])' + username.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?![\\w])', 'i').test(text)) found.add('local username')
  if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_-]{10,}|\bAKIA[A-Z0-9]{16}\b/.test(text)) found.add('possible credential')
  return [...found]
}
export async function scan(directory) {
  const failures = []
  async function walk(folder) {
    for (const item of await readdir(folder, { withFileTypes: true })) {
      const file = path.join(folder, item.name)
      if (item.isDirectory()) await walk(file)
      else if (item.isSymbolicLink()) failures.push({ file: path.relative(directory, file), category: 'unexpected symbolic link' })
      else if (item.isFile()) {
        let tail = Buffer.alloc(0); const found = new Set()
        const needles = ['Users/', 'Users\\', 'users/', 'users\\', 'USERS/', 'USERS\\', '/var/folders/', path.basename(os.homedir()), path.basename(os.homedir()).toUpperCase(), 'PRIVATE KEY', 'ghp_', 'github_pat_', 'sk-proj-', 'AKIA'].flatMap(text => {
          const utf16 = Buffer.from(text, 'utf16le'), bigEndian = Buffer.from(utf16); bigEndian.swap16()
          return [{ bytes: Buffer.from(text), encoding: 'utf8' }, { bytes: utf16, encoding: 'utf16le' }, { bytes: bigEndian, encoding: 'utf16be' }]
        })
        for await (const chunk of createReadStream(file, { highWaterMark: 1024 * 1024 })) {
          const bytes = Buffer.concat([tail, chunk])
          // Search raw bytes first. Regex runs on bounded decoded windows, avoiding enormous
          // binary-as-text strings (and excessive memory use for multi-gigabyte GGUF files).
          for (const needle of needles) {
            let offset = bytes.indexOf(needle.bytes)
            while (offset !== -1) {
              const start = needle.encoding === 'utf8' ? Math.max(0, offset - 128) : offset >= 256 ? offset - 256 : offset % 2
              let window = Buffer.from(bytes.subarray(start, Math.min(bytes.length, offset + 1024)))
              if (needle.encoding === 'utf16be') { window = window.subarray(0, window.length - window.length % 2); window.swap16() }
              for (const category of violations(window.toString(needle.encoding === 'utf8' ? 'utf8' : 'utf16le'))) found.add(category)
              offset = bytes.indexOf(needle.bytes, offset + needle.bytes.length)
            }
          }
          tail = bytes.subarray(Math.max(0, bytes.length - 2048))
        }
        for (const category of found) failures.push({ file: path.relative(directory, file), category })
      }
    }
  }
  await walk(directory)
  if (failures.length) { for (const f of failures) console.error(`Distribution check: ${f.file}: ${f.category}`); throw new Error(`Distribution privacy check failed (${failures.length} findings).`) }
  console.log('Distribution privacy check passed.'); return true
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await scan(path.resolve(process.argv[2]))

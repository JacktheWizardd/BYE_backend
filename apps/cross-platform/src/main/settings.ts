import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { randomUUID } from 'node:crypto'
import path from 'node:path'

// App preferences kept only on this PC (%LOCALAPPDATA%\BYECrossPlatformBeta\settings.json). Nothing here is sent anywhere.
export interface Settings { name: string; onboarded: boolean; recent: string[]; recentTerms?: Record<string,string> }
export const DEFAULT_SETTINGS: Settings = { name: '', onboarded: false, recent: [] }
export const NAME_LIMIT = 20, RECENT_LIMIT = 5
const COURSE = /^[A-Z]{2,8} [A-Z]?\d{1,4}[A-Z]*$/

/** Validates a partial update from the renderer. Unknown keys and bad values are rejected, not ignored. */
export function validateSettings(raw: unknown): Partial<Settings> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('Invalid settings.')
  const input = raw as Record<string, unknown>, out: Partial<Settings> = {}
  for (const key of Object.keys(input)) if (!['name', 'onboarded', 'recent', 'recentTerms'].includes(key)) throw new Error('Invalid settings.')
  if ('name' in input) {
    if (typeof input.name !== 'string' || /[\p{Cc}\p{Cf}]/u.test(input.name)) throw new Error('Invalid name.')
    const name = input.name.trim().replace(/ +/g, ' ')
    // Letters, marks, digits, spaces and a few name punctuation marks; no control characters.
    if ([...name].length > NAME_LIMIT || !/^[\p{L}\p{M}\p{N} .'’-]*$/u.test(name)) throw new Error('Invalid name.')
    out.name = name
  }
  if ('onboarded' in input) { if (typeof input.onboarded !== 'boolean') throw new Error('Invalid settings.'); out.onboarded = input.onboarded }
  if ('recent' in input) {
    if (!Array.isArray(input.recent) || input.recent.length > RECENT_LIMIT || !input.recent.every(x => typeof x === 'string' && COURSE.test(x))) throw new Error('Invalid recent classes.')
    out.recent = [...new Set(input.recent as string[])]
  }
  if ('recentTerms' in input) {
    const terms = input.recentTerms
    if (!terms || typeof terms !== 'object' || Array.isArray(terms) || Object.keys(terms).length > RECENT_LIMIT || Object.entries(terms).some(([c,t]) => c.length > 100 || !COURSE.test(c) || typeof t !== 'string' || !/^\d{6}$/.test(t))) throw new Error('Invalid recent semesters.')
    out.recentTerms = { ...terms } as Record<string,string>
  }
  return out
}

export class SettingsStore {
  private queue: Promise<unknown> = Promise.resolve()
  constructor(private readonly file: string) {}
  async get(): Promise<Settings> {
    await this.queue.catch(() => {})
    try { return { ...DEFAULT_SETTINGS, ...validateSettings(JSON.parse(await readFile(this.file, 'utf8'))) } } catch { return { ...DEFAULT_SETTINGS } }
  }
  /** Merges a validated update and writes atomically; returns the saved settings. */
  set(update: unknown): Promise<Settings> {
    let patch: Partial<Settings>
    try { patch = validateSettings(update) } catch (error) { return Promise.reject(error) }
    const next = this.queue.catch(() => {}).then(async () => {
      let current: Settings
      try { current = { ...DEFAULT_SETTINGS, ...validateSettings(JSON.parse(await readFile(this.file, 'utf8'))) } } catch { current = { ...DEFAULT_SETTINGS } }
      const saved = { ...current, ...patch }
      await mkdir(path.dirname(this.file), { recursive: true })
      const tmp = this.file + '.' + randomUUID() + '.tmp'
      await writeFile(tmp, JSON.stringify(saved), { mode: 0o600 })
      await rename(tmp, this.file)
      return saved
    })
    this.queue = next
    return next
  }
}

// Update check: Windows has no installer feed yet, so the app only asks the BYE website whether a newer version exists
// and links to the website's download area. One fixed address, contacted only when the student presses Check.
export const UPDATE_URL = 'https://bye-before-you-enroll.pages.dev/windows/latest.json'
const SITE = 'https://bye-before-you-enroll.pages.dev'
export type UpdateResult = { status: 'current'; version: string } | { status: 'available'; version: string; latest: string; downloadUrl: string } | { status: 'error'; version: string; message: string }

/** Compares versions like 0.4.0-beta.1 < 0.4.0 < 0.5.0-beta.1. Returns >0 when a is newer. */
export function compareVersions(a: string, b: string) {
  const parse = (v: string) => { const m = v.match(/^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$/); if (!m) throw new Error('Invalid version.'); return { nums: [m[1], m[2], m[3]].map(Number), pre: m[4]?.split('.') ?? [] } }
  const x = parse(a), y = parse(b)
  for (let i = 0; i < 3; i++) if (x.nums[i] !== y.nums[i]) return x.nums[i] - y.nums[i]
  if (!x.pre.length || !y.pre.length) return y.pre.length - x.pre.length
  for (let i = 0; i < Math.max(x.pre.length, y.pre.length); i++) {
    const p = x.pre[i], q = y.pre[i]
    if (p === undefined) return -1
    if (q === undefined) return 1
    if (p === q) continue
    const pn = /^\d+$/.test(p), qn = /^\d+$/.test(q)
    if (pn && qn) return Number(p) - Number(q)
    if (pn !== qn) return pn ? -1 : 1
    return p < q ? -1 : 1
  }
  return 0
}

/** Reads the website's version file (bounded in time and size) and compares it with this app. */
export async function checkForUpdate(version: string, fetcher: typeof fetch = fetch): Promise<UpdateResult> {
  try {
    const response = await fetcher(UPDATE_URL, { signal: AbortSignal.timeout(10_000), redirect: 'error', cache: 'no-store', headers: { Accept: 'application/json' } })
    if (!response.ok) throw new Error('bad status')
    const text = await response.text()
    if (text.length > 4096) throw new Error('too large')
    const data = JSON.parse(text) as { version?: unknown; downloadUrl?: unknown }
    if (typeof data.version !== 'string') throw new Error('no version')
    const latest = data.version
    if (compareVersions(latest, version) <= 0) return { status: 'current', version }
    // Only links on the BYE website are opened; anything else falls back to the website's download section.
    const link = typeof data.downloadUrl === 'string' && data.downloadUrl.startsWith(SITE + '/') ? data.downloadUrl : SITE + '/#download'
    return { status: 'available', version, latest, downloadUrl: link }
  } catch {
    return { status: 'error', version, message: "Couldn't reach the BYE website. Check your connection and try again." }
  }
}
export const isUpdateLink = (url: string) => url === SITE + '/#download' || (url.startsWith(SITE + '/') && !/[\s"'<>]/.test(url))

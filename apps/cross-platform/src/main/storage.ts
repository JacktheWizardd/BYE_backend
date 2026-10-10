import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { createHash, randomUUID } from 'node:crypto'
import path from 'node:path'
import type { Course, Profile, Review, Summary } from '../shared/types'
import { normalizedName } from '../shared/domain'
export const hash = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex')
export const choiceKey = (name: string, subject: string) => hash([normalizedName(name), subject])
export const evidenceKey = (reviews: Review[]) => hash([...reviews].sort((a, b) => a.id.localeCompare(b.id)))
const DAY = 86400000
export class Store {
  private writes = new Map<string, Promise<void>>()
  constructor(readonly directory: string, private now = Date.now) {}
  private async read<T>(key: string): Promise<T | undefined> {
    await this.writes.get(key)?.catch(() => {})
    try { return JSON.parse(await readFile(path.join(this.directory, key + '.json'), 'utf8')) } catch { return undefined }
  }
  private async write(key: string, value: unknown, valid = () => true) {
    const previous = this.writes.get(key) ?? Promise.resolve()
    const pending = previous.catch(() => {}).then(async () => {
      if (!valid()) return
      await mkdir(this.directory, { recursive: true })
      const file = path.join(this.directory, key + '.json'), tmp = file + '.' + randomUUID() + '.tmp'
      await writeFile(tmp, JSON.stringify(value), { mode: 0o600 })
      if (valid()) await rename(tmp, file)
      else { const { unlink } = await import('node:fs/promises'); await unlink(tmp).catch(() => {}) }
    })
    this.writes.set(key, pending)
    try { await pending } finally { if (this.writes.get(key) === pending) this.writes.delete(key) }
  }
  private fresh(time: number) { const age = this.now() - time; return Number.isFinite(age) && age >= 0 && age < DAY }
  async choice(name: string, subject: string) { return (await this.read<{ id?: string }>('choice-' + choiceKey(name, subject)))?.id }
  async setChoice(name: string, subject: string, id?: string, valid?: () => boolean) { await this.write('choice-' + choiceKey(name, subject), { id }, valid) }
  async index(name: string, subject: string) { const entry = await this.read<{ id: string; time: number }>('identity-' + choiceKey(name, subject)); return entry && this.fresh(entry.time) ? entry.id : undefined }
  async setIndex(name: string, subject: string, id?: string, valid?: () => boolean) { await this.write('identity-' + choiceKey(name, subject), { id, time: this.now() }, valid) }
  async profile(id: string): Promise<Profile | undefined> {
    const entry = await this.read<{ version: number; time: number; profile: Profile }>('profile-' + hash(id))
    if (!entry || entry.version !== 1 || !this.fresh(entry.time) || entry.profile?.id !== id || !Array.isArray(entry.profile.reviews) || !entry.profile.coverage) return undefined
    return entry.profile
  }
  async setProfile(profile: Profile, valid?: () => boolean) { await this.write('profile-' + hash(profile.id), { version: 1, time: this.now(), profile }, valid) }
  private summaryKey(id: string, c: Course, provider: string) { return 'summary-' + hash([id, c.subject, c.key, provider]) }
  async summary(id: string, c: Course, provider: string, reviews: Review[]) {
    const entry = await this.read<{ version: number; evidence: string; summary: Summary }>(this.summaryKey(id, c, provider))
    return entry?.version === 1 && this.fresh(entry.summary.generatedAt) && entry.summary.providerIdentity === provider && entry.evidence === evidenceKey(reviews) ? entry.summary : undefined
  }
  async setSummary(id: string, c: Course, summary: Summary, reviews: Review[], valid?: () => boolean) { await this.write(this.summaryKey(id, c, summary.providerIdentity), { version: 1, evidence: evidenceKey(reviews), summary }, valid) }
}

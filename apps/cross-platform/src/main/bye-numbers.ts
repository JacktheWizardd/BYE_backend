import type { ByeNumber, NumberResult } from '../shared/app'

// Gets a student's BYE number through the website's review sign-in, like the Mac's ByeNumberClient:
// email a code, verify it, claim the number (supabase/007_bye_numbers.sql). The short-lived session cookie lives only
// in this object's memory and is dropped once the number arrives; the email is never stored. HTTPS only.
export const NUMBERS_SITE = 'https://bye-before-you-enroll.pages.dev'
const SCHOOL = '@go.pasadena.edu'
const COOKIES = ['__Secure-bye-review', 'bye-review-local']

/** The website's rule: a @go.pasadena.edu address with no "+" alias. Null when it doesn't qualify. */
export function schoolEmail(raw: unknown): string | null {
  if (typeof raw !== 'string') return null
  const email = raw.trim().toLowerCase()
  if (email.length > 254 || !email.endsWith(SCHOOL)) return null
  const local = email.slice(0, -SCHOOL.length)
  return local && /^[a-z0-9._-]+$/.test(local) ? email : null
}
export function validCode(raw: unknown): string | null {
  if (typeof raw !== 'string') return null
  const code = raw.trim()
  return /^\d{6,10}$/.test(code) ? code : null
}
/** "name=value" of the review session cookie from a Set-Cookie header, ignoring its attributes. */
export function sessionCookie(header: string | null): string | null {
  const pair = header?.split(';')[0]?.trim() ?? '', name = pair.split('=')[0]
  return COOKIES.includes(name) && pair.length > name.length + 1 ? pair : null
}

class NumberError extends Error {}
const fail = (message: string): never => { throw new NumberError(message) }
const failure = (error: unknown, fallback: string): NumberResult & { ok: false } => ({ ok: false, message: error instanceof NumberError ? error.message : fallback })

export class ByeNumberClient {
  private session: string | null = null
  constructor(private readonly site = NUMBERS_SITE, private readonly request: typeof fetch = fetch) {}

  /** Emails a sign-in code. retryAfter is the seconds to wait before asking again. */
  async sendCode(raw: unknown): Promise<{ ok: true; retryAfter: number } | { ok: false; message: string }> {
    try {
      const email = schoolEmail(raw) ?? fail('Use your PCC school email, ending in @go.pasadena.edu.')
      this.session = null
      const { data } = await this.call('auth/send', { email })
      return { ok: true, retryAfter: Number.isSafeInteger(data?.retryAfter) && data.retryAfter > 0 ? data.retryAfter : 60 }
    } catch (error) { return failure(error, 'The code could not be sent. Try again shortly.') }
  }

  /** Checks the emailed code, then claims (or re-reads) the number. The session is dropped either way. */
  async verify(rawEmail: unknown, rawCode: unknown): Promise<NumberResult> {
    try {
      const email = schoolEmail(rawEmail) ?? fail('Use your PCC school email, ending in @go.pasadena.edu.')
      const code = validCode(rawCode) ?? fail('Enter the complete numeric code from your email.')
      const verified = await this.call('auth/verify', { email, code })
      if (verified.data?.signedIn !== true || !verified.cookie) fail('The code could not be confirmed. Request a new one.')
      this.session = verified.cookie
      const { data } = await this.call('number', {})
      if (!Number.isSafeInteger(data?.number) || !Number.isSafeInteger(data?.total) || data.number < 1 || data.total < 1) fail('Your BYE number could not be confirmed. Try again shortly.')
      return { ok: true, number: { number: data.number, total: Math.max(data.total, data.number) } }
    } catch (error) { return failure(error, 'The code could not be confirmed. Try again shortly.') }
    finally { this.session = null }
  }

  /** How many BYE numbers exist. Public; sends nothing about the student. */
  async total(): Promise<number | null> {
    try { const { data } = await this.call('numbers', null); return Number.isSafeInteger(data?.total) && data.total >= 0 ? data.total : null }
    catch { return null }
  }

  private async call(route: string, body: Record<string, string> | null): Promise<{ data: any; cookie: string | null }> {
    const headers: Record<string, string> = { Accept: 'application/json' }
    if (body) {
      headers['Content-Type'] = 'application/json'
      // The website accepts sign-in posts only from its own origin; the app speaks for that site.
      headers.Origin = this.site
    }
    if (this.session) headers.Cookie = this.session
    let response: Response
    try {
      response = await this.request(`${this.site}/api/reviews/${route}`, { method: body ? 'POST' : 'GET', headers, body: body ? JSON.stringify(body) : undefined,
        redirect: 'error', cache: 'no-store', credentials: 'omit', signal: AbortSignal.timeout(15_000) })
    } catch { return fail('BYE could not reach its website. Try again shortly.') }
    const text = await response.text().catch(() => '')
    if (text.length > 16_384) fail('BYE’s website returned an unexpected response.')
    let json: any = null
    try { json = JSON.parse(text) } catch { /* handled below */ }
    if (!response.ok) fail(typeof json?.error?.message === 'string' && json.error.message.length <= 300 ? json.error.message : response.status === 429 ? 'Please wait before trying again.' : 'BYE could not reach its website. Try again shortly.')
    if (!json || typeof json !== 'object' || !('data' in json)) fail('BYE’s website returned an unexpected response.')
    return { data: json.data, cookie: sessionCookie(response.headers.get('set-cookie')) }
  }
}

/** Keeps "Student 12 of 40" current: the new total, or null when it shouldn't change (lower than your own number). */
export const refreshedNumber = (current: ByeNumber, total: number | null): ByeNumber | null =>
  total !== null && total >= current.number && total !== current.total ? { number: current.number, total } : null

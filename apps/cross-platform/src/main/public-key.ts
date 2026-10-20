/** BYE registry keys and the registered legacy public key are distributable. Privileged keys are not. */
export function publicClientKey(value: string) {
  if (!value) return ''
  if (/^bye_pk_[A-Za-z0-9_-]{32,128}$/.test(value) || /^sb_publishable_[A-Za-z0-9_-]+$/.test(value)) return value
  try { const claims = JSON.parse(Buffer.from(value.split('.')[1],'base64url').toString('utf8')); if (value.split('.').length === 3 && claims.role === 'anon') return value } catch { /* Unknown credential format. */ }
  throw new Error('Configure a public BYE schedule application key. Privileged credentials cannot be bundled with Windows.')
}

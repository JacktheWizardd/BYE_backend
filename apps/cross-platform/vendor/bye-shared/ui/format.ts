import type { Professor } from '../core/types'

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
export const score = (n?: number) => n === undefined ? '—' : n.toFixed(1)
export const day = (s: string) => { const [, m, d] = s.slice(0, 10).split('-').map(Number); return m ? `${MONTHS[m - 1]} ${d}` : '' }
export const monthYear = (s: string) => { const [y, m] = s.slice(0, 7).split('-').map(Number); return y && m ? `${MONTHS[m - 1]} ${y}` : 'Date unavailable' }
export const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
export const courseLabel = (label: string) => label.replace(/^([A-Z]+)(\d)/, '$1 $2')
export const unnamed = (p: Professor) => p.issue?.startsWith('PCC has not') ?? false

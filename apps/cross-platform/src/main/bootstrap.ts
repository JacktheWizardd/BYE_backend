import { app, BrowserWindow, ipcMain, shell } from 'electron'
import path from 'node:path'
import { Engine } from './engine'
import { Store } from './storage'
import type { SummaryProvider } from './summary'
import type { Command, Term } from '../shared/types'
import { reviewURL } from '../shared/domain'
function validate(raw: unknown): Command {
  if (!raw || typeof raw !== 'object') throw new Error('Unsupported command.')
  const c = raw as Record<string, unknown>, kinds = ['terms', 'suggest', 'search', 'stop', 'retry', 'discover', 'dismiss', 'summary', 'select', 'details', 'source']
  if (typeof c.kind !== 'string' || !kinds.includes(c.kind)) throw new Error('Unsupported command.')
  const text = (key: string, max: number, optional = false) => { if (optional && c[key] === undefined) return; if (typeof c[key] !== 'string' || !c[key] || (c[key] as string).length > max) throw new Error('Invalid ' + key) }
  if (['retry', 'discover', 'dismiss', 'summary', 'select', 'details'].includes(c.kind)) text('professorId', 300)
  if (c.kind === 'select') { text('profileId', 30); if (!/^[1-9]\d*$/.test(c.profileId as string)) throw new Error('Invalid profile ID.') }
  if (c.kind === 'details') text('filter', 100, true)
  if (c.kind === 'suggest') { text('term', 6); if (!/^\d{6}$/.test(c.term as string)) throw new Error('Invalid semester.'); if (typeof c.query !== 'string' || c.query.length > 100) throw new Error('Invalid query.') }
  if (c.kind === 'search') {
    text('query', 100)
    const t = c.term as Term; if (!t || !/^\d{6}$/.test(t.termCode) || typeof t.termName !== 'string' || t.termName.length > 100 || (c.refresh !== undefined && typeof c.refresh !== 'boolean')) throw new Error('Invalid search.')
  }
  if (c.kind === 'source') { if (!['pcc', 'rmp', 'review'].includes(String(c.target))) throw new Error('Invalid source.'); text('professorId', 300, true); text('candidateId', 30, true) }
  return c as unknown as Command
}

export interface StartupOptions {
  storage: string; preload: string; renderer: string; rendererURL?: string
  pcc: Engine['pcc']; rmp: Engine['rmp']; ai: SummaryProvider
  beforeWindow?: () => void
}
// Shared internal startup keeps verification on the production security and IPC path.
export function startApplication(options: StartupOptions) {
  app.setPath('userData', options.storage)
  let window: BrowserWindow | undefined
  const ai = options.ai
  const engine = new Engine(options.pcc, options.rmp, new Store(path.join(options.storage, 'reports')), ai, state => window?.webContents.send('bye:state', state))
  function createWindow() {
    window = new BrowserWindow({ width: 1180, height: 800, minWidth: 1000, minHeight: 700, title: 'BYE — Before You Enroll', backgroundColor: '#faf8f3', show: false,
      webPreferences: { preload: options.preload, sandbox: true, contextIsolation: true, nodeIntegration: false, spellcheck: false } })
    window.removeMenu()
    window.once('ready-to-show', () => window?.show())
    window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
    window.webContents.on('will-navigate', event => event.preventDefault())
    window.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false))
    window.webContents.on('did-finish-load', () => engine.emit())
    window.on('closed', () => { window = undefined; engine.stop() })
    if (options.rendererURL) void window.loadURL(options.rendererURL)
    else void window.loadFile(options.renderer)
  }
  app.whenReady().then(() => {
    ipcMain.handle('bye:command', async (event, raw) => {
      if (!window || event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame) throw new Error('Untrusted command sender.')
      const c = validate(raw)
      switch (c.kind) {
        case 'terms': return engine.pcc.terms()
        case 'suggest': return engine.pcc.suggest(c.term, c.query)
        case 'search': void engine.search(c.query, c.term, c.refresh); return undefined
        case 'stop': engine.stop(); return undefined
        case 'retry': void engine.retry(c.professorId); return undefined
        case 'discover': void engine.discover(c.professorId); return undefined
        case 'dismiss': engine.dismiss(c.professorId); return undefined
        case 'select': void engine.select(c.professorId, c.profileId); return undefined
        case 'details': void engine.expand(c.professorId, c.filter); return undefined
        case 'summary': void engine.summarize(c.professorId); return undefined
        case 'source': {
          const p = engine.state.professors.find(x => x.id === c.professorId)
          const candidate = c.candidateId ? p?.candidates.find(x => x.id === c.candidateId) : undefined
          if (c.candidateId && !candidate) throw new Error('This candidate is no longer in the current list.')
          if (c.target === 'review') {
            // Built from the current search only, so the renderer cannot open arbitrary addresses.
            const url = p && engine.state.course ? reviewURL(p.name, engine.state.course) : undefined
            if (!url) throw new Error('Choose a professor in the current search first.')
            await shell.openExternal(url); return undefined
          }
          const url = c.target === 'pcc' ? `https://findclasses.pasadena.edu/?term=${engine.state.term?.termCode ?? ''}&q=${encodeURIComponent(engine.state.course?.display ?? '')}` : candidate || p?.profile ? `https://www.ratemyprofessors.com/professor/${(candidate ?? p!.profile!).id}` : `https://www.ratemyprofessors.com/search/professors/2649?q=${encodeURIComponent(p?.name ?? '')}`
          await shell.openExternal(url); return undefined
        }
      }
    })
    options.beforeWindow?.()
    createWindow()
  })
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
  app.on('activate', () => { if (!window) createWindow(); else { if (window.isMinimized()) window.restore(); window.show(); window.focus() } })
  app.on('before-quit', () => { engine.stop(); void ai.dispose?.() })

  return { engine, getWindow: () => window }
}

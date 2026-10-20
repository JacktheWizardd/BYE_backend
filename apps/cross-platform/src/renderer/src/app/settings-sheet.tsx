import { useEffect, useRef, useState } from 'react'
import type { UpdateCheck } from '../../../shared/app'
import { Segmented } from '../../../../vendor/bye-shared/ui'
import { NAME_LIMIT, validName } from './types'

export type SettingsTab = 'general' | 'updates' | 'about'
// Settings: your name, the update check (Windows checks the BYE website when you ask), and about.
export function SettingsSheet({ open, tab, setTab, name, version, onClose, onSaveName, onWelcome }: {
  open: boolean; tab: SettingsTab; setTab: (t: SettingsTab) => void; name: string; version: string
  onClose: () => void; onSaveName: (name: string) => Promise<void>; onWelcome: () => void
}) {
  const dialog = useRef<HTMLDialogElement>(null)
  const [draft, setDraft] = useState(name), [note, setNote] = useState(''), [bad, setBad] = useState(false)
  const [check, setCheck] = useState<UpdateCheck | 'checking' | null>(null)
  useEffect(() => {
    const d = dialog.current
    if (open && d && !d.open) { setDraft(name); setNote(''); setBad(false); d.showModal() }
    if (!open && d?.open) d.close()
  }, [open])
  async function save() {
    const value = draft.trim()
    if (!value) { setBad(true); setNote('Type a name first.'); return }
    if (!validName(value)) { setBad(true); setNote('Use letters, spaces, hyphens or apostrophes.'); return }
    try { await onSaveName(value); setBad(false); setNote('Saved.') } catch { setBad(true); setNote('That name couldn’t be saved.') }
  }
  async function checkNow() {
    setCheck('checking')
    try { setCheck(await window.byeApp.checkForUpdate()) } catch { setCheck({ status: 'error', version, message: 'The update check failed. Try again.' }) }
  }
  return <dialog ref={dialog} className="sheet settings" aria-labelledby="settings-title" onCancel={e => { e.preventDefault(); onClose() }} onClick={e => { if (e.target === dialog.current) onClose() }}>
    <div className="sheet-head"><h2 id="settings-title">Settings</h2><button className="icon-button" aria-label="Close settings" onClick={onClose}>×</button></div>
    <Segmented label="Settings sections" value={tab} onChange={setTab} options={[['general', 'General'], ['updates', 'Updates'], ['about', 'About']] as const} />
    <div className="sheet-body slide-in" key={tab}>
      {tab === 'general' && <>
        <label className="field-label" htmlFor="settings-name">Your name</label>
        <form className="row start" onSubmit={e => { e.preventDefault(); void save() }}>
          <input id="settings-name" className="field" maxLength={NAME_LIMIT} value={draft} placeholder="Your first name" aria-invalid={bad} aria-describedby="settings-name-note" onChange={e => { setDraft(e.target.value); setNote('') }} />
          <button className="pill" type="submit">Save</button>
        </form>
        <p id="settings-name-note" className={`small ${bad ? 'signal' : 'muted'}`} role="status">{note || 'Stays on this computer.'}</p>
        <button className="text-link" onClick={onWelcome}>Show welcome again</button>
      </>}
      {tab === 'updates' && <>
        <p>You have BYE <span className="mono">{version || '—'}</span>.</p>
        <div><button className="pill primary" disabled={check === 'checking'} onClick={() => void checkNow()}>Check for updates</button></div>
        <div className="update-result" role="status">
          {check === 'checking' && <><span className="progress-bar indeterminate" aria-hidden="true"><i /></span><span className="muted small">Checking…</span></>}
          {check && check !== 'checking' && check.status === 'current' && <span>You’re on the latest version, BYE {check.version}.</span>}
          {check && check !== 'checking' && check.status === 'available' && <span>BYE {check.latest} is out. <button className="text-link" onClick={() => void window.byeApp.openDownload(check.downloadUrl)}>Get it from the website ↗</button></span>}
          {check && check !== 'checking' && check.status === 'error' && <span className="signal">{check.message}</span>}
        </div>
        <p className="muted small">No private information is sent.</p>
      </>}
      {tab === 'about' && <>
        {/* The owner's own words (2026-10-20). */}
        <h3>Hi! :)</h3>
        <p>I’m a PCC student, just like you. I made BYE because I got tired of juggling a bunch of tabs just to find the right professor and plan my classes.</p>
        <p>So I thought, why not put everything in one place?</p>
        <p>BYE is just a little project I started to make picking classes easier for myself and hopefully for you too!</p>
        <p>It’s free, with no ads or tracking. Just something I built for students, by a student.</p>
        <p className="muted small">Ratings from Rate My Professors, schedules from PCC. Licenses and credits are in THIRD_PARTY_NOTICES.txt next to BYE.exe.</p>
      </>}
    </div>
  </dialog>
}

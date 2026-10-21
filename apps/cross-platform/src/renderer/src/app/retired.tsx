import { NETWORK_RETIRED_MESSAGE } from '../../../shared/features'

// Final release: BYE no longer connects to anything, so the app opens to this notice instead of search.
// It never calls the engine, the update check or any other main-process command.
export function Retired() {
  return <main className="onboarding" aria-labelledby="retired-title">
    <div className="welcome">
      <div className="welcome-mark"><span className="swipe">BYE</span></div>
      <p className="welcome-sub">This version is final</p>
      <h1 id="retired-title">BYE has been retired.</h1>
      <p className="lead">{NETWORK_RETIRED_MESSAGE} Thanks for testing BYE.</p>
      <p className="muted small">You can close BYE and delete its folder whenever you like.</p>
    </div>
  </main>
}

import policy from './features.json'
// The same policy controls inference, rendering and Windows package contents.
export const AI_SUMMARIES_ENABLED: boolean = policy.aiSummariesEnabled
export const AI_SUMMARIES_DISABLED_MESSAGE = 'AI summaries are temporarily disabled. Ratings and original reviews remain available.'
// Shown in the report while summaries are off, worded as in the Mac app.
export const AI_SUMMARIES_UNAVAILABLE_NOTE = 'AI summaries are temporarily unavailable. Read the original student reviews below.'
// Final release: when false the app makes no network requests at all (PCC, RMP and the update check).
export const NETWORK_ENABLED: boolean = policy.networkEnabled
export const NETWORK_RETIRED_MESSAGE = 'BYE is no longer active. This version doesn’t connect to the internet, so class searches, ratings and updates are turned off.'

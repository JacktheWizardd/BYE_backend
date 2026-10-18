import policy from './features.json'
// The same policy controls inference, rendering and Windows package contents.
export const AI_SUMMARIES_ENABLED: boolean = policy.aiSummariesEnabled
export const AI_SUMMARIES_DISABLED_MESSAGE = 'AI summaries are temporarily disabled. Ratings and original reviews remain available.'
// Shown in the report while summaries are off, worded as in the Mac app.
export const AI_SUMMARIES_UNAVAILABLE_NOTE = 'AI summaries are temporarily unavailable. Read the original student reviews below.'

// The app bridge (window.byeApp): preferences and the update check. Types only; main/settings.ts implements and validates them.
export interface AppSettings { name: string; onboarded: boolean; recent: string[]; recentTerms?: Record<string,string>; byeNumber?: ByeNumber }
// A student's BYE number and how many exist ("Student 12 of 40"). Only the numbers are kept on this PC, never the email.
export interface ByeNumber { number: number; total: number }
export type NumberResult = { ok: true; number: ByeNumber } | { ok: false; message: string }
export type UpdateCheck = { status: 'current'; version: string } | { status: 'available'; version: string; latest: string; downloadUrl: string } | { status: 'error'; version: string; message: string }
export interface AppBridge {
  info(): Promise<{ version: string }>
  getSettings(): Promise<AppSettings>
  setSettings(update: Partial<AppSettings>): Promise<AppSettings>
  checkForUpdate(): Promise<UpdateCheck>
  openDownload(url: string): Promise<void>
  sendNumberCode(email: string): Promise<{ ok: true; retryAfter: number } | { ok: false; message: string }>
  verifyNumberCode(email: string, code: string): Promise<NumberResult>
  refreshNumberTotal(): Promise<AppSettings>
}

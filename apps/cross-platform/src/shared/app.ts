// The app bridge (window.byeApp): preferences and the update check. Types only; main/settings.ts implements and validates them.
export interface AppSettings { name: string; onboarded: boolean; recent: string[] }
export type UpdateCheck = { status: 'current'; version: string } | { status: 'available'; version: string; latest: string; downloadUrl: string } | { status: 'error'; version: string; message: string }
export interface AppBridge {
  info(): Promise<{ version: string }>
  getSettings(): Promise<AppSettings>
  setSettings(update: Partial<AppSettings>): Promise<AppSettings>
  checkForUpdate(): Promise<UpdateCheck>
  openDownload(url: string): Promise<void>
}

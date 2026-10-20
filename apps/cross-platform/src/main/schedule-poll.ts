/** One visible-client loop; work cannot overlap and failures back off. No source retrieval lives here. */
export class SchedulePoll {
  private timer: ReturnType<typeof setTimeout> | undefined
  private controller: AbortController | undefined
  private active = false
  private failures = 0
  constructor(private work: (signal: AbortSignal) => Promise<void>, private interval = 60_000) {}
  setActive(active: boolean) {
    if (this.active === active) return
    this.active = active
    if (!active) { clearTimeout(this.timer); this.controller?.abort(); return }
    if (!this.controller) this.schedule(0)
  }
  private schedule(ms: number) { clearTimeout(this.timer); if (this.active) { this.timer = setTimeout(() => void this.tick(),ms); this.timer.unref?.() } }
  private async tick() {
    if (!this.active || this.controller) return
    const controller = new AbortController(); this.controller = controller
    try { await this.work(controller.signal); this.failures = 0 }
    catch { if (!controller.signal.aborted) this.failures = Math.min(4,this.failures + 1) }
    finally { this.controller = undefined; this.schedule(this.interval * 2 ** this.failures) }
  }
  stop() { this.setActive(false) }
}

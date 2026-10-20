import { type Budget, portal } from "./session.ts";
type Environment = {
  PUBLIC_ORIGIN: string;
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
  ASSETS: { fetch(req: Request): Promise<Response> };
  OWNER_SESSIONS: any;
};
// A single private object gives consistent routing and global bounded counters.
// Storage holds only three aggregate quotas. Sessions and JWTs stay in RAM.
export class OwnerSessions {
  app: ReturnType<typeof portal>;
  timer: ReturnType<typeof setTimeout> | undefined;
  constructor(ctx: any, env: Environment) {
    const budget: Budget = async (kind, now) =>
      ctx.storage.transaction(async (tx: any) => {
        const period = kind === "requests" ? 60000 : 600000,
          limit = kind === "requests" ? 120 : kind === "send" ? 3 : 20;
        let row = await tx.get("budget:" + kind);
        if (!row || row.until <= now) row = { until: now + period, count: 0 };
        if (row.count >= limit) return false;
        row.count++;
        await tx.put("budget:" + kind, row);
        return row.count <= limit;
      });
    this.app = portal({
      origin: env.PUBLIC_ORIGIN,
      supabaseURL: env.SUPABASE_URL,
      publishableKey: env.SUPABASE_PUBLISHABLE_KEY,
      budget,
      changed: () => this.keepSessionMemory(),
    });
  }
  keepSessionMemory() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    if (this.app.size()) {
      this.timer = setTimeout(() => {
        this.app.purge();
        this.keepSessionMemory();
      }, 30000);
    }
  }
  fetch(req: Request) {
    return this.app.handle(req);
  }
}
const headers = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy":
    "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "no-referrer",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Strict-Transport-Security": "max-age=31536000",
  "X-Robots-Tag": "noindex, nofollow",
};
export default {
  async fetch(req: Request, env: Environment) {
    const url = new URL(req.url);
    let response: Response;
    try {
      if (!env.PUBLIC_ORIGIN || url.origin !== env.PUBLIC_ORIGIN) {
        response = new Response("Host denied", { status: 403 });
      } else if (url.pathname.startsWith("/api/")) {
        response = await env.OWNER_SESSIONS.get(
          env.OWNER_SESSIONS.idFromName("owners-v1"),
        ).fetch(req);
      } else if (req.method !== "GET" && req.method !== "HEAD") {
        response = new Response(null, { status: 405 });
      } else if (
        !["/", "/app.js", "/style.css", "/favicon.ico"].includes(url.pathname)
      ) response = new Response("Not found", { status: 404 });
      else response = await env.ASSETS.fetch(req);
    } catch {
      response = new Response(
        JSON.stringify({
          error: {
            code: "SERVICE_UNAVAILABLE",
            message: "service unavailable",
            retryable: true,
          },
        }),
        { status: 503, headers: { "Content-Type": "application/json" } },
      );
    }
    const result = new Response(response.body, response);
    for (const [key, value] of Object.entries(headers)) {
      result.headers.set(key, value);
    }
    return result;
  },
};

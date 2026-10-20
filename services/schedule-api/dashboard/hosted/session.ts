// Fetch-based owner portal. Auth tokens exist only in this handler's bounded RAM.
// No JWT, refresh token, plaintext BYE key, or student history is persisted.
export type Budget = (
  kind: "requests" | "send" | "verify",
  now: number,
) => Promise<boolean>;
export type PortalOptions = {
  origin: string;
  supabaseURL: string;
  publishableKey: string;
  request?: typeof fetch;
  now?: () => number;
  budget?: Budget;
  changed?: () => void;
};
type Session = { token: string; owner: string; csrf: string; expires: number };
const cookieName = "__Host-bye_admin";
function random() {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...b)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replace(/=+$/, "");
}
const cookie = (id: string, age = 3600) =>
  `${cookieName}=${id}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=${age}`;
export function portal(options: PortalOptions) {
  if (
    !/^https:\/\/[^/?#]+$/.test(options.origin) ||
    new URL(options.origin).origin !== options.origin
  ) throw Error("An exact HTTPS origin is required");
  if (
    !/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(options.supabaseURL) ||
    !/^sb_publishable_[A-Za-z0-9_-]+$/.test(options.publishableKey)
  ) throw Error("Public Supabase Auth configuration required");
  const now = options.now ?? Date.now,
    request = options.request ?? fetch,
    sessions = new Map<string, Session>();
  let active = 0;
  const counters = new Map<string, { until: number; count: number }>();
  const budget = options.budget ?? (async (kind, t) => {
    const period = kind === "requests" ? 60000 : 600000,
      limit = kind === "requests" ? 120 : kind === "send" ? 3 : 20;
    let row = counters.get(kind);
    if (!row || row.until <= t) {
      row = { until: t + period, count: 0 };
      counters.set(kind, row);
    }
    return ++row.count <= limit;
  });
  const purge = () => {
    for (const [id, s] of sessions) if (s.expires <= now()) sessions.delete(id);
  };
  const reply = (status: number, body: unknown, setCookie?: string) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        ...(setCookie ? { "Set-Cookie": setCookie } : {}),
        ...(status === 429 ? { "Retry-After": "60" } : {}),
      },
    });
  async function manage(token: string, input: unknown) {
    const r = await request(
      options.supabaseURL + "/functions/v1/bye-key-admin",
      {
        method: "POST",
        headers: {
          apikey: options.publishableKey,
          Authorization: "Bearer " + token,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(input),
        signal: AbortSignal.timeout(20000),
      },
    );
    return { status: r.status, data: await r.json() };
  }
  async function logout(token: string) {
    try {
      const r = await request(
        options.supabaseURL + "/auth/v1/logout?scope=local",
        {
          method: "POST",
          headers: {
            apikey: options.publishableKey,
            Authorization: "Bearer " + token,
          },
          signal: AbortSignal.timeout(5000),
        },
      );
      await r.body?.cancel();
    } catch {}
  }
  const handle = async (req: Request): Promise<Response> => {
    const url = new URL(req.url);
    if (url.origin !== options.origin) {
      return reply(403, { error: "HOST_DENIED" });
    }
    if (
      ![
        "/api/session",
        "/api/auth/send",
        "/api/auth/verify",
        "/api/manage",
        "/api/signout",
      ].includes(url.pathname) || url.search
    ) return reply(404, { error: "NOT_FOUND" });
    if (active >= 8) return reply(429, { error: "BUSY" });
    active++;
    purge();
    try {
      if (!await budget("requests", now())) {
        return reply(429, { error: "RATE_LIMITED" });
      }
      const id = req.headers.get("Cookie")?.match(
          /(?:^|; )__Host-bye_admin=([A-Za-z0-9_-]{43})(?:;|$)/,
        )?.[1] ?? "",
        session = sessions.get(id);
      if (req.method === "GET" && url.pathname === "/api/session") {
        return reply(
          200,
          session
            ? {
              owner: session.owner,
              csrf: session.csrf,
              expires: session.expires,
            }
            : { signedIn: false },
          !session && id ? cookie("", 0) : undefined,
        );
      }
      if (req.method !== "POST") {
        return reply(405, { error: "METHOD_NOT_ALLOWED" });
      }
      if (
        req.headers.get("Origin") !== options.origin ||
        req.headers.get("X-BYE-Local") !== "1" ||
        !req.headers.get("Content-Type")?.startsWith("application/json")
      ) return reply(403, { error: "ORIGIN_DENIED" });
      const auth = url.pathname.startsWith("/api/auth/");
      if (!auth) {
        if (!session) {
          return reply(401, { error: "SESSION_EXPIRED" }, cookie("", 0));
        }
        if (req.headers.get("X-CSRF-Token") !== session.csrf) {
          return reply(403, { error: "CSRF_DENIED" });
        }
      }
      let input: any;
      try {
        input = await readJSON(req);
      } catch {
        return reply(400, { error: "INVALID_QUERY" });
      }
      if (!input || typeof input !== "object" || Array.isArray(input)) {
        return reply(400, { error: "INVALID_QUERY" });
      }
      if (auth) {
        if (
          typeof input.email !== "string" || input.email.length > 254 ||
          !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email)
        ) return reply(400, { error: "INVALID_EMAIL" });
        const sending = url.pathname.endsWith("/send");
        if (
          !sending &&
          (typeof input.code !== "string" || !/^\d{6,10}$/.test(input.code))
        ) return reply(400, { error: "INVALID_CODE" });
        if (!await budget(sending ? "send" : "verify", now())) {
          return reply(429, { error: "WAIT_BEFORE_RETRY" });
        }
        const r = await request(
          options.supabaseURL + "/auth/v1/" + (sending ? "otp" : "verify"),
          {
            method: "POST",
            headers: {
              apikey: options.publishableKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(
              sending
                ? { email: input.email, create_user: false }
                : { email: input.email, token: input.code, type: "email" },
            ),
            signal: AbortSignal.timeout(15000),
          },
        );
        if (sending) {
          await r.body?.cancel();
          return reply(
            r.ok ? 200 : r.status === 429 ? 429 : 400,
            r.ok ? { sent: true } : { error: "EMAIL_REQUEST_FAILED" },
          );
        }
        if (!r.ok) {
          await r.body?.cancel();
          return reply(r.status === 429 ? 429 : 401, { error: "INVALID_CODE" });
        }
        const data: any = await r.json();
        if (
          typeof data.access_token !== "string" || !data.user?.id ||
          !Number.isFinite(data.expires_in) || data.expires_in <= 0
        ) return reply(502, { error: "INVALID_AUTH_RESPONSE" });
        const owner = await manage(data.access_token, {
          action: "session",
          args: {},
        });
        if (owner.status !== 200) {
          await logout(data.access_token);
          return reply(owner.status, {
            error: "OWNER_ACCESS_REQUIRED",
            userId: data.user.id,
          });
        }
        if (id) sessions.delete(id);
        if (sessions.size >= 8) {
          await logout(data.access_token);
          return reply(429, { error: "SESSION_LIMIT" });
        }
        const newId = random(),
          csrf = random(),
          expires = now() + Math.min(3600, data.expires_in) * 1000;
        sessions.set(newId, {
          token: data.access_token,
          owner: data.user.id,
          csrf,
          expires,
        });
        options.changed?.();
        return reply(
          200,
          { owner: data.user.id, csrf, expires },
          cookie(newId, Math.floor((expires - now()) / 1000)),
        );
      }
      if (url.pathname === "/api/signout") {
        sessions.delete(id);
        options.changed?.();
        await logout(session!.token);
        return reply(200, { signedOut: true }, cookie("", 0));
      }
      const result = await manage(session!.token, input);
      if (result.status === 401 || result.status === 403) {
        sessions.delete(id);
        options.changed?.();
        return reply(result.status, result.data, cookie("", 0));
      }
      return reply(result.status, result.data);
    } catch {
      return reply(503, {
        error: "REQUEST_FAILED",
        message:
          "Result uncertain. Retry the same request ID; do not blindly create another key.",
      });
    } finally {
      active--;
    }
  };
  return {
    handle,
    purge,
    size: () => {
      purge();
      return sessions.size;
    },
    clear: () => sessions.clear(),
  };
}
async function readJSON(req: Request) {
  if (Number(req.headers.get("Content-Length") ?? 0) > 8192) throw Error();
  const reader = req.body?.getReader();
  if (!reader) throw Error();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let text = "", bytes = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > 8192) {
        await reader.cancel();
        throw Error();
      }
      text += decoder.decode(chunk.value, { stream: true });
    }
    text += decoder.decode();
    return JSON.parse(text);
  } finally {
    reader.releaseLock();
  }
}

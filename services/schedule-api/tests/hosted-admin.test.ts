import { test } from "node:test";
import assert from "node:assert/strict";
import { portal } from "../dashboard/hosted/session.ts";
import worker, { OwnerSessions } from "../dashboard/hosted/cloudflare.ts";
const origin = "https://bye-admin.example.test",
  supabaseURL = "https://fixture.supabase.co",
  publishableKey = "sb_publishable_fixture",
  jwt = "fixture.owner.jwt-never-exposed";
const json = (value: any, status = 200) =>
  new Response(JSON.stringify(value), { status });
function fixture() {
  let clock = Date.now(), owner = true, offline = false, emails = 0;
  const app = portal({
    origin,
    supabaseURL,
    publishableKey,
    now: () => clock,
    request: async (url, init) => {
      if (offline) throw Error("private server credential");
      const path = new URL(String(url)).pathname;
      if (path.endsWith("/otp")) {
        emails++;
        assert.equal(JSON.parse(String(init?.body)).create_user, false);
        return json({});
      }
      if (path.endsWith("/verify")) {
        return json({
          access_token: jwt,
          refresh_token: "discard-me",
          expires_in: 60,
          user: { id: "owner" },
        });
      }
      if (path.includes("bye-key-admin")) {
        assert.equal((init?.headers as any).Authorization, "Bearer " + jwt);
        return owner
          ? json({ owner: "owner", items: [] })
          : json({ error: { code: "FORBIDDEN" } }, 403);
      }
      return json({});
    },
  });
  let cookie = "", csrf = "";
  const req = (
    path: string,
    data: any = {},
    extra: Record<string, string> = {},
  ) =>
    new Request(origin + path, {
      method: "POST",
      headers: {
        Origin: origin,
        "Content-Type": "application/json",
        "X-BYE-Local": "1",
        Cookie: cookie,
        "X-CSRF-Token": csrf,
        ...extra,
      },
      body: JSON.stringify(data),
    });
  const login = async () => {
    const r = await app.handle(
      req("/api/auth/verify", { email: "owner@example.test", code: "123456" }),
    );
    const d: any = await r.json();
    if (r.ok) {
      cookie = r.headers.get("set-cookie")!.split(";")[0];
      csrf = d.csrf;
    }
    return { r, d };
  };
  return {
    app,
    req,
    login,
    setOwner: (v: boolean) => owner = v,
    setOffline: (v: boolean) => offline = v,
    advance: () => clock += 61000,
    emails: () => emails,
    clearCookie: () => {
      cookie = "";
      csrf = "";
    },
  };
}
test("hosted owner sessions use secure opaque cookies; owner checks, sign-out and expiry fail closed", async () => {
  const f = fixture();
  f.setOwner(false);
  assert.equal((await f.login()).r.status, 403);
  assert.equal(f.app.size(), 0);
  f.setOwner(true);
  const signed = await f.login();
  assert.equal(signed.r.status, 200);
  assert.match(
    signed.r.headers.get("set-cookie")!,
    /^__Host-bye_admin=.*Secure; HttpOnly; SameSite=Strict/,
  );
  assert(!JSON.stringify(signed.d).includes(jwt));
  assert(!signed.r.headers.get("set-cookie")!.includes(jwt));
  assert.equal(
    (await f.app.handle(f.req("/api/manage", { action: "list" }))).status,
    200,
  );
  f.setOwner(false);
  assert.equal(
    (await f.app.handle(f.req("/api/manage", { action: "list" }))).status,
    403,
  );
  assert.equal(f.app.size(), 0);
  f.setOwner(true);
  await f.login();
  f.advance();
  assert.equal((await f.app.handle(f.req("/api/manage", {}))).status, 401);
  await f.login();
  assert.equal((await f.app.handle(f.req("/api/signout"))).status, 200);
  assert.equal(f.app.size(), 0);
});
test("hosted Host/Origin/CSRF, size and network failures preserve security", async () => {
  const f = fixture();
  assert.equal(
    (await f.app.handle(new Request("https://wrong.example/api/session")))
      .status,
    403,
  );
  assert.equal(
    (await f.app.handle(
      f.req("/api/auth/send", { email: "owner@example.test" }, {
        Origin: "https://evil.example",
      }),
    )).status,
    403,
  );
  assert.equal(f.emails(), 0);
  await f.login();
  assert.equal(
    (await f.app.handle(f.req("/api/manage", {}, { "X-CSRF-Token": "wrong" })))
      .status,
    403,
  );
  assert.equal(
    (await f.app.handle(f.req("/api/manage", { text: "x".repeat(8193) })))
      .status,
    400,
  );
  f.setOffline(true);
  const r = await f.app.handle(f.req("/api/manage", {}));
  assert.equal(r.status, 503);
  assert(!await r.text().then((s) => s.includes("private server credential")));
});
test("hosted registry sessions and email attempts remain bounded across repeated reads", async () => {
  const f = fixture();
  for (let i = 0; i < 8; i++) {
    await f.login();
    f.clearCookie();
  }
  assert.equal(f.app.size(), 8);
  assert.equal((await f.login()).r.status, 429);
  f.app.clear();
  assert.equal(f.app.size(), 0);
  const g = fixture();
  for (let i = 0; i < 3; i++) {
    assert.equal(
      (await g.app.handle(
        g.req("/api/auth/send", { email: "owner@example.test" }),
      )).status,
      200,
    );
  }
  assert.equal(
    (await g.app.handle(
      g.req("/api/auth/send", { email: "owner@example.test" }),
    )).status,
    429,
  );
  assert.equal(g.emails(), 3);
  for (let i = 0; i < 120; i++) {
    await g.app.handle(new Request(origin + "/api/session"));
  }
  assert.equal(
    (await g.app.handle(new Request(origin + "/api/session"))).status,
    429,
  );
});
test("hosted router adds CSP and rejects alternate hosts; durable storage contains quotas only", async () => {
  let routed = 0;
  const env: any = {
    PUBLIC_ORIGIN: origin,
    SUPABASE_URL: supabaseURL,
    SUPABASE_PUBLISHABLE_KEY: publishableKey,
    ASSETS: { fetch: async () => new Response("<html>Owner</html>") },
    OWNER_SESSIONS: {
      idFromName: (n: string) => {
        assert.equal(n, "owners-v1");
        return n;
      },
      get: () => ({
        fetch: async () => {
          routed++;
          return json({ signedIn: false });
        },
      }),
    },
  };
  let r = await worker.fetch(new Request(origin + "/"), env);
  assert.equal(r.status, 200);
  assert.match(
    r.headers.get("content-security-policy")!,
    /frame-ancestors 'none'/,
  );
  assert.equal(
    (await worker.fetch(new Request("https://wrong.example/"), env)).status,
    403,
  );
  await worker.fetch(new Request(origin + "/api/session"), env);
  assert.equal(routed, 1);
  const storage = new Map();
  const tx = {
    get: async (k: string) => storage.get(k),
    put: async (k: string, v: any) => {
      assert.match(k, /^budget:(requests|send|verify)$/);
      storage.set(k, v);
    },
  };
  const ctx = { storage: { transaction: async (fn: any) => fn(tx) } };
  const object = new OwnerSessions(ctx, env);
  await object.fetch(new Request(origin + "/api/session"));
  assert.equal(storage.size, 1);
  assert(!JSON.stringify([...storage]).includes(jwt));
  assert.equal(object.app.size(), 0);
});

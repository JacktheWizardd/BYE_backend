// Full workerd + SQLite Durable Object, with every outbound request intercepted.
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { Miniflare, Response as TestResponse } from "miniflare";
const origin = "https://bye-admin.example.test",
  token = "fixture.auth.jwt-keep-in-server-memory";
let owner = true, sendCount = 0;
const temp = await mkdtemp(path.join(os.tmpdir(), "bye-admin-runtime-"));
const options = {
  resourcePersistencePath: temp,
  telemetry: { enabled: false },
  workers: [{
    config: {
      name: "admin-test",
      compatibilityDate: "2026-10-19",
      manifest: {
        mainModule: "index.js",
        modules: {
          "index.js": {
            type: "esm",
            contents: await readFile(
              new URL(
                "../dashboard/hosted/.deploy/hosted-admin/cloudflare.js",
                import.meta.url,
              ),
              "utf8",
            ),
          },
        },
      },
      exports: { OwnerSessions: { type: "durable-object", storage: "sqlite" } },
      env: {
        PUBLIC_ORIGIN: { type: "text", value: origin },
        SUPABASE_URL: { type: "text", value: "https://fixture.supabase.co" },
        SUPABASE_PUBLISHABLE_KEY: {
          type: "text",
          value: "sb_publishable_fixture",
        },
        OWNER_SESSIONS: {
          type: "durable-object",
          worker: "admin-test",
          exportName: "OwnerSessions",
        },
        ASSETS: {
          type: "fetcher",
          handler: async () => new TestResponse("<html>BYE owner</html>"),
        },
      },
    },
    dev: {
      outboundService: {
        type: "fetcher",
        handler: async (req) => {
          const url = new URL(req.url);
          assert.equal(url.hostname, "fixture.supabase.co");
          const json = (data, status = 200) =>
            new TestResponse(JSON.stringify(data), { status });
          if (url.pathname.endsWith("/otp")) {
            sendCount++;
            assert.equal((await req.json()).create_user, false);
            return json({});
          }
          if (url.pathname.endsWith("/verify")) {
            return json({
              access_token: token,
              refresh_token: "discard",
              expires_in: 3600,
              user: { id: "owner" },
            });
          }
          if (url.pathname.includes("bye-key-admin")) {
            assert.equal(req.headers.get("Authorization"), "Bearer " + token);
            return owner
              ? json({ owner: "owner", items: [] })
              : json({ error: { code: "FORBIDDEN" } }, 403);
          }
          return json({});
        },
      },
    },
  }],
};
let mf = new Miniflare(options);
const restart = async () => {
  await mf.dispose();
  mf = new Miniflare(options);
  await mf.ready;
};
let cookie = "", csrf = "";
const call = (path, body = {}, headers = {}) =>
  mf.dispatchFetch(origin + path, {
    method: "POST",
    headers: {
      Origin: origin,
      "Content-Type": "application/json",
      "X-BYE-Local": "1",
      Cookie: cookie,
      "X-CSRF-Token": csrf,
      ...headers,
    },
    body: JSON.stringify(body),
  });
try {
  await mf.ready;
  let r = await mf.dispatchFetch(origin + "/");
  assert.equal(r.status, 200);
  assert.match(
    r.headers.get("content-security-policy"),
    /frame-ancestors 'none'/,
  );
  assert.equal((await mf.dispatchFetch("https://wrong.example/")).status, 403);
  assert.equal(
    (await call("/api/auth/send", { email: "owner@example.test" }, {
      Origin: "https://evil.example",
    })).status,
    403,
  );
  assert.equal(sendCount, 0);
  owner = false;
  assert.equal(
    (await call("/api/auth/verify", {
      email: "owner@example.test",
      code: "123456",
    })).status,
    403,
  );
  owner = true;
  r = await call("/api/auth/verify", {
    email: "owner@example.test",
    code: "123456",
  });
  assert.equal(r.status, 200);
  const signed = await r.json();
  cookie = r.headers.get("set-cookie").split(";")[0];
  csrf = signed.csrf;
  assert.match(r.headers.get("set-cookie"), /Secure; HttpOnly/);
  assert(!JSON.stringify(signed).includes(token));
  assert.equal((await call("/api/manage", { action: "list" })).status, 200);
  assert.equal(
    (await call("/api/manage", { action: "create" }, {
      "X-CSRF-Token": "wrong",
    })).status,
    403,
  );
  // A Cloudflare eviction must drop login tokens; aggregate quotas survive.
  await restart();
  assert.equal((await call("/api/manage", { action: "list" })).status, 401);
  for (let i = 0; i < 3; i++) {
    assert.equal(
      (await call("/api/auth/send", { email: "owner@example.test" })).status,
      200,
    );
  }
  await restart();
  assert.equal(
    (await call("/api/auth/send", { email: "owner@example.test" })).status,
    429,
  );
  assert.equal(sendCount, 3);
  console.log(
    "PASS workerd runtime: routing, owner auth, secure cookies, CSRF, memory-session restart and persistent bounded quotas",
  );
} finally {
  await mf.dispose();
  const resolved = path.resolve(temp);
  if (
    path.dirname(resolved) !== path.resolve(os.tmpdir()) ||
    !path.basename(resolved).startsWith("bye-admin-runtime-")
  ) throw Error("Unexpected fixture storage path");
  await rm(resolved, { recursive: true, force: true });
}

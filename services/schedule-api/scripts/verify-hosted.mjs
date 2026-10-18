// Calls only BYE/Supabase. Never contacts PCC or RMP.
import assert from "node:assert/strict";
const base = process.env.BYE_API_URL ??
    "https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api",
  key = process.env.BYE_CLIENT_KEY ?? process.env.BYE_PUBLISHABLE_KEY;
if (!key) throw Error("Set BYE_CLIENT_KEY");
const call = (path, headers = {}) =>
  fetch(base + path, {
    headers: { apikey: key, ...headers },
    signal: AbortSignal.timeout(20000),
  });
let checks = 0;
async function verify(name, fn) {
  await fn();
  checks++;
  console.log("PASS", name);
}
await verify("authentication and private worker denial", async () => {
  assert.equal((await fetch(base + "/v1/terms")).status, 401);
  assert.equal(
    (await fetch(base.replace("bye-schedule-api", "bye-schedule-sync"), {
      method: "POST",
      headers: { apikey: key },
      body: "{}",
    })).status,
    401,
  );
});
await verify("only imported Fall term", async () => {
  const r = await call("/v1/terms");
  assert.equal(r.status, 200);
  assert.deepEqual((await r.json()).data.map((x) => x.termCode), ["202670"]);
  assert.equal((await call("/v1/terms/202630/catalog")).status, 404);
});
await verify("aliases, suffixes and partial course searches", async () => {
  for (const q of ["MATH 005A", "math 005a", "math 5a", "MATH5A"]) {
    const r = await call("/v1/terms/202670/courses?q=" + encodeURIComponent(q));
    assert.equal(r.status, 200);
    assert.equal((await r.json()).data[0].key, "MATH 005A");
  }
  const partial = await (await call("/v1/terms/202670/courses?q=MATH005"))
    .json();
  assert(partial.data.some((c) => c.key === "MATH 005B"));
});
await verify("catalog counts and conditional reads", async () => {
  const r = await call("/v1/terms/202670/catalog");
  assert.equal(r.status, 200);
  const body = await r.json();
  assert(body.data.length >= 1000);
  assert.equal(
    (await call("/v1/terms/202670/catalog", {
      "If-None-Match": r.headers.get("etag"),
    })).status,
    304,
  );
});
await verify(
  "structured source comparisons, freshness and bounded availability",
  async () => {
    const r = await call("/v1/terms/202670/courses/MATH%20005A/sections");
    const b = await r.json();
    assert.equal(r.status, 200);
    assert(b.data.some((s) => s.crn === "71655"));
    assert(b.data.some((s) => s.crn === "80206"));
    assert(!JSON.stringify(b).includes("@"));
    if (!b.meta.stale) {
      const section = b.data.find((s) => s.crn === "71655");
      assert.equal(section.availability.statusCode, "C");
      assert(section.availability.seatsAvailable > 0);
    } else assert(b.data.every((s) => s.availability === null));
    const a = await call("/v1/terms/202670/availability?crns=71655,80206");
    assert.equal(a.status, 200);
    assert.equal((await a.json()).data.length, 2);
    assert.equal(
      (await call("/v1/terms/202670/availability?crns=bad")).status,
      400,
    );
  },
);
await verify("hybrid dates remain separate", async () => {
  const r = await call("/v1/terms/202670/courses/ACCT%20001A/sections");
  const section = (await r.json()).data.find((s) => s.crn === "81016");
  assert(section.meetings.some((m) => m.startDate === "2026-09-29"));
  assert(section.meetings.some((m) => m.startDate === "2026-10-27"));
  assert(section.meetings.some((m) => m.startDate === "2026-11-24"));
});
await verify("manifest and published contract", async () => {
  const m = await (await call("/v1/terms/202670/manifest")).json();
  assert.equal(m.data.capabilities.clientPollSeconds, 60);
  assert.equal(m.data.capabilities.maxAvailabilityCrns, 100);
  const r = await call("/v1/openapi.json");
  assert.equal(r.status, 200);
  assert.equal((await r.json()).info.version, "1.0.0");
});
await verify("public key cannot invoke server RPC", async () => {
  const url = new URL(base).origin + "/rest/v1/rpc/bye_schedule_backend";
  const r = await fetch(url, {
    method: "POST",
    headers: { apikey: key, "Content-Type": "application/json" },
    body: JSON.stringify({ op: "state" }),
  });
  assert([401, 403, 404].includes(r.status));
});
console.log(`${checks} hosted scenarios passed`);

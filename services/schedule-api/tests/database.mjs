import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
import { prepare, sha } from "../src/domain.ts";
import { upload, worker } from "../src/sync.ts";
import { api } from "../src/api.ts";
const db = new PGlite();
const fixture = JSON.parse(
  await readFile(new URL("./fixtures/fall-2026.json", import.meta.url), "utf8"),
);
await db.exec(
  "create role anon;create role authenticated;create role service_role bypassrls;create table public.review_sentinel(id int primary key,body text);insert into public.review_sentinel values(1,'unchanged');",
);
for (
  const migration
    of (await readdir(new URL("../supabase/migrations/", import.meta.url)))
      .filter((x) => x.endsWith(".sql") && !x.includes("scheduler")).sort()
) {
  await db.exec(
    await readFile(
      new URL("../supabase/migrations/" + migration, import.meta.url),
      "utf8",
    ),
  );
}
const query = async (sql, args = []) => (await db.query(sql, args)).rows;
const rpc = {
  async rpc(_name, { op, args = {} }) {
    return (await query(
      "select public.bye_schedule_backend($1,$2::jsonb) value",
      [op, JSON.stringify(args)],
    ))[0].value;
  },
};
const call = (op, args = {}) => rpc.rpc("bye_schedule_backend", { op, args });
let checks = 0;
async function check(name, fn) {
  await fn();
  console.log("PASS", name);
  checks++;
}
let first = await prepare(fixture.rows), claim;
await check(
  "private roles cannot read, write or invoke server operations",
  async () => {
    for (const role of ["anon", "authenticated"]) {
      await db.exec("set role " + role);
      for (
        const sql of [
          "select public.bye_schedule_backend('state')",
          "select * from bye_schedule.raw_rows",
          "update bye_schedule.state set enabled=true",
        ]
      ) await assert.rejects(db.exec(sql), /permission denied/);
      await db.exec("reset role");
    }
    await db.exec("set role service_role");
    await assert.rejects(
      db.exec("select * from bye_schedule.raw_rows"),
      /permission denied/,
    );
    await call("state");
    await db.exec("reset role");
  },
);
await check(
  "partial staging, distributed lock and failed publication retain current data",
  async () => {
    claim = await call("claim", { mode: "bootstrap" });
    assert(claim.token);
    assert.equal(
      (await call("claim", { mode: "bootstrap" })).skipped,
      "LOCKED",
    );
    await assert.rejects(
      call("publish", {
        token: claim.token,
        catalogHash: first.catalogHash,
        availabilityHash: first.availabilityHash,
        sourceHash: first.sourceHash,
        rowCount: first.rowCount,
        sectionCount: first.sections.length,
        retrievedAt: new Date().toISOString(),
      }),
      /Incomplete/,
    );
    assert.equal((await call("state")).catalog, null);
  },
);
await check(
  "complete atomic publish reconciles source and curated sections",
  async () => {
    await upload(
      rpc,
      claim.token,
      first,
      claim,
      new Date().toISOString(),
      fixture.terms[0],
      true,
    );
    const s = await call("state");
    assert.equal(s.catalog, first.catalogHash);
    assert.equal(s.availability, first.availabilityHash);
    assert.equal(
      (await query("select count(*)::int n from bye_schedule.raw_rows"))[0].n,
      7,
    );
    const r = await call("read", {
      route: "sections",
      term: "202670",
      courseKey: "MATH 005A",
      identity: "a".repeat(64),
    });
    assert.equal(r.data[0].availability.seatsAvailable, 7);
    assert.equal(r.data[0].availability.statusCode, "C");
    assert.equal(r.data[0].instructors.length, 2);
    const hybrid = await call("read", {
      route: "sections",
      courseKey: "ACCT 001A",
      identity: "a".repeat(64),
    });
    assert.equal(hybrid.data[0].meetings.length, 3);
  },
);
await check(
  "unchanged/reordered source avoids duplicate catalog and availability writes",
  async () => {
    const before = await query(
      "select crn,xmin::text from bye_schedule.availability order by crn",
    );
    await db.exec("update bye_schedule.state set next_fetch='-infinity'");
    claim = await call("claim", { mode: "owner" });
    await upload(
      rpc,
      claim.token,
      await prepare([...fixture.rows].reverse()),
      claim,
      new Date().toISOString(),
      fixture.terms[0],
      false,
    );
    assert.deepEqual(
      await query(
        "select crn,xmin::text from bye_schedule.availability order by crn",
      ),
      before,
    );
    assert.equal(
      (await query("select count(*)::int n from bye_schedule.catalogs"))[0].n,
      1,
    );
  },
);
let changed = structuredClone(fixture.rows);
changed[0].seatsAvail = "6";
await check(
  "seat changes modify only changed rows and preserve catalog identity",
  async () => {
    await db.exec("update bye_schedule.state set next_fetch='-infinity'");
    claim = await call("claim", { mode: "owner" });
    await upload(
      rpc,
      claim.token,
      await prepare(changed),
      claim,
      new Date().toISOString(),
      fixture.terms[0],
      false,
    );
    const s = await call("state");
    assert.equal(s.catalog, first.catalogHash);
    assert.notEqual(s.availability, first.availabilityHash);
    assert.equal(
      (await query(
        "select count(*)::int n from bye_schedule.availability where rollback_member",
      ))[0].n,
      1,
    );
  },
);
await check(
  "rollback and repeated rollback only affect the last changed members",
  async () => {
    await call("rollback");
    assert.equal(
      (await query(
        "select value->>'seatsAvailable' n from bye_schedule.availability where crn='80206'",
      ))[0].n,
      "7",
    );
    assert.equal(
      (await query(
        "select value->>'statusCode' n from bye_schedule.availability where crn='90001'",
      ))[0].n,
      "R",
    );
    await call("rollback");
    assert.equal(
      (await query(
        "select value->>'seatsAvailable' n from bye_schedule.availability where crn='80206'",
      ))[0].n,
      "6",
    );
    assert.equal((await call("state")).checked_at, null);
  },
);
await check(
  "stale counts suppressed, daily/idle scheduling and shared cooldown",
  async () => {
    const stale = await call("read", {
      route: "availability",
      crns: ["80206"],
      identity: "a".repeat(64),
    });
    assert.equal(stale.meta.stale, true);
    assert.equal(stale.data[0].availability, null);
    await call("enable", { enabled: true });
    await db.exec(
      "update bye_schedule.state set daily_date=(now()-interval '10 hours')::date,active_until=now()-interval '1 minute',next_fetch='-infinity'",
    );
    assert.equal((await call("claim", { mode: "scheduled" })).skipped, "IDLE");
    await db.exec(
      "update bye_schedule.state set active_until=now()+interval '10 minutes'",
    );
    claim = await call("claim", { mode: "scheduled" });
    assert(claim.token);
    await call("fail", { token: claim.token, retrySeconds: 900 });
    assert.equal((await call("claim", { mode: "owner" })).skipped, "COOLDOWN");
    assert.equal((await call("state")).catalog, first.catalogHash);
  },
);
await check(
  "API polling has stable catalog ETags and bounded lease/limit storage",
  async () => {
    const handler = api(rpc, await sha("key"), "salt");
    const request = (path) =>
      new Request("https://api.test" + path, {
        headers: { apikey: "key", "x-forwarded-for": "fixture" },
      });
    const initial = await handler(request("/v1/terms/202670/catalog"));
    assert.equal(initial.status, 200);
    const tag = initial.headers.get("etag");
    const renewal = (await call("state")).renewed_at;
    for (let i = 0; i < 110; i++) {
      assert.equal(
        (await handler(request("/v1/terms/202670/manifest"))).status,
        200,
      );
    }
    assert.equal((await call("state")).renewed_at, renewal);
    assert.equal(
      (await query("select count(*)::int n from bye_schedule.limits"))[0].n,
      2,
    );
    assert.equal(
      (await handler(
        new Request("https://api.test/v1/terms/202670/catalog", {
          headers: {
            apikey: "key",
            "x-forwarded-for": "fixture",
            "if-none-match": tag,
          },
        }),
      )).status,
      304,
    );
    for (let i = 0; i < 20; i++) await handler(request("/v1/terms"));
    assert.equal((await handler(request("/v1/terms"))).status, 429);
  },
);
await check(
  "worker authentication and scheduled skip send no PCC traffic",
  async () => {
    let hits = 0;
    const handler = worker(rpc, "secret", async () => {
      hits++;
      throw Error("unexpected live request");
    });
    assert.equal(
      (await handler(new Request("https://worker", { method: "POST" }))).status,
      401,
    );
    await call("enable", { enabled: false });
    const result = await handler(
      new Request("https://worker", {
        method: "POST",
        headers: { Authorization: "Bearer secret" },
        body: JSON.stringify({ action: "scheduled" }),
      }),
    );
    assert.equal((await result.json()).skipped, "DISABLED");
    assert.equal(hits, 0);
  },
);
await check(
  "catalog changes, removals, retention and review sentinel preserved",
  async () => {
    for (let i = 0; i < 4; i++) {
      const rows = structuredClone(changed);
      rows[0].courseTitle = "TITLE " + i;
      if (i === 3) rows.pop();
      await db.exec("update bye_schedule.state set next_fetch='-infinity'");
      claim = await call("claim", { mode: "owner" });
      await upload(
        rpc,
        claim.token,
        await prepare(rows),
        claim,
        new Date().toISOString(),
        fixture.terms[0],
        false,
      );
      await call("cleanup");
    }
    assert.equal(
      (await query("select count(*)::int n from bye_schedule.catalogs"))[0].n,
      2,
    );
    assert.equal(
      (await query("select count(*)::int n from bye_schedule.staging"))[0].n,
      0,
    );
    assert.equal(
      (await query("select body from public.review_sentinel"))[0].body,
      "unchanged",
    );
  },
);
await check("null and expired tokens cannot stage or publish", async () => {
  await assert.rejects(
    call("stage", { kind: "raw", part: 0, payload: [] }),
    /Expired lock/,
  );
  await assert.rejects(
    call("publish", { catalogHash: first.catalogHash }),
    /Expired lock/,
  );
});
await check(
  "independent catalog rollback invalidates freshness without losing availability history",
  async () => {
    const before = await call("state");
    await call("rollback", { target: "catalog" });
    const after = await call("state");
    assert.equal(after.catalog, before.previous_catalog);
    assert.equal(after.availability, before.availability);
    assert.equal(after.checked_at, null);
    assert.equal(after.enabled, false);
    await call("rollback", { target: "catalog" });
    assert.equal((await call("state")).catalog, before.catalog);
  },
);
await check("event, staging and rate-limit retention is bounded", async () => {
  await db.exec(
    "insert into bye_schedule.events(kind,details) select 'fixture','{}'::jsonb from generate_series(1,2600);insert into bye_schedule.staging(token,kind,part,payload,created_at) values(gen_random_uuid(),'raw',0,'[]',now()-interval '31 minutes');insert into bye_schedule.limits values('expired',now()-interval '3 minutes',1)",
  );
  await call("cleanup");
  assert.equal(
    (await query("select count(*)::int n from bye_schedule.events"))[0].n,
    2500,
  );
  assert.equal(
    (await query("select count(*)::int n from bye_schedule.staging"))[0].n,
    0,
  );
  assert.equal(
    (await query(
      "select count(*)::int n from bye_schedule.limits where identity='expired'",
    ))[0].n,
    0,
  );
});
await check(
  "expired workers recover with cooldown; repeated failures trip the circuit",
  async () => {
    await db.exec(
      "update bye_schedule.state set lock_token=gen_random_uuid(),lock_until=now()-interval '1 minute',next_fetch='-infinity',failures=0",
    );
    assert.equal(
      (await call("claim", { mode: "owner" })).skipped,
      "RECOVERED_EXPIRED_WORKER",
    );
    assert.equal((await call("claim", { mode: "owner" })).skipped, "COOLDOWN");
    for (let i = 0; i < 2; i++) {
      await db.exec("update bye_schedule.state set next_fetch='-infinity'");
      const c = await call("claim", { mode: "owner" });
      await call("fail", { token: c.token, retrySeconds: 0 });
    }
    assert.equal((await call("state")).failures, 3);
    assert(
      (await query(
        "select next_fetch>now()+interval '29 minutes' cooled from bye_schedule.state",
      ))[0].cooled,
    );
  },
);
await check(
  "future retrieval times cannot publish over validated data",
  async () => {
    await db.exec("update bye_schedule.state set next_fetch='-infinity'");
    const c = await call("claim", { mode: "owner" });
    await assert.rejects(
      call("publish", {
        token: c.token,
        catalogHash: first.catalogHash,
        availabilityHash: first.availabilityHash,
        sourceHash: first.sourceHash,
        rowCount: 7,
        sectionCount: 5,
        retrievedAt: "2099-01-01T00:00:00Z",
      }),
      /Stale or future/,
    );
    await call("fail", { token: c.token });
  },
);
await db.close();
console.log(`${checks} database scenarios passed`);

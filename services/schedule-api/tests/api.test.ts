import { test } from "node:test";
import assert from "node:assert/strict";
import { api, OPENAPI } from "../src/api.ts";
import { sha } from "../src/domain.ts";
const key = "public-test-key";
const request = (path: string, extra: Record<string, string> = {}) =>
  new Request("https://api.test" + path, {
    headers: { apikey: key, ...extra },
  });
test("keys, methods, terms, paths, sizes, and availability CRNs bounded before DB", async () => {
  let calls = 0;
  const handler = api(
    {
      rpc: async () => {
        calls++;
        return { data: [], meta: {} };
      },
    },
    "test",
  );
  assert.equal(
    (await handler(new Request("https://api.test/v1/terms"))).status,
    401,
  );
  for (
    const path of [
      "/v1/terms/202630/catalog",
      "/v2/terms",
      "/v1/terms/202670/availability?crns=bad",
      "/v1/terms/202670/courses?q=" + "a".repeat(101),
    ]
  ) assert((await handler(request(path))).status >= 400);
  assert.equal(calls, 0);
});
test("stable envelopes, alias ranking and ETag/304", async () => {
  const handler = api(
    {
      rpc: async () => ({
        data: [{ key: "MATH 005B", title: "B" }, {
          key: "MATH 005A",
          title: "A",
        }],
        meta: { catalogVersion: "c1" },
      }),
    },
    "test",
  );
  const r = await handler(request("/v1/terms/202670/courses?q=math5a"));
  assert.equal(r.status, 200);
  assert.equal((await r.json()).data[0].key, "MATH 005A");
  const cached = await handler(
    request("/v1/terms/202670/courses?q=math5a", {
      "if-none-match": r.headers.get("etag")!,
    }),
  );
  assert.equal(cached.status, 304);
  assert.equal(await cached.text(), "");
});
test("gateway and function-runtime route prefixes remain compatible", async () => {
  const handler = api(
    { rpc: async () => ({ data: [], meta: {} }) },
    "test",
  );
  for (
    const prefix of ["", "/bye-schedule-api", "/functions/v1/bye-schedule-api"]
  ) assert.equal((await handler(request(prefix + "/v1/terms"))).status, 200);
});
test("rate failures, private error suppression, CORS and OpenAPI", async () => {
  const handler = api(
    { rpc: async () => ({ error: "RATE_LIMITED" }) },
    "test",
  );
  const r = await handler(request("/v1/terms"));
  assert.equal(r.status, 429);
  assert.equal(r.headers.get("retry-after"), "60");
  const failing = api(
    {
      rpc: async () => {
        throw new Error("secret password should never leak");
      },
    },
    "test",
  );
  assert(
    !await (await failing(request("/v1/terms"))).text().then((x) =>
      x.includes("password")
    ),
  );
  assert.equal(
    (await handler(new Request("https://api.test", { method: "OPTIONS" })))
      .status,
    204,
  );
  assert.equal(Object.keys(OPENAPI.paths).length, 6);
});

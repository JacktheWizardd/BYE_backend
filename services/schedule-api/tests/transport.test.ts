import { test } from "node:test";
import assert from "node:assert/strict";
import { boundedJSON } from "../src/database.ts";
import { sha } from "../src/domain.ts";
test("streamed UTF-8, exact content hashing, bounded size and cancellation", async () => {
  const raw = JSON.stringify([{
      name: "José 🌟",
      html: "<script>inert</script>",
    }]),
    bytes = new TextEncoder().encode(raw);
  let cancelled = false;
  const stream = new ReadableStream({
    start(controller) {
      for (let i = 0; i < bytes.length; i += 3) {
        controller.enqueue(bytes.slice(i, i + 3));
      }
      controller.close();
    },
    cancel() {
      cancelled = true;
    },
  });
  const r = await boundedJSON(new Response(stream));
  assert.deepEqual(r.data, JSON.parse(raw));
  assert.equal(r.rawHash, await sha(raw));
  await assert.rejects(
    boundedJSON(new Response("x".repeat(100)), 10),
    /SOURCE_TOO_LARGE/,
  );
  const oversized = new ReadableStream({
    start(c) {
      c.enqueue(new Uint8Array(11));
    },
    cancel() {
      cancelled = true;
    },
  });
  await assert.rejects(
    boundedJSON(new Response(oversized), 10),
    /SOURCE_TOO_LARGE/,
  );
  assert.equal(cancelled, true);
  await assert.rejects(boundedJSON(new Response("{broken")), /JSON/);
  await assert.rejects(
    boundedJSON(
      new Response("", { status: 429, headers: { "Retry-After": "900" } }),
    ),
    (e) => e.retryAfter === "900" && e.status === 429,
  );
});

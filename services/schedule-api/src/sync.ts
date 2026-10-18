import { boundedJSON, type Database, database } from "./database.ts";
import { JOB_TOKEN_SHA256 } from "./config.ts";
import {
  canonical,
  prepare,
  type Prepared,
  sha,
  SOURCE,
  TERMS,
  validateTerms,
} from "./domain.ts";
export async function upload(
  db: Database,
  token: string,
  p: Prepared,
  previous: { catalog: string | null; availability: string | null },
  retrievedAt: string,
  metadata: unknown,
  daily: boolean,
) {
  const call = (op: string, args: Record<string, unknown>) =>
    db.rpc("bye_schedule_backend", { op, args });
  async function stage(kind: string, records: unknown[]) {
    let part = 0, batch: unknown[] = [], bytes = 0;
    for (const record of records) {
      const n = JSON.stringify(record).length * 3;
      if (n > 1500000) throw new Error("SOURCE_RECORD_TOO_LARGE");
      if (batch.length && (batch.length >= 100 || bytes + n > 1000000)) {
        await call("stage", { token, kind, part: part++, payload: batch });
        batch = [];
        bytes = 0;
      }
      batch.push(record);
      bytes += n;
    }
    if (batch.length) {
      await call("stage", { token, kind, part, payload: batch });
    }
  }
  if (p.catalogHash !== previous.catalog) {
    await stage("courses", p.courses);
    await stage("sections", p.sections);
    await stage(
      "raw",
      p.raw.map((payload, i) => ({ ordinal: i + 1, payload })),
    );
  }
  if (p.availabilityHash !== previous.availability) {
    const old: { crn: string; value: unknown }[] = await call("values", {}),
      map = new Map(old.map((x) => [x.crn, x.value]));
    const changed = p.availability.filter((x) =>
      canonical(map.get(x.crn) ?? null) !== canonical(x.value)
    );
    const present = new Set(p.availability.map((x) => x.crn));
    for (const row of old) {
      if (!present.has(row.crn) && row.value !== null) {
        changed.push({ crn: row.crn, value: null as any, evidence: [] });
      }
    }
    await stage("availability", changed);
  }
  return call("publish", {
    token,
    catalogHash: p.catalogHash,
    availabilityHash: p.availabilityHash,
    sourceHash: p.sourceHash,
    rowCount: p.rowCount,
    sectionCount: p.sections.length,
    retrievedAt,
    metadata,
    daily,
  });
}
export function worker(
  db: Database,
  secret: string,
  request: typeof fetch = fetch,
  jobHash = "",
) {
  const call = (op: string, args: Record<string, unknown> = {}) =>
    db.rpc("bye_schedule_backend", { op, args });
  return async (req: Request): Promise<Response> => {
    const reply = (data: unknown, status = 200) =>
      new Response(JSON.stringify(data), {
        status,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });
    const job = req.headers.get("x-bye-job-token");
    if (
      (!secret || req.headers.get("Authorization") !== "Bearer " + secret) &&
      (!job || !jobHash || await sha(job) !== jobHash)
    ) return reply({ error: "UNAUTHORIZED" }, 401);
    if (req.method !== "POST") {
      return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
    }
    if (Number(req.headers.get("content-length") ?? 0) > 2048) {
      return reply({ error: "INVALID_QUERY" }, 400);
    }
    let token: string | undefined;
    try {
      let input: Record<string, unknown>;
      try {
        const parsed = req.body
          ? (await boundedJSON(new Response(req.body), 2048)).data
          : {};
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
          return reply({ error: "INVALID_QUERY" }, 400);
        }
        input = parsed as Record<string, unknown>;
      } catch {
        return reply({ error: "INVALID_QUERY" }, 400);
      }
      const action = typeof input.action === "string"
        ? input.action
        : "scheduled";
      if (["state", "cleanup", "rollback"].includes(action)) {
        return reply(
          await call(
            action,
            action === "rollback" ? { target: input.target } : {},
          ),
        );
      }
      if (action === "enable" || action === "disable") {
        return reply(await call("enable", { enabled: action === "enable" }));
      }
      if (!["scheduled", "run", "bootstrap"].includes(action)) {
        return reply({ error: "INVALID_QUERY" }, 400);
      }
      await call("cleanup");
      const claim = await call("claim", {
        mode: action === "run" ? "owner" : action,
      });
      if (!claim.token) return reply(claim);
      token = claim.token;
      const start = performance.now();
      let rows: unknown,
        metadata: unknown,
        retrievedAt: string,
        sourceHash: string | undefined;
      if (action === "bootstrap") {
        const source = await call("bootstrap_source");
        rows = source.rows;
        metadata = source.term;
        retrievedAt = source.retrievedAt;
      } else {
        const get = async (url: string, max?: number) => {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 40000);
          try {
            return await boundedJSON(
              await request(url, {
                headers: {
                  Accept: "application/json",
                  "User-Agent": "BYE-Schedule-API/1.0 (shared Fall-2026 cache)",
                },
                redirect: "error",
                signal: controller.signal,
              }),
              max,
            );
          } finally {
            clearTimeout(timer);
          }
        };
        if (claim.daily) {
          metadata = validateTerms((await get(TERMS, 1024 * 1024)).data);
        } else {
          metadata = (await call("state")).metadata;
          validateTerms([metadata]);
        }
        const source = await get(SOURCE);
        rows = source.data;
        sourceHash = source.rawHash;
        retrievedAt = new Date().toISOString();
      }
      const memory = () => {
        const runtime = (globalThis as any).Deno;
        if (!runtime?.memoryUsage) return null;
        const m = runtime.memoryUsage();
        return {
          heapBytes: m.heapUsed,
          externalBytes: m.external,
          totalBytes: m.heapUsed + m.external,
        };
      };
      const afterReadMemory = memory();
      const before = performance.now(),
        p = await prepare(rows, sourceHash),
        normalizationMs = performance.now() - before;
      const afterPrepareMemory = memory();
      const result = await upload(
        db,
        token!,
        p,
        claim,
        retrievedAt,
        metadata,
        claim.daily,
      );
      return reply({
        ...result,
        rowCount: p.rowCount,
        sectionCount: p.sections.length,
        normalizationMs: Math.round(normalizationMs),
        elapsedMs: Math.round(performance.now() - start),
        memorySamples: {
          afterRead: afterReadMemory,
          afterPrepare: afterPrepareMemory,
          afterPublish: memory(),
        },
      });
    } catch (error) {
      if (token) {
        const e = error as { retryAfter?: string; message?: string };
        const raw = e.retryAfter;
        let retrySeconds = Number(raw);
        if (raw && !Number.isFinite(retrySeconds)) {
          retrySeconds = Math.max(0, (Date.parse(raw) - Date.now()) / 1000);
        }
        await call("fail", {
          token,
          code: "SYNC_FAILED",
          retrySeconds: Number.isFinite(retrySeconds)
            ? Math.ceil(Math.min(86400, Math.max(0, retrySeconds)))
            : 0,
        }).catch(() => {});
      }
      return reply({ error: "SYNC_FAILED", previousRetained: true }, 503);
    }
  };
}
if (import.meta.main) {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  Deno.serve(
    worker(
      database(Deno.env.get("SUPABASE_URL")!, key),
      key,
      fetch,
      Deno.env.get("BYE_JOB_TOKEN_SHA256") ?? JOB_TOKEN_SHA256,
    ),
  );
}

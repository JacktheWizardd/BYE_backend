import { boundedJSON, type Database, database } from "./database.ts";
import { JOB_TOKEN_SHA256 } from "./config.ts";
import {
  canonical,
  prepare,
  type Prepared,
  sha,
  sourceURL,
  TERM,
  publishedTerms,
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
  term = TERM,
  phase: (value: string) => void = () => {},
) {
  const call = (op: string, args: Record<string, unknown>) =>
    db.rpc("bye_schedule_backend", { op, args: { ...args, term } });
  async function stage(kind: string, records: unknown[]) {
    phase("STAGING_FAILED");
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
  phase("PUBLICATION_FAILED");
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
    let term = TERM, phase = "DATABASE_FAILED", discovery = false;
    let sourceStatus: number | undefined;
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
      if (["owner-add", "owner-remove"].includes(action)) {
        if (typeof input.userId !== "string" || !/^[a-f0-9-]{36}$/i.test(input.userId)) return reply({error:"INVALID_QUERY"},400);
        const result = await call(action, {userId: input.userId});
        return reply(result, result.error ? 400 : 200);
      }
      if (action === "term-dates") {
        if (typeof input.term !== "string" || !/^\d{6}$/.test(input.term) || typeof input.reference !== "string" || !/^https:\/\/([a-zA-Z0-9-]+\.)*pasadena\.edu\//.test(input.reference)) return reply({error:"INVALID_QUERY"},400);
        return reply(await call(action,{term:input.term,reference:input.reference,startDate:input.startDate,endDate:input.endDate}));
      }
      if (["state", "cleanup", "rollback"].includes(action)) {
        return reply(
          await call(
            action,
            {...(input.term ? {term:input.term} : {}), ...(action === "rollback" ? {target:input.target} : {})},
          ),
        );
      }
      if (action === "enable" || action === "disable") {
        return reply(await call("enable", { enabled: action === "enable", ...(input.term ? {term:input.term} : {}) }));
      }
      if (!["scheduled", "run", "bootstrap"].includes(action)) {
        return reply({ error: "INVALID_QUERY" }, 400);
      }
      if (input.term !== undefined && (typeof input.term !== "string" || !/^\d{6}$/.test(input.term))) return reply({error:"INVALID_QUERY"},400);
      term = typeof input.term === "string" ? input.term : TERM;
      const get = async (url: string, max?: number) => {
        phase = "SOURCE_FETCH_FAILED";
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 40000);
        try {
          const response = await request(url, {headers: {Accept:"application/json", "User-Agent":"BYE-Schedule-API/1.1 (shared schedule cache)"},redirect:"error",signal:controller.signal});
          sourceStatus = response.status;
          if (response.ok) phase = "SOURCE_DECODE_FAILED";
          return await boundedJSON(response,max);
        } finally { clearTimeout(timer); }
      };
      await call("cleanup");
      if (action === "scheduled") {
        const claim = await call("discover-claim");
        if (claim.token) {
          discovery = true; token = claim.token;
          const source = await get(TERMS,1024*1024);
          phase = "TERMS_VALIDATION_FAILED";
          const terms = publishedTerms(source.data);
          phase = "DISCOVERY_PUBLICATION_FAILED";
          return reply(await call("discover-publish",{token,terms}));
        }
      }
      const claim = await call("claim", {
        mode: action === "run" ? "owner" : action,
        ...(action !== "scheduled" || input.term ? {term} : {}),
      });
      if (!claim.token) return reply(claim);
      token = claim.token;
      term = claim.term ?? term;
      const start = performance.now();
      let rows: unknown,
        metadata: unknown,
        retrievedAt: string,
        sourceHash: string | undefined;
      if (action === "bootstrap") {
        const source = await call("bootstrap_source", {term});
        rows = source.rows;
        metadata = source.term;
        retrievedAt = source.retrievedAt;
      } else {
        metadata = claim.metadata ?? (await call("state",{term})).metadata;
        phase = "TERMS_VALIDATION_FAILED";
        validateTerms([metadata],term);
        const source = await get(sourceURL(term));
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
      phase = "SCHEDULE_VALIDATION_FAILED";
      const afterReadMemory = memory();
      const before = performance.now(),
        p = await prepare(rows, sourceHash, term),
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
        term,
        value => { phase = value; },
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
        await call(discovery ? "discover-fail" : "fail", {
          term,
          token,
          code: phase,
          sourceStatus,
          retrySeconds: Number.isFinite(retrySeconds)
            ? Math.ceil(Math.min(86400, Math.max(0, retrySeconds)))
            : 0,
        }).catch(() => {});
      }
      return reply({ error: "SYNC_FAILED", diagnosticCode: phase, sourceStatus, previousRetained: true }, 503);
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

import { type Database, database } from "./database.ts";
import { OPENAPI } from "./contract.ts";
import { type Course, search, sha, TERM } from "./domain.ts";
const errors: Record<string, number> = {
  UNAUTHORIZED: 401,
  INVALID_QUERY: 400,
  UNSUPPORTED_TERM: 404,
  NOT_FOUND: 404,
  RATE_LIMITED: 429,
  NOT_READY: 503,
  DATABASE_UNAVAILABLE: 503,
};
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "apikey, if-none-match, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Expose-Headers": "ETag, Retry-After, X-Content-Type-Options",
};
export function api(db: Database, salt: string) {
  return async (req: Request): Promise<Response> => {
    const headers: Record<string, string> = {
      ...cors,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    };
    const fail = (code: string) =>
      new Response(
        JSON.stringify({
          error: {
            code,
            message: code.replaceAll("_", " ").toLowerCase(),
            retryable: ["RATE_LIMITED", "NOT_READY", "DATABASE_UNAVAILABLE"]
              .includes(code),
          },
        }),
        {
          status: errors[code] ?? 400,
          headers: {
            ...headers,
            ...(code === "RATE_LIMITED" ? { "Retry-After": "60" } : {}),
          },
        },
      );
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers });
    }
    if (req.method !== "GET") {
      return new Response(null, {
        status: 405,
        headers: { ...headers, Allow: "GET, OPTIONS" },
      });
    }
    if (req.url.length > 2048) return fail("INVALID_QUERY");
    const key = req.headers.get("apikey") ?? "";
    if (!key || key.length > 2048) {
      return fail("UNAUTHORIZED");
    }
    try {
      const url = new URL(req.url),
        path = url.pathname.replace(
          /^(?:\/functions\/v1)?\/bye-schedule-api(?=\/|$)/,
          "",
        );
      const parts = path.split("/").filter(Boolean);
      let route: string,
        term: string | undefined,
        courseKey: string | undefined,
        crns: string[] | undefined;
      if (path === "/v1/openapi.json") route = "openapi";
      else if (path === "/v1/terms") route = "terms";
      else if (parts[0] === "v1" && parts[1] === "terms" && parts.length >= 4) {
        term = parts[2];
        if (term !== TERM) return fail("UNSUPPORTED_TERM");
        route = parts[3];
        if (
          route === "courses" && parts.length === 6 && parts[5] === "sections"
        ) {
          route = "sections";
          courseKey = decodeURIComponent(parts[4]);
          if (courseKey.length > 150) return fail("INVALID_QUERY");
        } else if (
          parts.length !== 4 ||
          !["manifest", "catalog", "courses", "availability"].includes(route)
        ) return fail("NOT_FOUND");
        if (
          route === "courses" &&
          (!url.searchParams.get("q")?.trim() ||
            url.searchParams.get("q")!.length > 100)
        ) return fail("INVALID_QUERY");
        if (route === "availability") {
          crns = [...new Set((url.searchParams.get("crns") ?? "").split(","))];
          if (
            !crns.length || crns.length > 100 ||
            crns.some((c) => !/^\d{5}$/.test(c))
          ) return fail("INVALID_QUERY");
        }
      } else return fail("NOT_FOUND");
      const identity = await sha(
        salt + "|" +
          (req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
            req.headers.get("x-real-ip") || "unknown"),
      );
      const body = await db.rpc("bye_schedule_backend", {
        op: "read",
        args: { route, term, courseKey, crns, identity, keyDigest: await sha(key) },
      });
      if (body.error) return fail(body.error);
      if (route === "openapi") return new Response(JSON.stringify(OPENAPI), { headers });
      if (route === "courses") {
        body.data = search(body.data as Course[], url.searchParams.get("q")!);
      }
      if (route !== "manifest" && route !== "terms") {
        const etag = '"' + await sha(JSON.stringify(body)) + '"';
        headers.ETag = etag;
        headers["Cache-Control"] = "private, no-cache";
        if (
          (req.headers.get("if-none-match") ?? "").split(",").some((v) =>
            v.trim().replace(/^W\//, "") === etag || v.trim() === "*"
          )
        ) return new Response(null, { status: 304, headers });
      }
      return new Response(JSON.stringify(body), { headers });
    } catch {
      return fail("DATABASE_UNAVAILABLE");
    }
  };
}
// Schema source is dependency-free and shared with the exported specification.
export { OPENAPI } from "./contract.ts";
if (import.meta.main) {
  const url = Deno.env.get("SUPABASE_URL")!,
    key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  Deno.serve(
    api(
      database(url, key),
      key,
    ),
  );
}

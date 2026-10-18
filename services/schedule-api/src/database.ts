import { createHash } from "node:crypto";
export interface Database {
  rpc(name: string, args?: Record<string, unknown>): Promise<any>;
}
export function database(url: string, key: string, token: string = key): Database {
  return {
    async rpc(name, args = {}) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 45000);
      try {
        const response = await fetch(url + "/rest/v1/rpc/" + name, {
          method: "POST",
          headers: {
            apikey: key,
            Authorization: "Bearer " + token,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(args),
          signal: controller.signal,
        });
        if (!response.ok) {
          await response.body?.cancel();
          throw new Error("DATABASE_UNAVAILABLE");
        }
        return await response.json();
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
export async function boundedJSON(
  response: Response,
  max = 32 * 1024 * 1024,
): Promise<{ data: unknown; rawHash: string }> {
  if (!response.ok || !response.body) {
    await response.body?.cancel();
    throw Object.assign(new Error("SOURCE_UNAVAILABLE"), {
      retryAfter: response.headers.get("Retry-After"),
      status: response.status,
    });
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const hash = createHash("sha256");
  let size = 0, raw = "";
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > max) throw new Error("SOURCE_TOO_LARGE");
      // A small Edge HTTP chunk may retain a much larger backing buffer.
      // Decode and hash immediately instead of retaining the byte views.
      hash.update(value);
      raw += decoder.decode(value, { stream: true });
    }
  } finally {
    await reader.cancel().catch(() => {});
  }
  raw += decoder.decode();
  return { data: JSON.parse(raw), rawHash: hash.digest("hex") };
}

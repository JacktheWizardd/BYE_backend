import { readFileSync } from "node:fs";
import { prepare } from "../src/domain.ts";
const path = process.argv[2] ??
  "../../.local-docs/pcc-schedule/fall-2026/source.json";
const before = process.cpuUsage(),
  start = performance.now(),
  raw = readFileSync(path, "utf8");
const result = await prepare(JSON.parse(raw));
const cpu = process.cpuUsage(before), memory = process.memoryUsage();
console.log(JSON.stringify(
  {
    rows: result.rowCount,
    sections: result.sections.length,
    courses: result.courses.length,
    catalogHash: result.catalogHash,
    availabilityHash: result.availabilityHash,
    wallMs: Math.round(performance.now() - start),
    cpuMs: Math.round((cpu.user + cpu.system) / 1000),
    rssMiB: Math.round(memory.rss / 1024 / 1024),
    heapMiB: Math.round(memory.heapUsed / 1024 / 1024),
  },
  null,
  2,
));
if ((cpu.user + cpu.system) / 1000 > 1400 || memory.rss > 220 * 1024 * 1024) {
  process.exitCode = 1;
}

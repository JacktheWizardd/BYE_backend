import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { prepare, search, validateTerms } from "../src/domain.ts";
const fixture = JSON.parse(
  readFileSync(new URL("./fixtures/fall-2026.json", import.meta.url), "utf8"),
);
test("complete source, meetings, private instructors, source HTML and independent status", async () => {
  const p = await prepare(fixture.rows);
  assert.equal(p.rowCount, fixture.rows.length);
  assert(p.sections.length > 0);
  assert(!JSON.stringify(p.sections).includes("pfaEmail"));
  assert(!JSON.stringify(p.sections).includes("@"));
  const c = p.availability.find((x) =>
    x.value.statusCode === "C" && Number(x.value.seatsAvailable) > 0
  );
  assert(c);
  assert(p.sections.some((x) => x.body.notesFormat === "source-html-inert"));
});
test("aliases preserve suffixes and CCN", () => {
  const items = [
    "MATH 005A",
    "MATH 005B",
    "MATH 005AH",
    "MATH 005AL",
    "ENGL C1000H",
  ].map((key) => ({
    key,
    subject: key.split(" ")[0],
    number: key.split(" ")[1],
    title: "Course",
  }));
  for (const q of ["MATH 005A", "math 005a", "math 5a", "MATH5A"]) {
    assert.equal(search(items, q)[0].key, "MATH 005A");
  }
  assert.equal(search(items, "MATH 005AH")[0].key, "MATH 005AH");
  assert.equal(search(items, "ENGLC1000H")[0].key, "ENGL C1000H");
  assert.equal(search(items, "MATH 005").length, 4);
});
test("seat changes leave catalog stable; reordering is idempotent", async () => {
  const first = await prepare(fixture.rows),
    reordered = await prepare([...fixture.rows].reverse());
  assert.equal(first.catalogHash, reordered.catalogHash);
  assert.equal(first.availabilityHash, reordered.availabilityHash);
  const rows = structuredClone(fixture.rows);
  for (const r of rows) if (r.crn === rows[0].crn) r.seatsAvail = "99";
  const changed = await prepare(rows);
  assert.equal(first.catalogHash, changed.catalogHash);
  assert.notEqual(first.availabilityHash, changed.availabilityHash);
  rows[0].unfamiliarField = "preserved";
  assert.notEqual(first.catalogHash, (await prepare(rows)).catalogHash);
});
test("malformed, conflicting counts, identities and dates fail complete import", async () => {
  await assert.rejects(prepare([]));
  await assert.rejects(prepare([{ termCode: "202630" }]));
  const r = structuredClone(fixture.rows[0]);
  await assert.rejects(prepare([r, { ...r, seatsAvail: "999" }]));
  await assert.rejects(prepare([{ ...r, enrl: "NaN" }]));
  await assert.rejects(prepare([{ ...r, ptrmStartDate: "2026-02-31" }]));
});
test("published requested term wins over defaultTerm", () => {
  assert.equal(
    validateTerms([{
      termCode: "202670",
      termDisplayControl: "Y",
      termName: "Fall 2026",
      defaultTerm: "202630",
    }]).termCode,
    "202670",
  );
  assert.throws(() =>
    validateTerms([{
      termCode: "202630",
      termDisplayControl: "Y",
      termName: "Spring",
    }])
  );
});

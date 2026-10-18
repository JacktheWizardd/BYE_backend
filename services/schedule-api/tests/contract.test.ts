import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { OPENAPI } from "../src/contract.ts";
test("published OpenAPI matches the deployed contract source and preserves v1 reader fields", () => {
  assert.deepEqual(
    JSON.parse(
      readFileSync(new URL("../openapi.json", import.meta.url), "utf8"),
    ),
    OPENAPI,
  );
  assert.equal(OPENAPI.info.version, "1.0.0");
  const schema = OPENAPI.components.schemas as any;
  for (const field of ["key", "subject", "number", "title"]) {
    assert(schema.Course.required.includes(field));
  }
  for (
    const field of [
      "crn",
      "courseKey",
      "meetings",
      "instructors",
      "availability",
    ]
  ) assert(schema.Section.required.includes(field));
  assert(schema.Availability.required.includes("statusCode"));
  assert(schema.Availability.required.includes("seatsAvailable"));
  const oldReader = (body: any) =>
    body.data.map((c: any) => ({ key: c.key, title: c.title }));
  assert.deepEqual(
    oldReader({
      data: [{
        key: "MATH 005A",
        title: "Calculus",
        futureAdditiveField: true,
      }],
      meta: { catalogVersion: "v1", futureCapability: true },
    }),
    [{ key: "MATH 005A", title: "Calculus" }],
  );
});

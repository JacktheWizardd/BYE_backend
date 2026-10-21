import { createHash } from "node:crypto";
export const TERM = "202670";
export const sourceURL = (term: string) => {
  if (!/^\d{6}$/.test(term)) throw new Error("INVALID_TERM");
  return "https://prod-apiweb.pasadena.edu/api/classSchedule/" + term;
};
export const SOURCE = "https://prod-apiweb.pasadena.edu/api/classSchedule/" +
  TERM;
export const TERMS =
  "https://prod-apiweb.pasadena.edu/api/getClassScheduleTerms";
export const COUNTS: Record<string, string> = {
  enrl: "enrolled",
  maxEnrl: "capacity",
  seatsAvail: "seatsAvailable",
  waitCount: "waitlistCount",
  waitCapacity: "waitlistCapacity",
  waitAvail: "waitlistAvailable",
};
const DYNAMIC = new Set([...Object.keys(COUNTS), "fwSectOpenInd"]);
const DAYS = [
  "monDay",
  "tueDay",
  "wedDay",
  "thuDay",
  "friDay",
  "satDay",
  "sunDay",
];
const MEETING = [
  "ptrmStartDate",
  "ptrmEndDate",
  "ptrmCode",
  "ptrmDesc",
  "ptrmCatagory",
  "beginTime",
  "endTime",
  "schdCode",
  "schdDesc",
  "ssrmeetMtypCode",
  "ssrmeetSchdCode",
  "campCode",
  "campDesc",
  "bldgDesc",
  "stvbldgDesc",
  "bldgAddress",
  "roomCode",
  "weeklyHrs",
  "sessCode",
  "sessDesc",
  ...DAYS,
];
export type Row = Record<string, unknown>;
export type Course = {
  key: string;
  subject: string;
  number: string;
  title: string;
};
export type Definition = {
  crn: string;
  courseKey: string;
  body: Record<string, unknown>;
};
export type Availability = { crn: string; value: Row; evidence: Row[] };
export type Prepared = {
  catalogHash: string;
  availabilityHash: string;
  sourceHash: string;
  rowCount: number;
  courses: Course[];
  sections: Definition[];
  availability: Availability[];
  raw: Row[];
};
export function canonical(value: unknown): string {
  if (value === null || typeof value !== "object") {
    if (typeof value === "number" && !Number.isFinite(value)) {
      throw new Error("Invalid JSON number");
    }
    const result = JSON.stringify(value);
    if (result === undefined) throw new Error("Invalid JSON");
    return result;
  }
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  return "{" +
    Object.keys(value).sort().map((k) =>
      JSON.stringify(k) + ":" + canonical((value as Row)[k])
    ).join(",") + "}";
}
export async function sha(value: string): Promise<string> {
  return createHash("sha256").update(value).digest("hex");
}
const str = (v: unknown): string => v == null ? "" : String(v).trim();
function unique(rows: Row[], field: string): unknown[] {
  return [
    ...new Set(rows.filter((r) => field in r).map((r) => canonical(r[field]))),
  ].sort().map((v) => JSON.parse(v));
}
function scalar(rows: Row[], field: string): string | null {
  const values = [...new Set(rows.map((r) => str(r[field])).filter(Boolean))];
  if (values.length > 1) throw new Error("Conflicting section field: " + field);
  return values[0] ?? null;
}
function count(value: string | null): number | null {
  if (value === null) return null;
  if (
    !/^[+-]?\d+$/.test(value) || !Number.isSafeInteger(Number(value)) ||
    Number(value) < -2147483648 || Number(value) > 2147483647
  ) throw new Error("Invalid count");
  return Number(value);
}
function date(value: unknown): string | null {
  if (!str(value)) return null;
  const d = str(value).slice(0, 10);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(d) || !Number.isFinite(Date.parse(d)) ||
    new Date(d).toISOString().slice(0, 10) !== d
  ) throw new Error("Invalid meeting date");
  return d;
}
export function publishedTerms(data: unknown): Row[] {
  if (!Array.isArray(data) || data.length > 100) throw new Error("Malformed terms");
  const terms = data.filter(t => t && t.termDisplayControl === "Y");
  const seen = new Set<string>();
  for (const t of terms) {
    if (!/^\d{6}$/.test(t.termCode) || typeof t.termName !== "string" || !t.termName.trim() || t.termName.length > 100 || seen.has(t.termCode)) throw new Error("Malformed terms");
    seen.add(t.termCode);
  }
  if (!terms.length || terms.length > 32) throw new Error("Malformed terms");
  return terms.map(t => ({ termCode: t.termCode, termName: t.termName, termDisplayControl: "Y" }));
}
export function validateTerms(data: unknown, term = TERM): Row {
  if (!Array.isArray(data)) throw new Error("Malformed terms");
  const found = data.filter((t) =>
    t && t.termCode === term && t.termDisplayControl === "Y"
  );
  if (found.length !== 1 || !str(found[0].termName)) {
    throw new Error("Requested term is not published");
  }
  return found[0]; // defaultTerm intentionally does not participate.
}
export async function prepare(
  input: unknown,
  sourceHash?: string,
  term = TERM,
): Promise<Prepared> {
  if (!Array.isArray(input) || !input.length || input.length > 25000) {
    throw new Error("Malformed schedule");
  }
  const rows = input as Row[],
    groups = new Map<string, Row[]>(),
    courses = new Map<string, Course>(),
    signatures: string[] = [];
  const sourceHasher = createHash("sha256").update("[");
  for (const row of rows) {
    if (
      !row || typeof row !== "object" || Array.isArray(row) ||
      row.termCode !== term || !/^\d{5}$/.test(String(row.crn))
    ) throw new Error("Invalid section identity");
    for (const key of ["subjCode", "courseNumbDisplay", "crn"]) {
      if (
        typeof row[key] !== "string" || !str(row[key]) ||
        row[key] !== str(row[key]) || str(row[key]).length > 100 ||
        /[\u0000-\u001f]/.test(str(row[key]))
      ) throw new Error("Noncanonical identity");
    }
    const key = row.subjCode + " " + row.courseNumbDisplay;
    const course = {
      key,
      subject: str(row.subjCode),
      number: str(row.courseNumbDisplay),
      title: str(row.courseTitle),
    };
    if (
      !courses.has(key) ||
      course.title.localeCompare(courses.get(key)!.title) < 0
    ) courses.set(key, course);
    const crn = str(row.crn);
    if (!groups.has(crn)) groups.set(crn, []);
    groups.get(crn)!.push(row);
    if (!sourceHash) {
      if (signatures.length) sourceHasher.update(",");
      sourceHasher.update(canonical(row));
    }
    signatures.push(
      canonical(Object.fromEntries(
        Object.entries(row).filter(([k]) => !DYNAMIC.has(k)),
      )),
    );
  }
  const sections: Definition[] = [], availability: Availability[] = [];
  for (
    const [crn, records] of [...groups].sort(([a], [b]) => a.localeCompare(b))
  ) {
    const identities = new Set(
      records.map((r) => r.subjCode + " " + r.courseNumbDisplay),
    );
    if (identities.size !== 1) throw new Error("Conflicting CRN course");
    const courseKey = [...identities][0],
      meetings = new Map<string, Row>(),
      assignments = new Map<string, Row>();
    for (const row of records) {
      const fields = Object.fromEntries(
        MEETING.filter((k) => k in row).map((k) => [k, row[k]]),
      );
      const start = date(row.ptrmStartDate), end = date(row.ptrmEndDate);
      if (start && end && start > end) {
        throw new Error("Reversed meeting dates");
      }
      meetings.set(canonical(fields), {
        startDate: start,
        endDate: end,
        days: DAYS.filter((k) => str(row[k])).map((k) => k.slice(0, 3)),
        beginTime: str(row.beginTime) || null,
        endTime: str(row.endTime) || null,
        formatCode: str(row.schdCode) || null,
        formatDescription: str(row.schdDesc) || null,
        campus: str(row.campDesc) || null,
        building: str(row.stvbldgDesc) || str(row.bldgDesc) || null,
        room: str(row.roomCode) || null,
        sourceFields: fields,
      });
      for (
        const [role, n, e] of [["primary", "pfaName", "pfaEmail"], [
          "secondary",
          "sfaName",
          "sfaEmail",
        ]]
      ) {
        if (role === "secondary" && !str(row[n]) && !str(row[e])) continue;
        // Email distinguishes source assignments privately; never return it or a reversible identifier.
        const identity = canonical([role, row[n] ?? null, row[e] ?? null]);
        assignments.set(identity, { role, name: str(row[n]) || null });
      }
    }
    const information: Row = {};
    for (
      const key of [
        "description",
        "sectionFootnotes",
        "sectionNote",
        "attrchrts",
        "crossListGroup",
        "cohortDesc",
        "censusDate",
        "dropNoWDate",
        "dropWDate",
        "grademodeDate",
        "lastDateToEnroll",
        "refundDate",
        "ftyps",
        "saprCode",
        "saprDesc",
        "workload",
        "division",
      ]
    ) {
      const values = unique(records, key);
      if (values.length) information[key] = values;
    }
    const value: Row = { statusCode: scalar(records, "fwSectOpenInd") };
    for (const [field, target] of Object.entries(COUNTS)) {
      value[target] = count(scalar(records, field));
    }
    sections.push({
      crn,
      courseKey,
      body: {
        crn,
        courseKey,
        units: scalar(records, "creditHrLow"),
        information,
        notesFormat: "source-html-inert",
        meetings: [...meetings].sort(([a], [b]) => a.localeCompare(b)).map((
          [, v],
        ) => v),
        instructors: await Promise.all(
          [...assignments].sort(([a], [b]) => a.localeCompare(b)).map(async (
            [id, v],
          ) => ({ ...v, assignmentId: await sha(crn + id) })),
        ),
      },
    });
    availability.push({ crn, value, evidence: records });
  }
  const catalogHasher = createHash("sha256").update("[");
  let first = true;
  for (const signature of signatures.sort()) {
    if (!first) catalogHasher.update(",");
    first = false;
    catalogHasher.update(JSON.stringify(signature));
  }
  const catalogHash = catalogHasher.update("]").digest("hex");
  signatures.length = 0;
  const availabilityHash = await sha(
    canonical(availability.map(({ crn, value }) => ({ crn, value }))),
  );
  return {
    catalogHash,
    availabilityHash,
    sourceHash: sourceHash ?? sourceHasher.update("]").digest("hex"),
    rowCount: rows.length,
    courses: [...courses.values()].sort((a, b) => a.key.localeCompare(b.key)),
    sections,
    availability,
    raw: rows,
  };
}
export function search(courses: Course[], query: string): Course[] {
  const normalized = (v: string) =>
    v.toUpperCase().replace(/\s+/g, "").replace(/^([A-Z]+)0+(?=\d)/, "$1");
  const q = normalized(query.trim());
  if (!q) return [];
  const ranked = courses.map((c) => {
    const key = normalized(c.key);
    return {
      c,
      rank: key === q
        ? 0
        : key.startsWith(q)
        ? 1
        : key.includes(q)
        ? 2
        : c.title.toUpperCase().includes(query.toUpperCase().trim())
        ? 3
        : 4,
    };
  });
  return ranked.filter((x) => x.rank < 4).sort((a, b) =>
    a.rank - b.rank || a.c.key.localeCompare(b.c.key)
  ).slice(0, 20).map((x) => x.c);
}

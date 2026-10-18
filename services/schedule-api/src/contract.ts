import { TERM } from "./domain.ts";
const text = { type: "string" },
  nullableText = { type: ["string", "null"] },
  count = { type: ["integer", "null"] };
const object = (
  properties: Record<string, unknown>,
  required = Object.keys(properties),
) => ({ type: "object", required, properties });
const ref = (name: string) => ({ $ref: "#/components/schemas/" + name });
const array = (items: unknown) => ({ type: "array", items });
const definitions: Record<string, unknown> = {
  Course: object({ key: text, subject: text, number: text, title: text }),
  Term: object({ termCode: { type: "string", enum: [TERM] }, name: text }),
  Availability: object({
    statusCode: nullableText,
    enrolled: count,
    capacity: count,
    seatsAvailable: count,
    waitlistCount: count,
    waitlistCapacity: count,
    waitlistAvailable: count,
  }),
  Meeting: object({
    startDate: { ...nullableText, format: "date" },
    endDate: { ...nullableText, format: "date" },
    days: array(text),
    beginTime: nullableText,
    endTime: nullableText,
    formatCode: nullableText,
    formatDescription: nullableText,
    campus: nullableText,
    building: nullableText,
    room: nullableText,
    sourceFields: {
      type: "object",
      description: "Allowlisted PCC meeting fields, retained as data.",
    },
  }),
  Instructor: object({
    assignmentId: text,
    role: { type: "string", enum: ["primary", "secondary"] },
    name: nullableText,
  }),
  Section: object({
    crn: { type: "string", pattern: "^[0-9]{5}$" },
    courseKey: text,
    units: nullableText,
    information: {
      type: "object",
      description:
        "PCC notes, prerequisites, restrictions, deadlines and attributes. HTML is inert data: render as text or sanitize before display.",
    },
    notesFormat: { const: "source-html-inert" },
    meetings: array(ref("Meeting")),
    instructors: array(ref("Instructor")),
    availability: { anyOf: [ref("Availability"), { type: "null" }] },
  }),
  AvailabilityItem: object({
    crn: { type: "string", pattern: "^[0-9]{5}$" },
    availability: { anyOf: [ref("Availability"), { type: "null" }] },
  }),
  Metadata: object({
    term: text,
    catalogVersion: text,
    availabilityVersion: text,
    sourceCheckedAt: { ...nullableText, format: "date-time" },
    availabilityChangedAt: { ...nullableText, format: "date-time" },
    stale: { type: "boolean" },
    source: text,
    collectionTargetSeconds: { const: 300 },
  }),
  CatalogMetadata: object({
    term: text,
    catalogVersion: text,
    catalogPublishedAt: { type: "string", format: "date-time" },
  }),
  Manifest: object({
    apiVersion: { const: "v1" },
    catalogVersion: text,
    availabilityVersion: text,
    sourceCheckedAt: { ...nullableText, format: "date-time" },
    availabilityChangedAt: { ...nullableText, format: "date-time" },
    stale: { type: "boolean" },
    capabilities: object({
      conditionalReads: { const: true },
      maxAvailabilityCrns: { const: 100 },
      suggestionLimit: { const: 20 },
      clientPollSeconds: { const: 60 },
    }),
  }),
  Error: object({
    error: object({
      code: {
        type: "string",
        enum: [
          "UNAUTHORIZED",
          "INVALID_QUERY",
          "UNSUPPORTED_TERM",
          "NOT_FOUND",
          "RATE_LIMITED",
          "NOT_READY",
          "DATABASE_UNAVAILABLE",
        ],
      },
      message: text,
      retryable: { type: "boolean" },
    }),
  }),
};
const routes = [
  ["/v1/terms", "listTerms", array(ref("Term")), "Metadata"],
  ["/v1/terms/{term}/manifest", "getManifest", ref("Manifest"), "Metadata"],
  [
    "/v1/terms/{term}/catalog",
    "getCatalog",
    array(ref("Course")),
    "CatalogMetadata",
  ],
  [
    "/v1/terms/{term}/courses",
    "searchCourses",
    array(ref("Course")),
    "CatalogMetadata",
  ],
  [
    "/v1/terms/{term}/courses/{courseKey}/sections",
    "getSections",
    array(ref("Section")),
    "Metadata",
  ],
  [
    "/v1/terms/{term}/availability",
    "getAvailability",
    array(ref("AvailabilityItem")),
    "Metadata",
  ],
] as const;
export const OPENAPI = {
  openapi: "3.1.0",
  info: {
    title: "BYE schedule API",
    version: "1.0.0",
    description:
      "Independent read-only PCC schedule API. v1 changes are additive; breaking changes require v2 while v1 remains available. Unknown counts remain null. PCC status is independent of seats. Availability is observed, not a registration guarantee. Source HTML must remain inert. Stale availability is null after 15 minutes.",
  },
  servers: [{
    url:
      "https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api",
  }],
  security: [{ ClientKey: [] }],
  components: {
    securitySchemes: {
      ClientKey: {
        type: "apiKey",
        in: "header",
        name: "apikey",
        description:
          "Public app identification, not a secret or a student identity.",
      },
    },
    schemas: definitions,
  },
  paths: Object.fromEntries(
    routes.map((
      [path, id, data, metadata],
    ) => [path, {
      get: {
        operationId: id,
        summary: id,
        parameters: [
          ...(path.includes("{term}")
            ? [{
              name: "term",
              in: "path",
              required: true,
              schema: { type: "string", enum: [TERM] },
            }]
            : []),
          ...(path.includes("{courseKey}")
            ? [{
              name: "courseKey",
              in: "path",
              required: true,
              schema: text,
              example: "MATH 005A",
              description:
                "URL-encode the complete official course key; preserve prefixes, zeros and all suffix letters.",
            }]
            : []),
          ...(id === "searchCourses"
            ? [{
              name: "q",
              in: "query",
              required: true,
              schema: { type: "string", minLength: 1, maxLength: 100 },
              description:
                "Maximum 20 results; exact official/normalized match first. All supported spelling variants preserve suffix distinctions.",
            }]
            : []),
          ...(id === "getAvailability"
            ? [{
              name: "crns",
              in: "query",
              required: true,
              schema: text,
              description:
                "Comma-separated five-digit CRNs, maximum 100 unique values. Unknown CRNs return 404.",
            }]
            : []),
          ...(!["listTerms", "getManifest"].includes(id)
            ? [{ name: "If-None-Match", in: "header", schema: text }]
            : []),
        ],
        responses: {
          "200": {
            description: "Successful read",
            headers: {
              ETag: {
                schema: text,
                description:
                  "Representation validator for catalog, search, sections and availability. Revalidate; do not cache errors.",
              },
            },
            content: {
              "application/json": {
                schema: object({ data, meta: ref(metadata) }),
              },
            },
          },
          ...(!["listTerms", "getManifest"].includes(id)
            ? {
              "304": {
                description: "Unchanged; retain the cached representation.",
              },
            }
            : {}),
          ...Object.fromEntries([400, 401, 404, 429, 503].map((code) => [code, {
            description: code === 429
              ? "Rate limited. Retry-After is seconds."
              : "Request error",
            headers: code === 429
              ? {
                "Retry-After": {
                  schema: { type: "integer" },
                  description: "Seconds until retry.",
                },
              }
              : {},
            content: { "application/json": { schema: ref("Error") } },
          }])),
        },
      },
    }]),
  ),
};

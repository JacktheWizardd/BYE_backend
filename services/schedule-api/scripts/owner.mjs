const action = process.argv[2] === "rollback-catalog"
  ? "rollback"
  : process.argv[2] ?? "state";
if (
  !["state", "run", "bootstrap", "cleanup", "rollback", "enable", "disable", "owner-add", "owner-remove", "term-dates"]
    .includes(action)
) {
  throw Error(
    "Use state, run, bootstrap, cleanup, rollback, enable, disable, owner-add UUID, owner-remove UUID, or term-dates START END OFFICIAL_URL (BYE_TERM selects the semester)",
  );
}
if (!process.env.BYE_SERVER_KEY && !process.env.BYE_JOB_TOKEN) {
  throw Error(
    "Set BYE_JOB_TOKEN (Vault) or BYE_SERVER_KEY in a server-side shell; never distribute these credentials.",
  );
}
const url = (process.env.BYE_API_URL ??
  "https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api")
  .replace(/bye-schedule-api\/?$/, "bye-schedule-sync");
const response = await fetch(url, {
  method: "POST",
  headers: {
    ...(process.env.BYE_JOB_TOKEN
      ? { "x-bye-job-token": process.env.BYE_JOB_TOKEN }
      : { Authorization: "Bearer " + process.env.BYE_SERVER_KEY }),
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    action,
    ...(process.env.BYE_TERM ? {term:process.env.BYE_TERM} : {}),
    ...(action === 'term-dates' ? {startDate:process.argv[3],endDate:process.argv[4],reference:process.argv[5]} : {}),
    ...(["owner-add","owner-remove"].includes(action)?{userId:process.argv[3]}:{}),
    ...(process.argv[2] === "rollback-catalog" ? { target: "catalog" } : {}),
  }),
  signal: AbortSignal.timeout(150000),
});
const result = await response.json();
console.log(JSON.stringify(result, null, 2));
if (!response.ok) process.exitCode = 1;

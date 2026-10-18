// Independent backend deploy. No client build, website code, or app dependencies.
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const key = process.env.BYE_PUBLISHABLE_KEY;
if (
  !key || !(/^(sb_publishable_[a-zA-Z0-9_-]+|eyJ[a-zA-Z0-9_.-]+)$/.test(key))
) {
  throw Error(
    "Set BYE_PUBLISHABLE_KEY to a publishable key (never a server secret).",
  );
}
const jobHash = process.env.BYE_JOB_TOKEN_SHA256 ?? "";
if (jobHash && !/^[a-f0-9]{64}$/.test(jobHash)) {
  throw Error("Invalid job digest");
}
const files = await Promise.all(
  (await readdir(path.join(root, "src"))).filter((f) => f.endsWith(".ts")).map(
    async (name) => ({
      name,
      content: (await readFile(path.join(root, "src", name), "utf8")).replace(
        "__AUTH_PUBLISHABLE_KEY__",
        key,
      ).replace("__JOB_TOKEN_SHA256__", jobHash),
    }),
  ),
);
const migrations = await readdir(path.join(root, "supabase/migrations"));
const functions = ["api", "sync", "admin"].map((kind) => ({
  name: kind === "admin" ? "bye-key-admin" : "bye-schedule-"+kind,
  entrypoint_path: "index.ts",
  verify_jwt: false,
  files: [...files.filter((f) => f.name !== kind + ".ts"), {
    name: "index.ts",
    content: files.find((f) => f.name === kind + ".ts").content,
  }],
}));
if (process.argv.includes("--manifest")) {
  console.log(
    JSON.stringify({
      functions,
      migration: await readFile(
        path.join(
          root,
          "supabase/migrations",
          migrations.find((f) => f.endsWith(".sql")),
        ),
        "utf8",
      ),
    }),
  );
} else {
  const dir = path.join(root, ".deploy");
  await mkdir(path.join(dir, "supabase"), { recursive: true });
  await writeFile(
    path.join(dir, "supabase/config.toml"),
    'project_id = "bye-schedule-api"\n[functions.bye-schedule-api]\nverify_jwt = false\n[functions.bye-schedule-sync]\nverify_jwt = false\n[functions.bye-key-admin]\nverify_jwt = false\n',
  );
  for (const fn of functions) {
    const target = path.join(dir, "supabase/functions", fn.name);
    await mkdir(target, { recursive: true });
    for (const file of fn.files) {
      await writeFile(path.join(target, file.name), file.content);
    }
    const cli = path.join(root, "node_modules/supabase/dist/supabase.js");
    const result = spawnSync(process.execPath, [
      cli,
      "functions",
      "deploy",
      fn.name,
      "--project-ref",
      process.env.BYE_PROJECT_REF ?? "nahvhampsxtasfwvvfei",
      "--workdir",
      dir,
      "--no-verify-jwt",
      "--use-api",
    ], { stdio: "inherit" });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
}

// The deploy tool injects a PUBLIC key digest, never a secret. Environment
// configuration takes precedence when deploying through a separate pipeline.
export const PUBLIC_KEY_SHA256 = "__PUBLIC_KEY_SHA256__";
export const JOB_TOKEN_SHA256 = "__JOB_TOKEN_SHA256__";

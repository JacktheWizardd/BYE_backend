// The deploy tool injects public Auth configuration, never a server secret. Environment
// configuration takes precedence when deploying through a separate pipeline.
export const JOB_TOKEN_SHA256 = "__JOB_TOKEN_SHA256__";
export const AUTH_PUBLISHABLE_KEY = "__AUTH_PUBLISHABLE_KEY__";

import { execFileSync } from 'node:child_process'
import { mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'
for (const [service, environment] of [['web-api', 'preview'], ['web-api', 'production'], ['source-worker', 'preview']]) {
  const out = resolve('.wrangler/artifacts/' + service + '-' + environment)
  await mkdir(out, { recursive: true })
  execFileSync(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'deploy', '--config', `services/${service}/wrangler.jsonc`, '--env', environment, '--dry-run', '--outdir', out], {
    env: { ...process.env, WRANGLER_SEND_METRICS: 'false', WRANGLER_LOG_PATH: '/private/tmp/bye-backend-build.log' }, stdio: 'inherit'
  })
}

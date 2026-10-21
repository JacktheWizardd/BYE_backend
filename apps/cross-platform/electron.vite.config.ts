import {loadEnv} from 'vite'
import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import react from '@vitejs/plugin-react'
import { writeFile } from 'node:fs/promises'
import path from 'node:path'
import policy from './src/shared/features.json'
import pkg from './package.json'
// Only public application identification enters the desktop main bundle.
const scheduleEnv=loadEnv(process.env.NODE_ENV==='development'?'development':'production',process.cwd(),'BYE_')
const clientKey=scheduleEnv.BYE_SCHEDULE_API_KEY??scheduleEnv.BYE_CLIENT_KEY??''
let role=''
try {role=JSON.parse(Buffer.from(clientKey.split('.')[1]??'','base64url').toString('utf8')).role??''}catch{/* Opaque application keys are expected. */}
if(clientKey.startsWith('sb_secret_') || role==='service_role')throw new Error('Use a public schedule application key, never a privileged Supabase key.')
const scheduleConfig={url:scheduleEnv.BYE_SCHEDULE_API_URL??'https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api',key:clientKey}
export default defineConfig({
  main: {
    define: {__BYE_SCHEDULE_CONFIG__:JSON.stringify(scheduleConfig)},
    plugins: [externalizeDepsPlugin(), { name: 'build-policy', async writeBundle(options) {
      await writeFile(path.join(options.dir!, 'build-info.json'), JSON.stringify({ schemaVersion: 1, version: pkg.version, aiSummariesEnabled: policy.aiSummariesEnabled, weightsBundled: policy.aiSummariesEnabled }, null, 2))
    } }],
    build: { sourcemap: false, rollupOptions: { input: { index: path.resolve('src/main/index.ts'), bootstrap: path.resolve('src/main/bootstrap.ts') } } }
  },
  preload: { plugins: [externalizeDepsPlugin()], build: { sourcemap: false, rollupOptions: { output: { format: 'cjs', entryFileNames: '[name].cjs' } } } },
  renderer: { plugins: [react()], build: { sourcemap: false } }
})

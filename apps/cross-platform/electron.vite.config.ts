import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import { loadEnv } from 'vite'
import { publicClientKey } from './src/main/public-key'
import react from '@vitejs/plugin-react'
import { writeFile } from 'node:fs/promises'
import path from 'node:path'
import policy from './src/shared/features.json'
import pkg from './package.json'
export default defineConfig({
  main: {
    define: { __BYE_CLIENT_KEY__: JSON.stringify(publicClientKey(process.env.BYE_CLIENT_KEY ?? loadEnv('production',process.cwd(),'BYE_').BYE_CLIENT_KEY ?? '')) },
    plugins: [externalizeDepsPlugin(), { name: 'build-policy', async writeBundle(options) {
      await writeFile(path.join(options.dir!, 'build-info.json'), JSON.stringify({ schemaVersion: 1, version: pkg.version, aiSummariesEnabled: policy.aiSummariesEnabled, weightsBundled: policy.aiSummariesEnabled }, null, 2))
    } }],
    build: { sourcemap: false, rollupOptions: { input: { index: path.resolve('src/main/index.ts'), bootstrap: path.resolve('src/main/bootstrap.ts') } } }
  },
  preload: { plugins: [externalizeDepsPlugin()], build: { sourcemap: false, rollupOptions: { output: { format: 'cjs', entryFileNames: '[name].cjs' } } } },
  renderer: { plugins: [react()], build: { sourcemap: false } }
})

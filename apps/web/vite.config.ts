import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'
const shared = fileURLToPath(new URL('../cross-platform/src/shared', import.meta.url))
const repo = fileURLToPath(new URL('../..', import.meta.url))
// Relative base lets the static build run from any folder, such as the website's /demo/.
export default defineConfig({
  base: './',
  plugins: [react()],
  resolve: { alias: { '@shared': shared } },
  server: { fs: { allow: [repo] } },
  build: { sourcemap: false }
})

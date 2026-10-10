import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import react from '@vitejs/plugin-react'
export default defineConfig({
  main: { plugins: [externalizeDepsPlugin()], build: { sourcemap: false } },
  preload: { plugins: [externalizeDepsPlugin()], build: { sourcemap: false, rollupOptions: { output: { format: 'cjs', entryFileNames: '[name].cjs' } } } },
  renderer: { plugins: [react()], build: { sourcemap: false } }
})

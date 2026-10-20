// Internal verification entrypoint, bundled into ignored .cache only; never shipped.
import { app, session, net as electronNet } from 'electron'
import path from 'node:path'
import { readFile } from 'node:fs/promises'
import http from 'node:http'
import https from 'node:https'
import net from 'node:net'
import tls from 'node:tls'
import { startApplication } from '../out/main/bootstrap.js'
import { LocalSummaries } from '../src/main/summary.ts'
import { fixtureServices } from './offline-fixtures.ts'
const root = process.env.BYE_OFFLINE_ROOT, storage = process.env.BYE_OFFLINE_STORAGE
if (!root || !storage) throw new Error('Offline entry requires isolated paths.')
const networkAttempts = []
function forbidden() { networkAttempts.push('Unexpected network call'); throw new Error('Network is forbidden during offline verification.') }
globalThis.fetch = async () => forbidden()
for (const module of [http, https]) { module.request = forbidden; module.get = forbidden }
net.connect = forbidden; net.createConnection = forbidden; tls.connect = forbidden
electronNet.request = forbidden; electronNet.fetch = async () => forbidden()
const saved = JSON.parse(await readFile(path.join(root, '../../Tests/ClasswiseCoreTests/Fixtures/pcc-summer-2026-eth014.json'), 'utf8'))
const services = fixtureServices(saved), ai = new LocalSummaries(path.join(storage, 'nonexistent-models'))
const aiCalls = { summarize: 0, verify: 0 }
const summarize = ai.summarize.bind(ai)
ai.summarize = async (...args) => { aiCalls.summarize++; return summarize(...args) }
ai.verify = async () => { aiCalls.verify++; throw new Error('AI verification must stay inactive.') }
const runtime = startApplication({ storage, pcc: services.pcc, rmp: services.rmp, bye:services.bye, ai,
  preload: path.join(root, 'out/preload/index.cjs'), renderer: path.join(root, 'out/renderer/index.html'),
  beforeWindow() {
    session.defaultSession.webRequest.onBeforeRequest({ urls: ['http://*/*', 'https://*/*', 'ws://*/*', 'wss://*/*'] }, (details, callback) => { networkAttempts.push(details.url); callback({ cancel: true }) })
  }
})
globalThis.__offline = { ...runtime, ...services, ai, aiCalls, networkAttempts, metrics: () => app.getAppMetrics() }

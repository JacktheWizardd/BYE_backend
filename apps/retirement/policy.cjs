const https = require('node:https')
const SITE = 'https://bye-before-you-enroll.pages.dev'
const UPDATE_URL = SITE + '/windows/latest.json'
const DOWNLOAD_URL = SITE + '/download/windows/retirement'
function newer(a, b) {
  const parse = v => { const m = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$/.exec(v); if (!m || v.length > 64) throw Error('Invalid version'); return m }
  const x = parse(a), y = parse(b)
  for (let i=1; i<=3; i++) if (+x[i] !== +y[i]) return +x[i] > +y[i]
  return !x[4] && !!y[4]
}
function readLatest(request = https.get) {
  return new Promise((resolve, reject) => {
    const req = request(UPDATE_URL, { headers: { Accept: 'application/json' } }, response => {
      if (response.statusCode !== 200) { response.resume(); reject(Error('Update service unavailable')); return }
      const chunks=[];let bytes=0
      response.on('data', c => { bytes+=c.length; if (bytes>4096) { response.destroy(); req.destroy(); reject(Error('Update response too large')) } else chunks.push(c) })
      response.on('error',reject)
      response.on('end',() => { try { const value=JSON.parse(Buffer.concat(chunks).toString('utf8')); if (!value || typeof value.version!=='string' || value.downloadUrl!==DOWNLOAD_URL) throw Error('Invalid update response'); newer(value.version,'0.0.0');resolve({version:value.version,downloadUrl:DOWNLOAD_URL}) } catch { reject(Error('Invalid update response')) } })
    })
    // A wall-clock deadline bounds slow-drip responses as well as connection stalls.
    const deadline=setTimeout(() => { req.destroy();reject(Error('Update request timed out')) },10000)
    req.on('error',reject);req.on('close',() => clearTimeout(deadline))
  })
}
module.exports={SITE,UPDATE_URL,DOWNLOAD_URL,newer,readLatest}

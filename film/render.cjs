// node render.cjs <w> <h> <out.mp4> [stills]   (stills: write JPGs at TIMES instead of a video)
const { chromium } = require('playwright'), { spawn } = require('child_process'), path = require('path')
const [w, h, out, mode] = process.argv.slice(2), FPS = 30
;(async () => {
  const browser = await chromium.launch(), page = await browser.newPage({ viewport: { width: +w, height: +h } })
  await page.goto('file://' + path.join(__dirname, process.env.SCENE || 'opening.html') + `?w=${w}&h=${h}&norender`)
  await page.evaluate(() => window.READY)
  const DUR = await page.evaluate(() => window.DUR)
  const frame = (t) => page.evaluate((t) => { window.draw(t); return document.getElementById('c').toDataURL('image/jpeg', 0.93) }, t)
  if (mode === 'stills') {
    const fs = require('fs')
    for (const t of (process.env.TIMES || '3,8,13,17,21,28,36,43,47').split(',').map(Number))
      fs.writeFileSync(`${out}-${t}.jpg`, Buffer.from((await frame(t)).split(',')[1], 'base64'))
  } else {
    const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'medium', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] })
    for (let i = 0; i < FPS * DUR; i++) {
      if (!ff.stdin.write(Buffer.from((await frame(i / FPS)).split(',')[1], 'base64'))) await new Promise((r) => ff.stdin.once('drain', r))
      if (i % 150 === 0) process.stderr.write(`${out}: ${(i / FPS).toFixed(0)}s\n`)
    }
    ff.stdin.end(); await new Promise((r) => ff.on('close', r))
  }
  await browser.close()
})()

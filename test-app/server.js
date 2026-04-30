const express = require('express');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

const app = express();
const PORT = 3737;
const RECORDINGS_DIR = path.join(__dirname, 'recordings');

fs.mkdirSync(RECORDINGS_DIR, { recursive: true });

// Serve the test page
app.use(express.static(path.join(__dirname, 'public')));

// Accept raw video blob POSTed as application/octet-stream
app.post('/save-recording', (req, res) => {
  const ts   = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(RECORDINGS_DIR, `recording-${ts}.webm`);
  const out  = fs.createWriteStream(file);

  req.pipe(out);
  out.on('finish', () => {
    console.log(`[saved] ${file}`);
    res.json({ ok: true, file });
  });
  out.on('error', (err) => {
    console.error('[save error]', err);
    res.status(500).json({ ok: false, error: err.message });
  });
});

// Accept event log JSON for post-run analysis
app.use(express.json({ limit: '10mb' }));
app.post('/save-log', (req, res) => {
  const ts   = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(RECORDINGS_DIR, `eventlog-${ts}.json`);
  fs.writeFileSync(file, JSON.stringify(req.body, null, 2));
  console.log(`[saved] ${file}`);
  res.json({ ok: true, file });
});

app.listen(PORT, () => {
  console.log(`BlindSpot adversarial test running → http://localhost:${PORT}`);
  console.log(`Recordings saved to: ${RECORDINGS_DIR}`);
});

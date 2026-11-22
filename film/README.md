# MINAKIBA: "The fund is open"

48-second opening film, two cuts from one scene, with an original score made in code. Brief: `MINAKIBA_OPENING_FILM.md`.

| File | What it is |
|---|---|
| `opening.html` | The scene. `window.draw(t)` renders any time `t`; `?w=&h=` sets the size (`?t=12` previews a frame). |
| `score.py` | The score (koto, bass, congas, shekere, soft kick, pads), 48 s WAV. |
| `render.cjs` | Renders frames through Chromium into H.264, or stills (`node render.cjs 960 540 sheet stills`). |
| `mux.sh` | Adds the score at -16 LUFS / -1.5 dBTP and writes the posters. |
| `fonts/` | Inter Display, Inter, JetBrains Mono (SIL Open Font License, see the licence files). |
| `out/` | `minakiba-the-fund-is-open-wide.mp4`, `-vertical.mp4`, `poster-wide.jpg`, `poster-vertical.jpg` |

Re-render (needs Node with Playwright, ffmpeg, Python with numpy and scipy):

```bash
python3 score.py out/score.wav
node render.cjs 1920 1080 out/video-wide.mp4
node render.cjs 1080 1920 out/video-vertical.mp4
./mux.sh
```

To change the numbers, edit `CARDS` and the `+$0.61 / ₦976` gap label in `opening.html`. The timings
(`PULSES`, `BLADES`, `PEAKS`, card closes) are on a 100 BPM grid that `score.py` shares. If you move a beat
in one file, move it in the other too.

Left out on purpose: the fund naira rate in the market scene (there is no real rate yet), and the Season 1/2
lineage line (it needs the manager's OK).

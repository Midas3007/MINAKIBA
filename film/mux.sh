#!/usr/bin/env bash
# Mux each cut with the score, normalised to -16 LUFS / -1.5 dBTP (two-pass loudnorm for an exact target),
# and write a poster frame (the end card) for each aspect.
set -euo pipefail
cd "$(dirname "$0")/out"
read -r I TP LRA TH OFF < <(ffmpeg -hide_banner -i score.wav -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 |
  python3 -c "import sys,json,re; j=json.loads(re.search(r'\{[^{}]*\}', sys.stdin.read()).group()); print(j['input_i'], j['input_tp'], j['input_lra'], j['input_thresh'], j['target_offset'])")
LN="loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=$I:measured_TP=$TP:measured_LRA=$LRA:measured_thresh=$TH:offset=$OFF:linear=true"
for cut in wide vertical; do
  ffmpeg -v error -y -i video-$cut.mp4 -i score.wav -c:v copy -af "$LN,aresample=48000" -c:a aac -b:a 192k -shortest \
    -movflags +faststart minakiba-the-fund-is-open-$cut.mp4
  ffmpeg -v error -y -ss 46.8 -i video-$cut.mp4 -frames:v 1 -q:v 2 poster-$cut.jpg
done

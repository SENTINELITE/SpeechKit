# AAC-in-MP4 integration fixtures

Added 2026-10-30 by Codex on Kirklands-MacBook-Pro.local. Binary copies match
`speechkit-relay/test/fixtures/` byte-for-byte; tests require no sibling checkout.

- `aac.m4a`, `aac.mp4`, `aac-faststart.m4a`: 96 real AAC-LC units at 48 kHz.
- `he-aac.m4a`: 50 SBR units with a 24 kHz LC core.
- `surround.m4a`: 95 FFmpeg 5.1 units at 48 kHz.
- `merged-samples.m4a`: all 96 faststart units packed into one declared sample,
  with `stts` reduced to 1,024 ticks. Decodes to 2.048 seconds with FFmpeg.

The relay's `test/fixtures/regenerate-mp4.sh` regenerates encoder fixtures.
`test/fixtures/merge-aac-samples.mjs` reproduces the packed-sample mutation
without changing encoded bytes. Copy regenerated files here intentionally.
The SDK checks strict acceptance and byte-identical passthrough, rejects packed
units before credentials or HTTP with optimization off, and converts to PCM
with optimization on. The local conversion intermediate is private ADTS,
produced at syntax-proven access-unit boundaries with duration and byte caps.
It is never uploaded and is removed with the prepared directory.

`black-video.mov` contains two synthetic black MJPEG frames and no audio.
Relay upload tests mux it with their synthetic AAC track to check that the
video track is removed and the encoded audio packets are preserved. Keeping
the frames pre-encoded avoids requiring a video encoder on CI runners.

```sh
ffmpeg -f lavfi -i 'color=c=black:s=64x64:r=1' \
  -t 2 -an -c:v mjpeg -pix_fmt yuvj420p -threads 1 -fflags +bitexact \
  -flags:v +bitexact -map_metadata -1 black-video.mov
```

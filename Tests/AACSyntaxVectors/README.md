# AAC syntax vectors

These vectors exercise the standalone validators in `src/aac-syntax.ts` and
`SpeechKit/Sources/SpeechKit/Relay/SpeechRelayAACSyntax.swift`. JSON copies under
`SpeechKit/Tests/AACSyntaxVectors/` contain identical bytes. Tests need neither
encoders nor a checkout of the other repository.

## Inventory

`real.json` contains 588 accepted frames in 46 streams:

- `afconvert`: 36 AAC-LC streams, mono and stereo at 8000, 11025, 12000, 16000,
  22050, 24000, 32000, 44100 and 48000 Hz, with two bitrates per channel layout.
- `afconvert`: four HE-AAC encoding attempts using `aach` and `aacp` for mono
  and stereo at 48 kHz output. All succeeded. The stereo PS vector has a mono
  24 kHz LC core, as required by HE-AAC v2. Requesting PS for mono produces an
  SBR-only configuration on this Mac.
- AVFoundation/AVFAudio `AVAudioFile`: mono and stereo AAC-LC at 48 kHz.
- FFmpeg's native AAC encoder: mono, stereo and 5.1 at 48 kHz.
- The review's real `baseline.m4a`: 96 frames at 48 kHz. The same file rewritten
  as one sample containing all 96 blocks is in `rejected` and must fail.

The JSON records encoder version, ASC hex, effective LC core configuration,
and each MP4 sample as base64. FFprobe supplies each packet's exact file position
and byte length. The extraction script slices the encoded file at those ranges;
it neither decodes nor rewrites the samples.

`synthetic.json` has 1,438 cases: 1,404 accepted and 34 rejected. It covers every
codeword in spectral books 1–11 and the scalefactor book, sign and escape bits,
all four window sequences, short-window grouping, MS masks, intensity, PNS,
pulse, TNS, DSE lengths, FIL lengths, PCE mappings, and layouts 1–7. Rejections
include concatenated blocks, truncation, trailing garbage and zero bytes,
nonzero final alignment, wrong element layouts, CCE, prediction, gain control,
reserved syntax and overlong escapes. The suites also reject concatenation,
truncation and trailing bytes for every real frame, and run the same 5,000-case
seeded random-input loop. Swift exercises both Data and byte-array APIs and
Data slices with nonzero start indices.

## Regenerate on macOS

Keep `speechkit-relay` and `SpeechKit` as sibling directories. Install FFmpeg
and the macOS Command Line Tools. From `speechkit-relay`:

```sh
node scripts/aac-vectors/generate.mjs /tmp/speechkit-upload-verification
node scripts/aac-vectors/generate-synthetic.mjs
npx prettier --write test/aac-vectors/*.json
cp test/aac-vectors/real.json ../SpeechKit/Tests/AACSyntaxVectors/real.json
cp test/aac-vectors/synthetic.json ../SpeechKit/Tests/AACSyntaxVectors/synthetic.json
```

The optional directory argument contains the review's `baseline.m4a` and
`merged-samples.m4a`, produced by its `make-probes.mjs`. Without it the generator
retains the checked-in review vectors while regenerating all encoder streams.
The script creates deterministic PCM with tones, noise and transients, invokes
the three encoder paths, extracts every sample and configuration, and writes
both fixture copies. Temporary WAV/M4A files remain in the printed scratch
folder for independent FFmpeg inspection. Production code has no encoder or
external process dependency. A synthetic table-source file can be passed as an
argument to `generate-synthetic.mjs` for offline regeneration.

Huffman and band-table provenance is the public-domain JAAD / FreeBSD JCodec
source at revision `4ba922aca445c4df59f99e183c79d0538e5cb53f`. Both production
modules retain its copyright, conditions and disclaimer. No FFmpeg or FAAD2
code or tables were copied. Regenerate the transformed tables with:

```sh
python3 scripts/aac-vectors/regenerate-tables.py
```

That script checks prefix-freeness and completeness, then emits identical
binary tries for both languages. Leaves retain only the number of sign and
escape bits needed for spectral syntax, or the scalefactor differential.
It performs no dequantization or synthesis.

## API and accepted configuration

```ts
validateSingleAccessUnit(sample: Uint8Array, config: AACSyntaxConfig): boolean
```

`AACSyntaxConfig` contains `objectType: number`, `samplingFrequencyIndex: number`,
`channelConfiguration: number`, `frameLengthFlag: boolean`, and optional
`programConfig: AACProgramConfig`. `AACProgramConfig` has `front`, `side`, `back`
and `lfe` arrays of `{ type: "sce" | "cpe" | "lfe", tag: number }`.

```swift
SpeechRelayAACSyntax.validateSingleAccessUnit(sample: Data, config: Config) -> Bool
SpeechRelayAACSyntax.validateSingleAccessUnit(sample: [UInt8], config: Config) -> Bool
```

Swift's nested public `Config` has the same fields, with `Int` integer values.
Its initializer takes all four scalar fields and optional `programConfig`.
Nested `Element` takes `type: Element.Kind` and `tag: Int`; `Kind` has cases
`.sce`, `.cpe` and `.lfe`. Nested `ProgramConfig` takes `front: [Element]` plus
optional `side`, `back` and `lfe` arrays, each defaulting to empty.

`true` means one complete block with the required audio elements, ID_END,
zero alignment bits and no remaining bytes. `false` means reject or convert.
The functions never throw. Pass the **effective LC core** object type 2,
frequency index and channel layout from ASC, including for HE-AAC whose outer
object type can be 5 or 29. PS stereo has a mono core. Supported frequency
indices are 0–12. For channel configuration 0, pass the PCE topology from ASC
or require a leading in-band PCE. If both are present they must match, including
tags. In-band PCEs must precede audio elements; a second PCE is rejected.
Configurations 1–7 require their standard SCE/CPE/LFE counts; a supplied PCE
must additionally match the front/side/back/LFE topology. Element tags are unique
within each element type.

Conservative limits: 8192 bytes per sample, eight channels, 1024-sample LC
frames only. `frameLengthFlag = true` is rejected because 960/120-line band
tables do not yet have independent encoder coverage here. Prediction, gain
control, coupling elements, reserved values and unsupported profiles fail
closed. Length-delimited FIL payloads are opaque, including SBR/PS. This is a
boundary validator, not an audio conformance decoder or an SBR semantic check.

## Worker performance

Run the benchmark inside the configured workerd Vitest pool:

```sh
npx vitest run test/aac-syntax.test.ts --reporter=json --outputFile=/tmp/aac-results.json
```

Each of the three 48 kHz stereo LC streams gets 100 warmup rounds, then three
trials of 2000 rounds. Base64 conversion is outside the timer; results include
bit walking and per-frame allocation. The JSON reporter stores trial times,
median ns/frame and the 60-minute projection in each benchmark test's
`meta.aacSyntaxBenchmark`. The test checks every measured call succeeds and
that the clock advances, but applies no machine-specific speed threshold.
Local workerd elapsed time estimates CPU cost; it is not a production CPU
profile. JIT, CPU scheduling, bitrate and content affect the result.

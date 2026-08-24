# 04 — Audit the app bundle size

**Type:** chore  
**Status:** ready-for-human  
**Blocked by:** None  
**From:** request by glangmead, 2026-08-24  
**Spec:** None — audit; findings go to a doc, fixes become their own tickets  
**Assignee:** glangmead  
**Opened:** 2026-08-24  

## Task

Measure what Diction ships and where the bytes go, so we can decide what (if anything) to trim or move to on-demand resources. This ticket produces numbers and a ranked recommendation; it changes no shipped code.

### Measure

1. Archive a Release build (`asc-xcode-build` skill or `xcodebuild archive`) and export with app thinning for all device variants, so the App Thinning Size Report gives **download** and **install** size per device class. Note the App Store's cellular download threshold (200 MB) and whether any variant crosses it.
2. Break the installed `.app` down by component, largest first, with sizes:
   - `KokoroModels.bundle` — the CoreML model(s) and the 29 bundled English voice packs (`<id>.bin`, see `KokoroSpeechEngine.bundledEnglishVoiceIDs`); give per-voice size and the total.
   - Misaki G2P assets (`G2PEncoder.mlmodelc`, `G2PDecoder.mlmodelc`, `g2p_vocab.json`) and the gold/silver lexicon JSON (~3 MB uncompressed, per `LexiconCache`).
   - FluidAudio and any other Swift package binaries.
   - The C/C++ interpreters under `Interpreters/` (per-interpreter binary size, and whether any are linked but unused).
   - The GlkOte/`glk-bridge.html` web assets (JS, CSS, fonts).
   - The bundled game(s), fonts, asset catalog, and localisations.
   - The app binary itself (`Diction`), with and without symbols.
3. Record the toolchain settings that affect size: optimisation level, `STRIP_INSTALLED_PRODUCT`, dead-code stripping, bitcode/symbol settings, asset-catalog compression.

### Recommend

A ranked table — MB saved, user-visible cost, effort — for every option worth considering, for example: ship fewer voices (or the four accent/gender defaults) and load the rest as On-Demand Resources; compress or trim the lexicon; drop unused interpreters; asset-catalog or image compression; anything the size report flags. For each recommendation state what would need a decision from the owner (e.g. which voices are default) versus what is a pure engineering change.

### Deliverable

- `docs/bundle-size-2026-08.md` — the measurements (with the commands used so they can be re-run), the component table, and the ranked recommendations.
- One implementation ticket per recommendation the owner accepts, opened as follow-ups; this ticket resolves when the doc is written and the owner has seen the table.

### Acceptance

- Download and install sizes are reported per device class from a real thinned export, not estimated.
- Every component over 1 MB appears in the table with a measured size.
- Recommendations carry a measured or clearly-derived MB figure each.

## Comments

### glangmead (Claude) — 2026-08-24

Measured. Findings in [bundle-size-2026-08.md](../../../bundle-size-2026-08.md) (commit `7509f0a`); artefacts under `nocommit/bundle-size/`.

- **Download 100.3 MB / install 120.4 MB** on every device class from a `<thin-for-all-variants>` export (base iPads 99.3 / 119.4; universal 102.7 / 122.8). Half the 200 MB cellular limit.
- **95.3 MB of the download is `KokoroModels.bundle`**: ANE model chain 77.1 MB (Vocoder alone 46.0), 29 voices 13.9 MB (0.48 MB each), lexicons 3.0 MB (12.6 MB installed), G2P 1.4 MB. Weights are already fp16.
- Everything else is 5 MB: binary 2.2 MB (5.2 installed; 57 % of its code is FluidAudio, most of it unused ASR/diarizer/other-TTS stacks), icon 2.4 MB, web interpreters 0.2 MB, game 0.06 MB.
- Nothing native is linked: `Interpreters/sources` is gitignored reference source; no fonts; no localisations.

Decisions the owner needs to make before follow-up tickets are opened (§ 6 of the doc):

1. Ship the neural voice in the box, or fetch it on demand (ODR / first-use download)? Saves 95 MB download / 112 MB install; dwarfs everything else.
2. If in the box: which four voices are default (rest → ODR, 12.0 / 13.1 MB)?
3. Is a quality pass on 8-bit quantised Kokoro weights worth a spike (≈ 38 / 41 MB)?
4. Drop the silver lexicons (1.5 / 6.8 MB, pronunciation risk on rare words)?

Pure-engineering items that need no decision: ODR the UK lexicons alongside UK voices; gzip the lexicons on disk (install only); housekeeping — `Configuration.storekit` ships in the app, vestigial `-lc++`, dead `Interpreters/` scripts. Leaving this `ready-for-human`; resolve once the table has been read and the accepted items have tickets.

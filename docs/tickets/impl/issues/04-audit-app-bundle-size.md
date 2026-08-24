# 04 — Audit the app bundle size

**Type:** chore  
**Status:** ready-for-agent  
**Blocked by:** None  
**From:** request by glangmead, 2026-08-24  
**Spec:** None — audit; findings go to a doc, fixes become their own tickets  
**Assignee:** —  
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

# Bundle size audit — August 2026

**Ticket:** [04 — Audit the app bundle size](tickets/impl/issues/04-audit-app-bundle-size.md)  
**Measured:** 2026-08-24, Xcode 26.6 (17F113), `main` at `7c3fe16`, version 1.0 (1)  
**Author:** glangmead (with Claude)

## Headline

Diction downloads at **100 MB and installs at 120 MB** on every device class. That is half the App Store's 200 MB over-cellular limit, so nothing is urgent. **95 % of the download (95 of 100 MB) is neural narration** — `KokoroModels.bundle` — and everything else the app ships (binary, web interpreters, game, icon) is under 9 MB combined. Every worthwhile size lever is therefore a decision about how much of Kokoro to ship in the box versus fetch on demand.

## 1. Download and install size per device class

From the App Thinning Size Report of a real thinned export (commands in § 5). Apple's figures are decimal MB; "download" is the compressed IPA, "install" is the uncompressed `.app`.

| Variant | Devices | Download | Install |
| --- | --- | ---: | ---: |
| `Diction-D080F0AB…ipa` | All iPhones (iPhone 11 → iPhone 17 family) | **100.3 MB** | **120.4 MB** |
| `Diction-17DF029B…ipa` | iPad Pro / Air / mini, Vision Pro (compat), Mac (Designed for iPad) | 100.3 MB | 120.4 MB |
| `Diction-91B32254…ipa` | Base iPads (iPad 6th–11th gen) | 99.3 MB | 119.4 MB |
| `Diction.ipa` | Universal (what TestFlight/Xcode installs) | 102.7 MB | 122.8 MB |

- **Cellular threshold:** the App Store prompts for Wi-Fi above 200 MB (users can override since iOS 13). No variant is within 90 MB of it; there is room for a second bundled game or more voices before this matters.
- The variants differ by ~1 MB only in `Assets.car` (icon rasters per idiom). There are no device-specific resources or architectures otherwise — the build is arm64-only (`ARCHS = arm64`).
- On-Demand Resources: zero. `ENABLE_ON_DEMAND_RESOURCES = YES` is set (Xcode default) but nothing is tagged.
- Install size grows by ~1.6 MB after the first use of neural narration: `KokoroSpeechEngine.seedG2PCacheIfNeeded` copies the G2P assets into `Caches/fluidaudio/Models/kokoro/` because FluidAudio insists on a writable model directory for them.

## 2. Component breakdown (iPhone variant)

Install = uncompressed bytes in the `.app`; download = deflated bytes in the IPA, i.e. each component's real contribution to the 100.3 MB. The rows sum to Apple's totals exactly (120.36 / 100.29 MB).

| Component | Install MB | Download MB | Notes |
| --- | ---: | ---: | --- |
| **`KokoroModels.bundle` (total)** | **111.6** | **95.3** | Neural TTS; everything below down to G2P |
| ├ `KokoroVocoder.mlmodelc` | 49.2 | 46.0 | fp16 weights (`weight.bin` 48.9 MB); barely compressible |
| ├ Voice packs, 29 × `<id>.bin` | 15.1 | 13.9 | **0.52 / 0.48 MB per voice**, all identical size (510 KB float32 style vectors); `af.bin` is 512 KB |
| ├ `KokoroPostAlbert.mlmodelc` | 13.9 | 13.3 | fp16 |
| ├ `KokoroProsody.mlmodelc` | 8.5 | 8.0 | fp16 |
| ├ `KokoroAlbert.mlmodelc` | 5.8 | 5.4 | fp16 |
| ├ `KokoroNoise.mlmodelc` | 4.7 | 4.3 | fp32 (the one stage not yet halved) |
| ├ `KokoroTail` + `KokoroAlignment` | 0.1 | 0.1 | |
| ├ Misaki lexicons (4 JSON) | 12.6 | 3.0 | `gb_silver` 3.7/0.8, `us_silver` 3.1/0.7, `us_gold` 3.0/0.7, `gb_gold` 2.8/0.7. Only one region pair loads per session (`DataResourcesUtil.loadGold/loadSilver(british:)`); UK pair is 6.5 / 1.5 MB |
| └ Misaki G2P (`G2PEncoder`, `G2PDecoder`, `g2p_vocab.json`) | 1.6 | 1.4 | fp16. `G2PDecoder` 0.85 / 0.77, `G2PEncoder` 0.71 / 0.65, `g2p_vocab.json` 1.7 KB |
| `Diction` binary (stripped) | 5.2 | 2.2 | See § 3 |
| `Assets.car` + 2 icon PNGs | 2.5 | 2.4 | Almost entirely the Liquid Glass app icon rendered to 1024² layers (ARGB 0.8 MB, GRAY‑16 0.7 MB, …); 6 named colours ≈ 1.5 KB. Universal IPA carries 4.9 MB |
| GlkOte / Quixe / ZVM / jQuery web assets (13 files) | 0.9 | 0.2 | `glkapi.js` 218 KB, `quixe.min.js` 168 KB, `glkote.js` 117 KB, `zvm.js` 102 KB, `jquery.min.js` 94 KB, rest < 50 KB each. No fonts, no images |
| Bundled game `devours.z5` | 0.16 | 0.06 | |
| Licences, `Info.plist`, `_CodeSignature`, `embedded.mobileprovision`, `Configuration.storekit`, `SpeechProfiles/global.json` | 0.07 | 0.03 | |
| **Total** | **120.4** | **100.3** | |

Things the ticket asked about that turn out to be **absent**:

- **C/C++ interpreters: none are linked.** `Diction/Interpreters/sources/` (bocfel, remglk, quixe — 4.5 MB on disk, gitignored) is fetched by `Interpreters/scripts/fetch_sources.sh` for reference only; nothing in `project.pbxproj` refers to it, the `.app` has no `Frameworks/` directory, and the target contains no `.c`/`.cpp`/`.mm` files. Games run in the JS interpreters (Quixe for Glulx, ZVM for Z-machine) inside a `WKWebView`. The `-lc++` in `OTHER_LDFLAGS` is vestigial (links the system dylib; zero size cost). The fetch script's comment points at a `build_xcframeworks.sh` that does not exist.
- **Swift package binaries: none as separate files.** FluidAudio is linked statically into `Diction`; it contributes no `.framework` or resource bundle (its only package resource, `english.json`, belongs to the CLI target, not the library).
- **Localisations and fonts: none.** No `.lproj`, `.xcstrings` or font files ship; `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` is set but there is no catalogue.

## 3. The app binary

| Measurement | Size |
| --- | ---: |
| `Diction` in the shipped IPA (stripped, `STRIP_STYLE = all`) | 5.16 MB install / 2.22 MB download |
| `Diction` from a plain Release build, unstripped | 16.0 MB (54,745 symbols; `__LINKEDIT` 9.9 MB; also carries a 0.4 MB `__LLVM_COV` segment that the archive does not) |
| `Diction.app.dSYM` in the archive (DWARF) | 30.8 MB (33 MB on disk) — not shipped |
| `__TEXT` segment (shipped) | 4.37 MB, of which `__text` code ≈ 3.6 MB |

Where the code comes from, by walking the dSYM symbol table (`nm -n`) and bucketing by mangled module prefix:

| Module | `__text` KB | Share |
| --- | ---: | ---: |
| FluidAudio (`$s10FluidAudio…`) | 2,048 | 57 % |
| Diction app code | 926 | 26 % |
| Swift stdlib/runtime specialisations | 467 | 13 % |
| Diction's vendored Misaki + Kokoro glue | 109 | 3 % |
| C / ObjC / other | 35 | 1 % |

FluidAudio's symbols show the whole package is present — `AsrManager`, `OfflineDiarizerManager`, `SortformerConfig`, `Qwen`, `Supertonic`, `StyleTTS`, `PocketTts`, `Magpie`, `MandarinG2P`, `DownloadUtils` — although Diction only calls `KokoroAneManager` and the G2P model. `DEAD_CODE_STRIPPING = YES` is on, but Swift's public type metadata keeps these alive. Speech recognition is Apple's `SFSpeechRecognizer`, so FluidAudio's ASR stack is dead weight (~1 MB compressed at most).

## 4. Toolchain settings that affect size

Effective values for the `Diction` target, Release, from `xcodebuild -showBuildSettings` (all are Xcode defaults unless noted):

| Setting | Value | Comment |
| --- | --- | --- |
| `SWIFT_OPTIMIZATION_LEVEL` | `-O` (default; Debug overrides to `-Onone`) | |
| `SWIFT_COMPILATION_MODE` | `wholemodule` | Set in project |
| `GCC_OPTIMIZATION_LEVEL` | `s` (default) | No C sources anyway |
| `DEAD_CODE_STRIPPING` | `YES` | |
| `LLVM_LTO` | not set (off) | Would not touch resources; expected < 0.3 MB on the binary |
| `STRIP_INSTALLED_PRODUCT` / `STRIP_STYLE` / `STRIP_SWIFT_SYMBOLS` | `YES` / `all` / `YES` | Applied during archive (`DEPLOYMENT_POSTPROCESSING`); `COPY_PHASE_STRIP = NO` is the correct pairing |
| `DEBUG_INFORMATION_FORMAT` | `dwarf-with-dsym` | DWARF goes to the dSYM, not the app |
| `ENABLE_BITCODE` | not set | Bitcode is gone since Xcode 14; nothing to do |
| `ARCHS` / `ONLY_ACTIVE_ARCH` | `arm64` / `NO` | Single slice |
| `ASSETCATALOG_COMPILER_OPTIMIZATION` | not set (`time`) | `space` would shave a few KB off a 2.4 MB `.car`; not worth it |
| `COMPRESS_PNG_FILES` | `YES` | Two icon PNGs, 48 KB total |
| `ENABLE_ON_DEMAND_RESOURCES` | `YES` | Nothing tagged |
| `CLANG_COVERAGE_MAPPING` | reported `YES` | Not set anywhere in the project or scheme; explains the `__LLVM_COV` segment in plain Release builds. Archives don't carry it, so it does not ship |
| Kokoro weight precision | fp16 (Albert, PostAlbert, Prosody, Vocoder, G2P); fp32 (Noise, Tail) | Read from each `model.mil`; fp16 is already done upstream, so there is no cheap 2× left |

## 5. How to re-run

Everything lands under `nocommit/bundle-size/` (gitignored). The shell wraps `xcodebuild` through `xcsift` and `find` through `bfs`; use the full paths shown.

```bash
cd Diction
mkdir -p ../nocommit/bundle-size

# 1. Archive (asc's helper; ~3 min)
asc xcode archive --project Diction.xcodeproj --scheme Diction --configuration Release \
  --archive-path ../nocommit/bundle-size/Diction.xcarchive \
  --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS \
  --xcodebuild-flag=-allowProvisioningUpdates --output json

# 2. Thinned export. `asc xcode export` deletes the output when it can't find a single
#    IPA, so use xcodebuild directly. Method "development" (Xcode 26 calls it "debugging")
#    because no distribution certificate is installed here; thinning output is identical.
cd ../nocommit/bundle-size
cat > ExportOptions-thinned.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>28K28PQK98</string>
  <key>thinning</key><string>&lt;thin-for-all-variants&gt;</string>
  <key>compileBitcode</key><false/>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
EOF
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -exportArchive \
  -archivePath Diction.xcarchive -exportPath export \
  -exportOptionsPlist ExportOptions-thinned.plist -allowProvisioningUpdates
cat "export/App Thinning Size Report.txt"

# 3. Per-component install vs download (bytes in the .app vs deflated bytes in the IPA)
IPA=$(ls export/Apps/Diction-*.ipa | head -1)   # pick the iPhone variant from the report
unzip -lv "$IPA" | awk '$NF ~ /^Payload\// {print $1, $3, $NF}'   # uncompressed, compressed, path
mkdir -p ipa && unzip -q "$IPA" -d ipa && du -sk ipa/Payload/Diction.app/* | sort -rn

# 4. Binary: stripped size, segments, and code attribution by module
size -m ipa/Payload/Diction.app/Diction
nm -n --defined-only Diction.xcarchive/dSYMs/Diction.app.dSYM/Contents/Resources/DWARF/Diction \
  | awk '$2 ~ /^[tT]$/'          # then diff consecutive addresses, bucket on $s10FluidAudio / $s7Diction

# 5. Unstripped binary: a plain Release build never runs strip
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build -project ../../Diction/Diction.xcodeproj \
  -scheme Diction -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO
ls -l ../../Diction/Build/Products/Release-iphoneos/Diction.app/Diction

# 6. Effective size-related settings and model weight precision
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -showBuildSettings -project ../../Diction/Diction.xcodeproj \
  -scheme Diction -configuration Release -sdk iphoneos | grep -E "STRIP|DEAD_CODE|OPTIMIZATION|LTO|BITCODE|ON_DEMAND|ASSETCATALOG"
for d in ../../Diction/Diction/Resources/KokoroModels.bundle/kokoro-82m-coreml/ANE/*.mlmodelc; do
  echo "$(basename $d): $(grep -oE 'tensor<(fp16|fp32)' $d/model.mil | sort | uniq -c | tr '\n' ' ')"; done
```

## 6. Recommendations, ranked by MB saved

"Decision" = the owner has to choose something product-facing; "engineering" = no product decision, just a ticket.

| # | Option | Download saved | Install saved | User-visible cost | Effort | Needs |
| --- | --- | ---: | ---: | --- | --- | --- |
| 1 | **Move all of neural narration to On-Demand Resources** (or a first-use download): tag `KokoroModels.bundle` as an ODR asset pack; fetch with `NSBundleResourceRequest` when the user first enables neural narration; point `KokoroAneManager(directory:)` at the pack's URL. Initial app becomes ≈ 5 MB / 9 MB. | **95 MB** | **112 MB** | First use of neural narration needs a ~95 MB download with progress UI and failure states; iOS may purge the pack under storage pressure and re-fetch it later; the Settings audition would need the pack too. Neural narration is a paid feature (ADR 0001), so gating the download behind purchase is natural. ODR is App-Store-hosted and works in TestFlight; not available for ad-hoc/enterprise. | Medium–high (ODR tagging is trivial; the work is UI, error paths, and testing the hosted flow) | **Decision:** is neural narration "in the box" or an opt-in download? |
| 2 | **Ship only the default voices, ODR the rest.** Keep 4 (one per accent × gender, e.g. `af_heart`, `am_michael`, `bf_emma`, `bm_george`) in the initial install; tag the other 25 `.bin` files as ODR, one tag per voice or per accent. | 12.0 MB | 13.1 MB | Picking a non-default voice triggers a 0.5 MB fetch. FluidAudio's `ensureVoicePack` looks for `<directory>/<voice>.bin` and would otherwise try to download from HuggingFace, so fetched voices must be copied into a writable model directory (the G2P assets already take that path via `seedG2PCacheIfNeeded`), or the whole model dir moves to `Caches` on first launch. | Medium | **Decision:** which four voices are default. Rest is engineering. |
| 3 | **Quantise the Kokoro weights to 8-bit** (coremltools linear quantisation or palettisation on the five fp16 stages; `KokoroNoise` is still fp32 and would go 4×). Regenerate via `nocommit/stage_kokoro.py` from a re-exported model. | ≈ 38 MB (half of 77 MB; derived, not measured) | ≈ 41 MB | Possible audible degradation; ANE scheduling can change and affect latency. Must be auditioned per voice before shipping. | High — upstream model work (FluidInference/kokoro-82m-coreml), then validation | **Decision:** quality sign-off. Worth a spike only if #1 is rejected. |
| 4 | **Trim the lexicons.** Options, independent of each other: (a) ODR the UK pair with the UK voices (pairs with #2); (b) store the JSON gzipped or as a compact binary and inflate at load (saves install only — the IPA already deflates them 4×); (c) drop the silver lexicons (misaki's `Lexicon` consults gold first and silver only for words gold misses; the neural G2P is the fallback after that). | (a) 1.5 MB, (b) 0, (c) 1.5 MB | (a) 6.5 MB, (b) ≈ 9.6 MB, (c) 6.8 MB | (a) none beyond #2; (b) a few tens of ms extra on the first lexicon build (already done off the main actor by `prewarmLexicon`); (c) more OOV words hit the neural G2P — pronunciation risk on rarer words. | (a) low once #2 exists; (b) low; (c) trivial but needs an audition pass | (a),(b) engineering; (c) **decision** (quality). |
| 5 | **Cut FluidAudio's unused stacks** (ASR, diarisation, Qwen/Supertonic/StyleTTS/PocketTTS/Magpie TTS, Mandarin G2P): either ask upstream for a TTS-only product, or vendor the `TTS/KokoroAne` + `Shared` subset. | ≤ 1 MB | ≤ 2 MB | None | Medium–high (vendoring means owning updates; upstream split is a request, not work) | Engineering; low priority — cheapest to raise upstream and wait. |
| 6 | **Housekeeping** (no measurable MB): stop shipping `Configuration.storekit` (a StoreKit test file is in the Resources phase, `project.pbxproj:11`); drop the vestigial `-lc++` from `OTHER_LDFLAGS`; delete or document `Diction/Interpreters/` (its scripts reference a build step that no longer exists); optionally set `CLANG_COVERAGE_MAPPING = NO` for Release. | 0 | 0 | None | Trivial | Engineering |

**Not recommended:** minifying `glkapi.js`/`glkote.js` (≤ 0.4 MB install, 0.05 MB download); `ASSETCATALOG_COMPILER_OPTIMIZATION = space`; LTO; anything about interpreters (none are linked); converting the models to fp16 — upstream already did it, so there is no cheap 2× left.

**Suggested order:** decide #1 first, because it dwarfs everything else and makes #2/#4(a) moot (the voices and lexicons would ride along in the pack). If neural narration stays in the box, do #2 + #4(a) together (≈ 13.5 MB download, ≈ 20 MB install) and file #6 as a chore either way.

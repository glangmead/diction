# Diction

Voice-first iOS player for Z-machine and Glulx interactive fiction. Diction reads
the game aloud while you play; with the full version you can also give parser
commands by voice. A built-in **Find** browser lists classic games from IFDB that
are a click away.

## Features

- **Narration.** The free version reads game output with Apple's Accessibility
  text-to-speech engine. The full version adds a neural voice (Kokoro) for a more
  natural read.
- **Voice commands.** _(Full version)_ The mic listens continuously and knows when
  you've stopped talking; your speech is normalized to parser commands. Recognition
  favors words from the recent game log to handle unusual names.
- **Spoken control commands.** Say "game" followed by `stop`, `repeat`, `windows`,
  `window N`, `keywords`, `inputs`, or `input N` to control narration and review
  history without touching the screen.
- **Library.** Browse and download classic games from IFDB, or open your own story
  files.

The paywall covers voice features only: games and system-voice narration are free;
a single in-app purchase unlocks neural narration and voice commands. Voice commands
are free to try in the bundled game.

## Architecture

Diction runs the interpreters in JavaScript inside a headless `WKWebView`, the same
autosave-capable web IF stack Lectrote uses, and exchanges RemGlk JSON with the
Swift app:

- **ZVM** ([ifvms.js](https://github.com/curiousdannii/ifvms.js)) interprets
  Z-machine story files.
- **Quixe** ([erkyrath/quixe](https://github.com/erkyrath/quixe)) interprets Glulx
  story files, and supplies the classic Glk stack (`glkapi`, `dialog`, `gi_blorb`,
  `gi_dispa`, `gi_load`).
- **GlkOte** + **jQuery** render the text, grid, and graphics windows inside the web
  page; that rendered surface is what the app displays.

The Swift side (`Diction/Diction/Interpreter/`) drives the page through
`WebInterpreterHost`, decodes the RemGlk JSON into presentation snapshots, answers
save/restore filerefs internally, and feeds the styled output to the narration and
speech-recognition layers.

## Setup

The interpreter JavaScript is built from upstream sources rather than vendored in
git. After cloning this repository:

```
npm install                            # pulls the pinned ifvms (ZVM) package
cd Diction/Interpreters
./scripts/fetch_glk_stack.sh           # vendors Quixe + ZVM + GlkOte + jQuery into the app
```

The script copies the built JS into `Diction/Diction/Interpreter/Resources/` and the
license texts into `Diction/Diction/Resources/Licenses/`. Then open
`Diction/Diction.xcodeproj` and build.

### Pinned versions

| Component | Source | Pin |
|---|---|---|
| Quixe + classic Glk stack | [erkyrath/quixe](https://github.com/erkyrath/quixe) | commit `d1710c27b0ac293d40bc67cb1b3de38c1ef7fa9f` |
| ZVM (Z-machine) | [ifvms](https://www.npmjs.com/package/ifvms) | npm `1.1.6` |

To update, bump `QUIXE_COMMIT` in `scripts/fetch_glk_stack.sh` and/or the `ifvms`
version in `package.json`, re-run `npm install` and the fetch script, and verify the
app still builds. The script re-applies one local patch: GlkOte's MORE paging is
disabled so the buffer scrolls continuously for the voice reader.

## Credits

Diction is built on these open-source projects.

### Interpreters and Glk stack

| Project | Role | License | Author |
|---|---|---|---|
| [Quixe](https://github.com/erkyrath/quixe) | Glulx interpreter + classic Glk stack | MIT | Andrew Plotkin |
| [GlkOte](https://github.com/erkyrath/glkote) | Web display layer — text, grid + graphics windows | MIT | Andrew Plotkin |
| [jQuery](https://github.com/jquery/jquery) | DOM toolkit required by GlkOte | MIT | jQuery Foundation |
| [ifvms.js (ZVM)](https://github.com/curiousdannii/ifvms.js) | Z-machine interpreter | MIT | Dannii Willis |

### Neural voice

| Project | Role | License | Author |
|---|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Neural-voice runtime | Apache 2.0 | FluidInference |
| [Kokoro](https://github.com/hexgrad/kokoro) | Neural-voice model | Apache 2.0 | hexgrad |
| [MisakiSwift](https://github.com/mlalma/MisakiSwift) | Phonemizer — Swift port of misaki | Apache 2.0 | mlalma |
| [misaki](https://github.com/hexgrad/misaki) | Phonemizer — upstream | Apache 2.0 | hexgrad |

The in-app Acknowledgements section (Settings → About) is the source of truth for
these credits; full license texts ship in the app and live under
`Diction/Diction/Resources/Licenses/`.

## License

Diction itself is MIT-licensed — see [LICENSE](LICENSE).

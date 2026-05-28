# Diction

Voice-first iOS player for Z-machine and Glulx interactive fiction. Push-to-talk
voice input is normalized to parser commands via on-device Apple Intelligence,
and game output is read aloud.

## Setup

The app links two static XCFrameworks built from upstream IF interpreters
(Bocfel, Glulxe) plus the RemGlk JSON Glk implementation. The source archives
are not vendored in git; a fetch script clones them at pinned commits.

After cloning this repository:

```
cd Diction/Interpreters
./scripts/fetch_sources.sh        # clones the three repos at pinned commits
./scripts/build_xcframeworks.sh   # cross-compiles to Bocfel.xcframework + Glulxe.xcframework
```

Then open `Diction/Diction.xcodeproj` and build.

### Pinned commits

The fetch script clones at these revisions:

| Library | Commit |
|---|---|
| [RemGlk](https://github.com/erkyrath/remglk) | `7d53a46a9d40d2e569b154e4740e8ac4eee67cb8` |
| [Glulxe](https://github.com/erkyrath/glulxe) | `56ab8743bab565de307bd892c555d8d8897ed517` |
| [Bocfel](https://github.com/erkyrath/bocfel) | `f3bab004d2c16be3f8000b82e4da9cb5f74d30dd` |

To update, edit the commit SHAs in `Diction/Interpreters/scripts/fetch_sources.sh`,
re-run both scripts, and verify the app still builds.

## Licenses

All linked interpreters are MIT-licensed:

- RemGlk, Glulxe — © Andrew Plotkin
- Bocfel — © Chris Spiegel

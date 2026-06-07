/* Drives the classic Glk stack (glkapi + per-VM dispatch + ZVM/Quixe) in a
 * WKWebView. Uses the REAL vendored GlkOte (glkote.js) to render text/grid/
 * graphics windows into the page DOM, while ALSO forwarding GlkOte-protocol
 * updates and the VM's own autosave bytes to Swift (the "tap") so the native
 * voice/narration stack keeps receiving content. Answers save/restore fileref
 * prompts itself (single slot, mirrored to Swift's SaveStorage). Mirrors the
 * Swift-facing protocol the previous bridge used so InterpreterSession is
 * unchanged.
 *
 * The one wire difference the classic stack introduces — text runs encoded as
 * ["style","text",...] pairs instead of {style,text} objects — is normalised
 * here (shimUpdate) before posting, so RemGlkUpdate decodes them unchanged.
 *
 * Autosave: the VM autosaves after every move (do_vm_autosave) and calls
 * Dialog.autosave_write; we post those bytes to Swift (the engine artifact). On
 * restore Swift injects the snapshot up front (pendingAutosave) so the VM's
 * synchronous autosave_read can return it and prepare() self-restores. */

function post(stage, payload) {
  try { window.webkit.messageHandlers.interp.postMessage({ stage, payload: payload ?? null }) } catch (e) {}
}

// Classic GlkOte encodes a line's runs as ["style","text","style","text",...]
// with object entries for special (hyperlink/image) runs. RemGlkUpdate.TextRun
// expects {style,text,...} objects, so convert the paired-string form.
function shimRuns(arr) {
  if (!Array.isArray(arr)) return arr
  const out = []
  for (let i = 0; i < arr.length; i++) {
    if (typeof arr[i] === 'string') { out.push({ style: arr[i], text: arr[i + 1] }); i++ }
    else out.push(arr[i])
  }
  return out
}
function shimUpdate(data) {
  for (const c of data.content || []) {
    for (const ln of c.text || []) if (ln.content) ln.content = shimRuns(ln.content)
    for (const gl of c.lines || []) if (gl.content) gl.content = shimRuns(gl.content)
  }
  return data
}

let glkote = null
let blorb = null
let dialog = null
let pendingAutosave = null   // snapshot object injected by Swift for restore, else null
// The game's single manual SAVE slot, as a byte array (what glkapi's file I/O
// reads/writes), or null when the game has never been saved. Seeded by Swift at
// glkStart from SaveStorage; mirrored back to Swift on every SAVE so it survives
// across launches. The headless WebView has no filesystem, so this in-memory
// copy is what the synchronous Dialog.file_read returns.
let saveSlot = null

// Pack a byte array into base64 for postMessage (chunked so a large save doesn't
// overflow the argument stack of String.fromCharCode).
function bytesToB64(arr) {
  let binary = ''
  for (let i = 0; i < arr.length; i += 8192) {
    binary += String.fromCharCode.apply(null, arr.slice(i, i + 8192))
  }
  return btoa(binary)
}

// Install the real GlkOte plus an update-tap wrapper. The real instance renders
// text/grid/graphics into the page DOM (and resolves Blorb images via the Blorb
// we hand glkapi); the wrapper additionally forwards each update's content to
// Swift so the native voice/narration path keeps working. glkapi honours the
// GlkOte we pass in Glk.init's options (glkapi.js:86-88), so this instance is
// the one it drives.
//
// glkapi calls GlkOte.update(dataobj, gli_autorestore_glkstate) (glkapi.js:781),
// but glkapi.js:779 nulls gli_autorestore_glkstate first, so that 2nd arg is
// always null. The wrapper still forwards ALL arguments via `arguments`
// defensively; autorestore actually travels on dataobj.autorestore (set at
// glkapi.js:778, read by glkote_update at glkote.js:640-641), not as a 2nd param.
// The generation GlkOte last rendered — equals glkapi's current event_generation.
// Native input is stamped with this (see glkSendEvent) so it can't go stale when
// arrange/refresh events advance the generation between turns.
let lastGen = null

/* --- Per-style colour hints (the colours glkote drops) ---------------------
 * glkapi emits a per-window `styles` table on arrangement updates; glkote itself
 * ignores it. We turn it into a `<style id=diction-style-hints>` and inject it
 * BEFORE glkote paints (in the update wrapper, ahead of realUpdate), so coloured
 * keyword runs render correctly on first paint — no flash. Game colours get a
 * legibility lift against the transcript background (ported from Swift RunColor):
 * symmetric, only adjusting colours that would be illegible. `onDark` is seeded
 * at glkStart and updated live by Swift on a light/dark toggle. */
let dictionOnDark = false
let dictionBufferStyles = {}   // merged buffer-window styles table, kept for re-lift

const DICTION_NAMED_COLORS = {
  black: '000000', white: 'ffffff', red: 'ff0000', green: '008000', blue: '0000ff',
  yellow: 'ffff00', cyan: '00ffff', magenta: 'ff00ff', gray: '808080', grey: '808080'
}

function dictionParseColor(css) {
  let s = String(css).trim().toLowerCase()
  if (s[0] === '#') s = s.slice(1)
  if (DICTION_NAMED_COLORS[s]) s = DICTION_NAMED_COLORS[s]
  if (s.length === 3) s = s[0] + s[0] + s[1] + s[1] + s[2] + s[2]
  if (!/^[0-9a-f]{6}$/.test(s)) return null
  return [parseInt(s.slice(0, 2), 16) / 255, parseInt(s.slice(2, 4), 16) / 255, parseInt(s.slice(4, 6), 16) / 255]
}

// Lift a colour toward white on a dark background / toward black on a light one,
// to a luma threshold, preserving hue. Colours already legible pass through.
function dictionLegible(rgb, onDark, threshold) {
  const luma = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
  if (onDark) {
    if (luma >= threshold) return rgb
    const amount = (threshold - luma) / (1 - luma)
    return [rgb[0] + (1 - rgb[0]) * amount, rgb[1] + (1 - rgb[1]) * amount, rgb[2] + (1 - rgb[2]) * amount]
  }
  if (luma <= threshold) return rgb
  const scale = threshold / luma
  return [rgb[0] * scale, rgb[1] * scale, rgb[2] * scale]
}

function dictionHex(rgb) {
  const byte = c => Math.round(Math.max(0, Math.min(1, c)) * 255).toString(16).padStart(2, '0')
  return ('#' + byte(rgb[0]) + byte(rgb[1]) + byte(rgb[2])).toUpperCase()
}

// Build `.BufferWindow .Style_<name>` rules (colour+weight only) from the merged
// styles table, lifting each colour for the current background.
function dictionStyleCss() {
  const rules = []
  for (const key of Object.keys(dictionBufferStyles).sort()) {
    if (key === '.Style_normal') continue
    const attrs = dictionBufferStyles[key]
    const decls = []
    if (attrs.color) {
      const rgb = dictionParseColor(attrs.color)
      decls.push('color: ' + (rgb ? dictionHex(dictionLegible(rgb, dictionOnDark, 0.5)) : attrs.color))
    }
    if (attrs['background-color']) decls.push('background-color: ' + attrs['background-color'])
    if (attrs['font-weight']) decls.push('font-weight: ' + attrs['font-weight'])
    if (decls.length) rules.push('.BufferWindow ' + key + ' { ' + decls.join('; ') + '; }')
  }
  return rules.join('\n')
}

function dictionInjectStyleHints() {
  let el = document.getElementById('diction-style-hints')
  if (!el) { el = document.createElement('style'); el.id = 'diction-style-hints'; document.head.appendChild(el) }
  el.textContent = dictionStyleCss()
}

// Merge any buffer-window styles tables carried by this update, then (re)inject.
// Called before glkote paints, so the rules are in the DOM ahead of the spans.
function dictionApplyStyleHints(data) {
  if (!data || !data.windows) return
  let changed = false
  for (const w of data.windows) {
    if (w.type === 'buffer' && w.styles) { Object.assign(dictionBufferStyles, w.styles); changed = true }
  }
  if (changed) dictionInjectStyleHints()
}

// Swift calls this on a light/dark toggle: re-lift the cached styles in place.
window.dictionSetDark = function (dark) {
  dictionOnDark = !!dark
  dictionInjectStyleHints()
}

function installGlkOte() {
  glkote = new window.GlkOteClass()
  const realUpdate = glkote.update.bind(glkote)
  glkote.update = function (data) {
    if (data && data.gen != null) lastGen = data.gen
    // The game's SAVE/RESTORE verbs surface as a fileref_prompt specialinput
    // (glkapi.js:5132-5145, attached to the update at glkapi.js:758-760). The
    // real GlkOte would route this to Dialog.open() (glkote.js:1665), which our
    // BridgeDialog doesn't implement; instead we answer it ourselves (single
    // slot, no user filename) and DON'T call the real update — there's no new
    // window content on a prompt frame, so nothing to render, and Swift never
    // sees the prompt, so its input model is unchanged and send("save") just
    // resolves on the resulting "Ok." update. Deferred by a microtask so the
    // current glkapi cycle unwinds before we re-enter accept().
    const special = data && data.specialinput
    if (special && special.type === 'fileref_prompt') {
      const gen = data.gen
      Promise.resolve().then(() => answerFileref(special, gen))
      return
    }
    // Render first (real GlkOte reads `data` directly), THEN tap. shimUpdate
    // mutates in place, so deep-copy before shimming so we don't corrupt what
    // GlkOte rendered. glkapi's select posts the display update, THEN runs
    // do_vm_autosave synchronously; defer our post by a microtask so it reaches
    // Swift AFTER the move's autosave message — otherwise send() resolves on the
    // update with the previous turn's snapshot still latest, and a restore lands
    // one move stale.
    // Inject the per-style colour CSS BEFORE glkote paints, so coloured runs
    // render correctly on first paint instead of flashing in afterward.
    dictionApplyStyleHints(data)
    realUpdate.apply(glkote, arguments)
    let copy
    try { copy = JSON.parse(JSON.stringify(data)) } catch (e) { return }
    const shimmed = shimUpdate(copy)
    Promise.resolve().then(() => post('update', shimmed))
  }
}

// Answer a fileref_prompt the game raised for its SAVE/RESTORE verb. Single
// slot, so we construct the ref ourselves rather than asking the user for a
// name. We feed the response straight to glkapi's accept callback — on the real
// GlkOte that's reached via getinterface().accept (== glkapi's accept_ui_event,
// set at glkapi.js:104), not the stub's old accept_func property. The gen MUST
// match the prompt's update generation or glkapi silently drops the event
// (accept_ui_event's generation guard, glkapi.js:138). Only the `save` filetype
// is backed by a slot; transcript/command/data prompts are cancelled (null ref),
// which makes the game print its own "cancelled" message. glkapi turns this
// response into a fileref (glkapi.js:5151-5174); the VM then reads/writes it
// through BridgeDialog's synchronous file_* API, backed by saveSlot.
function answerFileref(special, gen) {
  if (!glkote) return
  const iface = glkote.getinterface()
  if (!iface || !iface.accept) return
  const ref = special.filetype === 'save'
    ? dialog.file_construct_ref('save', special.filetype, special.gameid)
    : null
  iface.accept({ type: 'specialresponse', response: 'fileref_prompt', value: ref, gen })
}

// Named/temp files (glk_fileref_create_by_name / _temp — e.g. Counterfeit
// Monkey's Inform 7 external-data file, opened on its FIRST turn) get their own
// session-only, in-memory keyed store, kept SEPARATE from the manual SAVE slot so
// a game's data file can't collide with or corrupt the player's save. Only the
// save slot (usage 'save') is mirrored to Swift's SaveStorage.
const namedFiles = {}
let tempRefCounter = 0

// The manual SAVE slot is identified by the 'save' usage the SAVE/RESTORE prompt
// path constructs (answerFileref → file_construct_ref('save', 'save', …)).
// Everything else is a session-only named/temp file.
function isSaveRef(ref) { return !!ref && ref.usage === 'save' }

// Dialog: autosave routes to/from Swift (the resume mechanism); the synchronous
// fileref API backs the game's SAVE/RESTORE verb with a single in-memory slot
// (`saveSlot`, seeded from and mirrored to Swift's SaveStorage), plus an
// in-memory store for game-named data/temp files.
class BridgeDialog {
  constructor() { this.streaming = false }
  // Real GlkOte calls Dialog.inited() at init (glkote.js:365); a truthy return
  // makes glkote_init SKIP its init block (init/init_async, glkote.js:366-384).
  // Our dialog is purely synchronous and in-memory — no async setup — so report
  // ready immediately. (Without this, glkote_init throws TypeError and the VM
  // never starts.)
  inited() { return true }
  // Referenced by glkote_init's (now-skipped) init block (glkote.js:381). A
  // no-op satisfies the reference; there is nothing to set up.
  init() {}
  autosave_write(signature, snapshot) { post('autosave', snapshot ? JSON.stringify(snapshot) : null) }
  autosave_read(signature) { return pendingAutosave }

  // Sanitize a game-supplied fixed filename (glk_fileref_create_by_name) into a
  // stable key. Real GlkOte's Dialog provides this; WITHOUT it the call throws
  // and games that open a by-name file at startup (Counterfeit Monkey) crash
  // before booting (glkapi.js:5101).
  file_clean_fixed_name(filename, filetype) {
    let name = String(filename == null ? '' : filename).replace(/[\/\\:*?"<>| -]/g, '-')
    name = name.replace(/^[.\-]+/, '')
    return name || 'null'
  }

  // A temporary fileref (glk_fileref_create_temp). Session-only, in-memory.
  file_construct_temp_ref(usage) { return { filename: '*temp*' + (tempRefCounter++), usage: usage } }

  // Carry the real filename through so file I/O routes to the right store: the
  // save slot (usage 'save') vs a named file (its own key). The SAVE prompt path
  // passes ('save', 'save', …); by-name/temp files pass their cleaned name.
  file_construct_ref(filename, usage, gameid) { return { filename: filename, usage: usage, gameid: gameid } }

  // Route by backing store. A missing/odd ref degrades to "no file" rather than
  // throwing, so an unexpected Glk call can't kill the VM.
  file_ref_exists(ref) {
    if (isSaveRef(ref)) return saveSlot != null
    const key = ref && ref.filename
    return key != null && namedFiles[key] != null
  }
  // Return a copy so the VM can't mutate our canonical store in place.
  file_read(ref) {
    if (isSaveRef(ref)) return saveSlot != null ? saveSlot.slice() : null
    const key = ref && ref.filename
    return (key != null && namedFiles[key] != null) ? namedFiles[key].slice() : null
  }
  // glkapi opens a write file by truncating (empty string / israw), then writes
  // the byte array on close. For the save slot, only mirror real bytes to Swift
  // (the transient empty would just be overwritten a microtask later).
  file_write(ref, content, israw) {
    if (isSaveRef(ref)) {
      if (israw || typeof content === 'string') { saveSlot = []; return true }
      saveSlot = content.slice()
      post('savewrite', bytesToB64(saveSlot))
      return true
    }
    const key = (ref && ref.filename) || '*anon*'
    namedFiles[key] = (israw || typeof content === 'string') ? [] : content.slice()
    return true
  }
  file_remove_ref(ref) {
    if (isSaveRef(ref)) { saveSlot = null; post('savedelete'); return }
    const key = ref && ref.filename
    if (key != null) delete namedFiles[key]
  }
}

async function storyBytes() {
  const r = await fetch('glk://app/file/storyfile')
  return new Uint8Array(await r.arrayBuffer())
}

// Extract the executable chunk (GLUL / ZCOD) from a Blorb by walking its IFF
// chunk list. A speech reader doesn't render Blorb graphics/sound, so the bare
// game image is all the VM needs. Returns null for a non-Blorb (raw .ulx/.z*).
function blorbExec(u8, type) {
  const tag = (o) => String.fromCharCode(u8[o], u8[o + 1], u8[o + 2], u8[o + 3])
  const be = (o) => ((u8[o] << 24) | (u8[o + 1] << 16) | (u8[o + 2] << 8) | u8[o + 3]) >>> 0
  if (u8.length < 12 || tag(0) !== 'FORM' || tag(8) !== 'IFRS') return null
  let pos = 12
  while (pos + 8 <= u8.length) {
    const ctype = tag(pos)
    const clen = be(pos + 4)
    if (ctype === type) return u8.subarray(pos + 8, pos + 8 + clen)
    pos += 8 + clen + (clen & 1)   // chunks are padded to an even length
  }
  return null
}

// engine: 'zvm' (Z-machine) or 'quixe' (Glulx). The restore snapshot (if any) is
// served by Swift at /restore so we can JSON.parse it before prepare() — ZVM's
// autosave_read is synchronous, so the snapshot must be in hand up front.
window.glkStart = async function (engine, onDark) {
  dictionOnDark = !!onDark
  try {
    const restoreResp = await fetch('glk://app/restore')
    const restoreText = restoreResp.ok ? await restoreResp.text() : ''
    pendingAutosave = restoreText.length ? JSON.parse(restoreText) : null
    // Seed the manual SAVE slot from Swift's SaveStorage (raw bytes, or 404 when
    // the game has no save). file_read returns this synchronously, so it has to
    // be in hand before the VM can RESTORE.
    const saveResp = await fetch('glk://app/savedata')
    saveSlot = saveResp.ok
      ? Array.from(new Uint8Array(await saveResp.arrayBuffer()))
      : null
    blorb = new window.BlorbClass()
    installGlkOte()
    dialog = new BridgeDialog()
    const Glk = window.Glk
    let image = await storyBytes()
    // Unwrap a Blorb to the bare game image the VM expects (Glulx → GLUL,
    // Z-machine → ZCOD); raw story files pass through unchanged. When the story
    // IS a Blorb container, initialise the Blorb with the FULL bytes first so
    // get_image_url can resolve picture resources for graphics rendering — the
    // canonical loader does the same (gi_load.js:586). blorb_init's blorbbytes
    // branch indexes the byte array directly and uses .length/.slice (gi_blorb
    // .js:248-275), all valid on the Uint8Array storyBytes() returns, so no
    // Array.from is needed. Without the `format:'blorbbytes'` opt, init would
    // treat the bytes as a resource-object array (gi_blorb.js:219) and corrupt.
    const exec = blorbExec(image, engine === 'quixe' ? 'GLUL' : 'ZCOD')
    if (exec) {
      try { if (!(blorb.inited && blorb.inited())) blorb.init(image, { format: 'blorbbytes' }) }
      catch (e) { post('error', 'blorb init: ' + String((e && e.stack) || e)) }
      image = exec
    }

    if (engine === 'zvm') {
      const vm = new window.ZVM()
      const GiDispa = window.GiDispa   // the ZVMDispatch instance from zvm_dispatch.js
      GiDispa.init = (opts) => GiDispa.set_vm(opts.vm)   // adapt old set_vm to glkapi's init()
      const options = { vm, Glk, Dialog: dialog, GiDispa, Blorb: blorb, GlkOte: glkote, do_vm_autosave: true }
      vm.prepare(image, options)
      Glk.init(options)
    } else if (engine === 'quixe') {
      const vm = window.Quixe                          // Quixe is a singleton object
      const GiDispa = new window.GiDispaClass()        // Quixe's own dispatch
      if (typeof GiDispa.init !== 'function' && typeof GiDispa.set_vm === 'function') {
        GiDispa.init = (opts) => GiDispa.set_vm(opts.vm)
      }
      // Quixe reads the Glk lib from options.io and wants GiLoad; Dialog is
      // resolved via GlkOte.getlibrary('Dialog').
      const options = {
        vm, io: Glk, Glk, Dialog: dialog, GiDispa, GiLoad: window.GiLoad,
        Blorb: blorb, GlkOte: glkote, do_vm_autosave: true, image,
      }
      vm.init(image, options)
      Glk.init(options)
    } else {
      post('error', 'unknown engine: ' + engine)
    }
  } catch (e) {
    post('error', String((e && e.stack) || e))
  }
}

// Native input (the SwiftUI bar) is fed straight into glkapi's input handling,
// the same RemGlk line/char/etc. events the real GlkOte would otherwise send.
// We route through getinterface().accept (== glkapi's accept_ui_event) rather
// than driving GlkOte's hidden <input> element: Diction owns input, GlkOte's in-
// page fields are CSS-hidden, and glkapi echoes the line into the buffer window
// itself, so the rendered transcript stays correct. The real GlkOte has no
// accept_func property (that was the old stub); getinterface() returns the iface
// glkapi passed at init (glkote.js:1763-1765), whose accept is accept_ui_event.
window.glkSendEvent = function (json) {
  if (!glkote) { post('error', 'event before ready'); return }
  try {
    const iface = glkote.getinterface()
    if (!iface || !iface.accept) { post('error', 'event before init'); return }
    const ev = JSON.parse(json)
    // Stamp with the generation GlkOte last rendered (== glkapi's current
    // event_generation). Swift's tracked gen goes stale whenever real GlkOte
    // emits an arrange/refresh event between turns — the keyboard or input bar
    // resizing the WebView advances event_generation (glkapi.js:142) — and glkapi
    // then SILENTLY drops an input whose gen doesn't match (glkapi.js:138), so the
    // game never progresses. The old headless stub used fixed metrics and never
    // resized, so this desync is new. lastGen always matches what glkapi expects.
    if (ev && typeof ev === 'object' && lastGen != null) ev.gen = lastGen
    iface.accept(ev)
  } catch (e) { post('error', 'event: ' + String((e && e.stack) || e)) }
}

window.onerror = (msg, src, line, col, err) => post('error', String((err && err.stack) || msg))
window.addEventListener('unhandledrejection', (ev) => post('error', String((ev.reason && ev.reason.stack) || ev.reason)))

// Double-tap a word in the story buffer to send it to Swift, which appends it to
// the command field (the iOS Frotz typing shortcut). Delegated on document so it
// covers GlkOte's dynamically-created `.BufferWindow`s; the page reloads fresh per
// game, so this re-registers cleanly. Hyperlinks are skipped so the game's keyword
// links still follow on tap. The viewport is `user-scalable=no`, so `dblclick`
// doesn't collide with double-tap zoom.
function wordAround(text, i) {
  if (!text) return ''
  const isWord = (c) => /[\p{L}\p{N}'’-]/u.test(c)
  const n = text.length
  if (i > n) i = n
  // A tap can land just past the word's last character; step back one then.
  if (i >= n || !isWord(text[i])) i = i - 1
  if (i < 0 || !isWord(text[i])) return ''
  let start = i, end = i + 1
  while (start > 0 && isWord(text[start - 1])) start--
  while (end < n && isWord(text[end])) end++
  return text.slice(start, end)
}

document.addEventListener('dblclick', (e) => {
  if (!e.target || !e.target.closest || !e.target.closest('.BufferWindow')) return
  if (e.target.closest('a')) return            // let game keyword/hyperlinks behave
  const range = document.caretRangeFromPoint &&
                document.caretRangeFromPoint(e.clientX, e.clientY)
  const node = range && range.startContainer
  if (!node || node.nodeType !== Node.TEXT_NODE) return
  const word = wordAround(node.textContent, range.startOffset)
  if (!word) return
  post('wordtap', word)
  e.preventDefault()
  const sel = window.getSelection()
  if (sel) sel.removeAllRanges()
})

post('bridge_loaded')

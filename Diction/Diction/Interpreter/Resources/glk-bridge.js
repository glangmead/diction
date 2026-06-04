/* Drives the classic Glk stack (glkapi + per-VM dispatch + ZVM/Quixe) headlessly
 * in a WKWebView. Forwards GlkOte-protocol updates and the VM's own autosave
 * bytes to Swift, and answers save/restore fileref prompts itself (single slot,
 * mirrored to Swift's SaveStorage). Mirrors the Swift-facing protocol the
 * previous bridge used so InterpreterSession is unchanged.
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

const METRICS = {
  width: 80, height: 50, buffercharwidth: 1, buffercharheight: 1,
  gridcharwidth: 1, gridcharheight: 1, buffermarginx: 0, buffermarginy: 0, gridmarginx: 0, gridmarginy: 0,
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

// Headless GlkOte: the 7-method interface glkapi actually calls. Sends the init
// event itself (no display layer to supply metrics), forwards updates to Swift.
class BridgeGlkOte {
  constructor() { this.accept_func = () => {}; this.is_inited = false }
  init(iface) {
    this.accept_func = iface.accept
    this.is_inited = true
    setTimeout(() => this.accept_func({ type: 'init', gen: 0, metrics: METRICS, support: ['timer', 'hyperlinks'] }), 0)
  }
  update(data) {
    // The game's SAVE/RESTORE verbs surface as a fileref_prompt specialinput.
    // Answer it ourselves (single slot, no user filename) and DON'T forward this
    // update — Swift never sees the prompt, so its input model is unchanged and
    // send("save") just resolves on the resulting "Ok." update. Deferred by a
    // microtask so the current glkapi cycle unwinds before we re-enter accept().
    const special = data.specialinput
    if (special && special.type === 'fileref_prompt') {
      const gen = data.gen
      Promise.resolve().then(() => answerFileref(special, gen))
      return
    }
    // glkapi's select posts the display update, THEN runs do_vm_autosave
    // synchronously. Defer our update post by a microtask so it reaches Swift
    // AFTER the move's autosave message — otherwise send() resolves on the
    // update with the previous turn's snapshot still latest, and a restore lands
    // one move stale.
    const shimmed = shimUpdate(data)
    Promise.resolve().then(() => post('update', shimmed))
  }
  save_allstate() { return {} }   // display is restored from Swift's presentation snapshot
  // glkapi.getlibrary delegates here; Quixe resolves its Dialog (for autosave)
  // via GlkOte.getlibrary('Dialog'), so we must return it.
  getlibrary(name) { return name === 'Blorb' ? blorb : name === 'Dialog' ? dialog : null }
  getinterface() { return {} }
  inited() { return this.is_inited }
  log() {}
  warning() {}
  error(msg) { post('error', String(msg)) }
  getdomcontext() { return null }
  setdomcontext() {}
}

// Answer a fileref_prompt the game raised for its SAVE/RESTORE verb. Single
// slot, so we construct the ref ourselves rather than asking the user for a
// name. The gen MUST match the prompt's update generation or glkapi silently
// drops the event (accept_ui_event's generation guard). Only the `save` filetype
// is backed by a slot; transcript/command/data prompts are cancelled (null ref),
// which makes the game print its own "cancelled" message.
function answerFileref(special, gen) {
  if (!glkote) return
  const ref = special.filetype === 'save'
    ? dialog.file_construct_ref('save', special.filetype, special.gameid)
    : null
  glkote.accept_func({ type: 'specialresponse', response: 'fileref_prompt', value: ref, gen })
}

// Dialog: autosave routes to/from Swift (the resume mechanism); the synchronous
// fileref API backs the game's own SAVE/RESTORE verb with a single in-memory
// slot (`saveSlot`), seeded from and mirrored to Swift's SaveStorage.
class BridgeDialog {
  constructor() { this.streaming = false }
  autosave_write(signature, snapshot) { post('autosave', snapshot ? JSON.stringify(snapshot) : null) }
  autosave_read(signature) { return pendingAutosave }

  // Single slot: the filename is ignored. A non-null ref signals "slot exists to
  // open"; glkapi/ZVM then call file_read / file_write on it.
  file_construct_ref(filename, usage, gameid) { return { filename: 'save', usage: usage, gameid: gameid } }
  file_ref_exists() { return saveSlot != null }
  // Return a copy so the VM can't mutate our canonical slot in place.
  file_read() { return saveSlot != null ? saveSlot.slice() : null }
  // glkapi opens a write file by truncating (empty string, israw), then writes
  // the byte array on close. Reset the slot on truncate but only mirror real
  // bytes to Swift — persisting the transient empty would just be overwritten a
  // microtask later.
  file_write(ref, content, israw) {
    if (israw || typeof content === 'string') { saveSlot = []; return true }
    saveSlot = content.slice()
    post('savewrite', bytesToB64(saveSlot))
    return true
  }
  file_remove_ref() { saveSlot = null; post('savedelete') }
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
window.glkStart = async function (engine) {
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
    glkote = new BridgeGlkOte()
    dialog = new BridgeDialog()
    const Glk = window.Glk
    let image = await storyBytes()
    // Unwrap a Blorb to the bare game image the VM expects (Glulx → GLUL,
    // Z-machine → ZCOD); raw story files pass through unchanged.
    const exec = blorbExec(image, engine === 'quixe' ? 'GLUL' : 'ZCOD')
    if (exec) image = exec

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

window.glkSendEvent = function (json) {
  if (!glkote) { post('error', 'event before ready'); return }
  try { glkote.accept_func(JSON.parse(json)) } catch (e) { post('error', 'event: ' + String((e && e.stack) || e)) }
}

window.onerror = (msg, src, line, col, err) => post('error', String((err && err.stack) || msg))
window.addEventListener('unhandledrejection', (ev) => post('error', String((ev.reason && ev.reason.stack) || ev.reason)))
post('bridge_loaded')

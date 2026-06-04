/* Drives the classic Glk stack (glkapi + per-VM dispatch + ZVM/Quixe) headlessly
 * in a WKWebView. Forwards GlkOte-protocol updates to Swift and routes the VM's
 * own autosave bytes (and fileref prompts) to Swift. Mirrors the Swift-facing
 * protocol of the old emglken bridge so InterpreterSession is unchanged.
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
    // glkapi's select posts the display update, THEN runs do_vm_autosave
    // synchronously. Defer our update post by a microtask so it reaches Swift
    // AFTER the move's autosave message — otherwise send() resolves on the
    // update with the previous turn's snapshot still latest, and a restore lands
    // one move stale.
    const shimmed = shimUpdate(data)
    const special = data.specialinput ? JSON.stringify(data.specialinput) : null
    Promise.resolve().then(() => {
      post('update', shimmed)
      if (special) post('specialinput', special)
    })
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

// Dialog: autosave routes to/from Swift; the classic fileref (manual SAVE) API
// is stubbed for now — autosave is the resume mechanism. (Follow-up: bridge the
// synchronous fileref API to SaveStorage.)
class BridgeDialog {
  constructor() { this.streaming = false }
  autosave_write(signature, snapshot) { post('autosave', snapshot ? JSON.stringify(snapshot) : null) }
  autosave_read(signature) { return pendingAutosave }
  // Minimal fileref surface so glkapi/Blorb don't choke if they probe it.
  file_construct_ref() { return null }
  file_ref_exists() { return false }
  file_read() { return null }
  file_write() { return false }
  file_remove_ref() {}
}

async function storyBytes() {
  const r = await fetch('emglken://app/file/storyfile')
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
    const restoreResp = await fetch('emglken://app/restore')
    const restoreText = restoreResp.ok ? await restoreResp.text() : ''
    pendingAutosave = restoreText.length ? JSON.parse(restoreText) : null
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

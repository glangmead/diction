/* Drives an emglken interpreter headlessly: a raw-JSON GlkOte that forwards
 * every RemGlk update to Swift (and signals fileref prompts), plus a Dialog
 * that routes all file I/O to Swift by basename. Swift answers fileref prompts
 * and decides on-disk placement; this bridge holds no save policy. */
const STORY_PATH = '/storyfile'
function post(stage, payload) {
  try { window.webkit.messageHandlers.interp.postMessage({ stage, payload: payload ?? null }) } catch (e) {}
}
// 1x1 chars + zero margins: the standard "dumb terminal" metrics RemGlk needs
// to lay out windows when there is no real display.
const METRICS = {
  width: 80, height: 50, buffercharwidth: 1, buffercharheight: 1,
  gridcharwidth: 1, gridcharheight: 1, buffermarginx: 0, buffermarginy: 0,
  gridmarginx: 0, gridmarginy: 0,
}
function b64encode(u8) {
  let s = ''; const chunk = 0x8000
  for (let i = 0; i < u8.length; i += chunk) s += String.fromCharCode.apply(null, u8.subarray(i, i + chunk))
  return btoa(s)
}
class BridgeGlkOte {
  constructor() {
    this.classname = 'GlkOte'; this.version = '3.0.0'; this.is_inited = false
    this.accept_func = () => {}; this.Dialog = null; this.Blorb = null; this.options = {}
  }
  async init(options) {
    this.options = options; this.accept_func = options.accept
    this.Dialog = options.Dialog; this.Blorb = options.Blorb; this.is_inited = true
    // We are the host: send the init+metrics event on a fresh tick, out of the
    // VM's init call stack. This produces the first update.
    setTimeout(() => this.accept_func({ type: 'init', gen: 0, metrics: METRICS, support: ['timer', 'hyperlinks'] }), 0)
  }
  update(data) {
    post('update', data)
    if (data.specialinput) post('specialinput', JSON.stringify(data.specialinput))
  }
  getlibrary(name) { return name === 'Dialog' ? this.Dialog : name === 'Blorb' ? this.Blorb : null }
  getinterface() { return this.options }
  inited() { return this.is_inited }
  log() {}
  getdomcontext() { return null }
  setdomcontext() {}
}
class BridgeDialog {
  constructor() { this.async = true }
  async init() {}
  async exists(path) {
    if (path === STORY_PATH) return true
    try { return (await fetch('emglken://app/save/' + path.split('/').pop())).ok } catch (e) { return false }
  }
  async read(path) {
    const url = path === STORY_PATH ? 'emglken://app/file/storyfile' : 'emglken://app/save/' + path.split('/').pop()
    try { const r = await fetch(url); if (!r.ok) return null; return new Uint8Array(await r.arrayBuffer()) }
    catch (e) { return null }
  }
  async write(files) {
    for (const [path, data] of Object.entries(files)) {
      const u8 = data instanceof Uint8Array ? data : new Uint8Array(data)
      post('save_bytes', { name: path.split('/').pop(), b64: b64encode(u8) })
    }
  }
  async delete() {}
  get_dirs() { return { storyfile: '/', system_cwd: '/', temp: '/', working: '/' } }
  set_storyfile_dir() { return { storyfile: '/', working: '/' } }
  prompt() { return null }
}
let glkote = null
window.emglkenStart = async function (engineFile) {
  try {
    const engine = (await import('./' + engineFile)).default
    const vm = await engine()
    glkote = new BridgeGlkOte()
    vm.start({ arguments: [STORY_PATH], Dialog: new BridgeDialog(), GlkOte: glkote })
  } catch (e) { post('error', String((e && e.stack) || e)) }
}
window.emglkenSendEvent = function (json) {
  if (!glkote) { post('error', 'event before ready'); return }
  try { glkote.accept_func(JSON.parse(json)) } catch (e) { post('error', 'event: ' + String((e && e.stack) || e)) }
}
window.onerror = (msg, src, line, col, err) => post('error', String((err && err.stack) || msg))
window.addEventListener('unhandledrejection', (ev) => post('error', String((ev.reason && ev.reason.stack) || ev.reason)))
post('bridge_loaded')


import std/[os, strutils, times, tables, sequtils, options]
import pixie
import ./core/dom
import ./core/html_parser
import ./core/animation
import ./css/resolver
import ./layout/engine
import ./render/painter
import ./platform/window
import ./script/jsbridge

export dom, resolver, painter, window, animation, jsbridge

type
  NimaxEngine* = ref object
    document*: Node
    styleResolver*: StyleResolver
    layoutCtx*: LayoutContext
    animEngine*: AnimationEngine
    renderState*: RenderState
    window*: NimaxWindow
    jsEngine*: pointer
    sheets*: seq[StyleSheet]
    viewportWidth*, viewportHeight*: float32
    rootFontSize*: float32
    title*: string
    baseUrl*: string

proc newNimaxEngine*(width = 1280, height = 720): NimaxEngine =
  let doc = newDocument()
  let html = newElement("html")
  let head = newElement("head")
  let body = newElement("body")
  html.appendChild(head)
  html.appendChild(body)
  doc.appendChild(html)
  result = NimaxEngine(
    document: doc,
    styleResolver: newStyleResolver(),
    layoutCtx: newLayoutContext(width.float32, height.float32),
    animEngine: newAnimationEngine(),
    renderState: newRenderState(width, height),
    sheets: @[],
    viewportWidth: width.float32,
    viewportHeight: height.float32,
    rootFontSize: 16.0,
    title: "NiMax"
  )
  result.styleResolver.viewportWidth = width.float32
  result.styleResolver.viewportHeight = height.float32

proc loadHtml*(eng: NimaxEngine, html: string) =
  eng.document = parseHtml(html)
  let css = extractStyles(eng.document)
  if css.len > 0:
    let sheet = parseStyleSheet(css)
    eng.sheets.add(sheet)
    eng.styleResolver.addStyleSheet(sheet)
  eng.styleResolver.resolveStyles(eng.document)

proc loadHtmlFile*(eng: NimaxEngine, path: string) =
  eng.loadHtml(readFile(path))

proc addStyleSheet*(eng: NimaxEngine, css: string) =
  let sheet = parseStyleSheet(css)
  eng.sheets.add(sheet)
  eng.styleResolver.addStyleSheet(sheet)

proc addStyleFile*(eng: NimaxEngine, path: string) =
  eng.addStyleSheet(readFile(path))

proc layout*(eng: NimaxEngine) =
  eng.styleResolver.resolveStyles(eng.document)
  eng.layoutCtx.layout(eng.document)

proc paint*(eng: NimaxEngine): Image =
  eng.renderState.render(eng.document)
  eng.renderState.getImage()

proc renderToFile*(eng: NimaxEngine, path: string) =
  eng.layout()
  let img = eng.paint()
  img.writeFile(path)

proc enableJs*(eng: NimaxEngine) =
  when not defined(noQuickJs):
    from ./script/qjsengine import newQJSEngine, injectDOMContentLoaded, eval, QJSEngine
    let jsEng = newQJSEngine(eng.document)
    jsEng.onRender = proc() =
      eng.styleResolver.resolveStyles(eng.document)
      eng.layoutCtx.layout(eng.document)
      if eng.window != nil: eng.window.needsPaint = true
    jsEng.onNavigate = proc(url: string) =
      echo "[navigate] " & url
    jsEng.onTitleChange = proc(title: string) =
      eng.title = title
      if eng.window != nil: eng.window.title = title
    eng.jsEngine = cast[pointer](jsEng)
    let scripts = extractScripts(eng.document)
    for script in scripts:
      if script.strip().len > 0:
        discard jsEng.eval(script, "<inline-script>")
    jsEng.injectDOMContentLoaded()

proc runJs*(eng: NimaxEngine, code: string): string =
  if eng.jsEngine == nil: return ""
  when not defined(noQuickJs):
    from ./script/qjsengine import QJSEngine, eval
    return cast[QJSEngine](eng.jsEngine).eval(code)
  ""

proc registerNativeProc*(eng: NimaxEngine, name: string, cb: NativeCallback) =
  if eng.jsEngine != nil:
    when not defined(noQuickJs):
      from ./script/qjsengine import QJSEngine
      cast[QJSEngine](eng.jsEngine).bridge.registerNative(name, cb)

proc openWindow*(eng: NimaxEngine, config: WindowConfig = defaultConfig()) =
  let win = newNimaxWindow(config, eng.document)
  win.styleResolver = eng.styleResolver
  win.renderState = eng.renderState
  win.layoutCtx = eng.layoutCtx
  win.animEngine = eng.animEngine
  if eng.jsEngine != nil:
    when not defined(noQuickJs):
      from ./script/qjsengine import QJSEngine
      let jsEng = cast[QJSEngine](eng.jsEngine)
      jsEng.onRender = proc() =
        win.needsLayout = true
        win.needsPaint = true
  eng.window = win
  win.bridge.onRenderRequest = proc() =
    win.needsLayout = true
    win.needsPaint = true
  when defined(nimaxGlfw):
    win.runGlfwLoop(eng.jsEngine)
  else:
    win.runOffscreen(eng.jsEngine)

proc renderOffscreen*(eng: NimaxEngine, frames = 1) =
  if eng.window == nil:
    let win = newNimaxWindow(defaultConfig(
      int(eng.viewportWidth), int(eng.viewportHeight)), eng.document)
    win.styleResolver = eng.styleResolver
    win.renderState = eng.renderState
    win.layoutCtx = eng.layoutCtx
    win.animEngine = eng.animEngine
    eng.window = win
  eng.window.runOffscreen(eng.jsEngine, frames)

proc saveImage*(eng: NimaxEngine, path: string) =
  eng.layout()
  let img = eng.paint()
  img.writeFile(path)

when isMainModule:
  import std/[parseopt, cmdline]

  proc printUsage() =
    echo """NiMax UI Engine v1.0
Usage: nimax [options] <file.html>

Options:
  --width=N       Viewport width (default: 1280)
  --height=N      Viewport height (default: 720)
  --out=file.png  Render to PNG (headless)
  --js            Enable JavaScript engine
  --window        Open native window (requires GLFW build)
  --title=TEXT    Window title
  --scale=N       HiDPI scale factor (default: 1.0)
  --help          Show this help

Examples:
  nimax --out=out.png index.html
  nimax --window --js index.html
  nimax --width=800 --height=600 --out=screenshot.png app.html
"""

  var
    inputFile = ""
    outFile = ""
    width = 1280
    height = 720
    useJs = false
    useWindow = false
    title = "NiMax"
    scale = 1.0f32

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "width":  width  = try: parseInt(p.val) except: 1280
      of "height": height = try: parseInt(p.val) except: 720
      of "out":    outFile = p.val
      of "js":     useJs = true
      of "window": useWindow = true
      of "title":  title = p.val
      of "scale":  scale = try: parseFloat(p.val).float32 except: 1.0
      of "help", "h":
        printUsage()
        quit(0)
      else: discard
    of cmdArgument:
      inputFile = p.key

  if inputFile.len == 0:
    echo "NiMax v1.0 - High-performance embeddable UI engine"
    echo "Run with --help for usage"
    quit(0)

  if not fileExists(inputFile):
    echo "Error: file not found: " & inputFile
    quit(1)

  let eng = newNimaxEngine(width, height)
  eng.title = title
  eng.loadHtmlFile(inputFile)

  if useJs:
    eng.enableJs()

  if outFile.len > 0:
    echo "Rendering " & inputFile & " -> " & outFile
    let t0 = epochTime()
    eng.renderOffscreen(1)
    eng.saveImage(outFile)
    echo "Done in " & $(epochTime() - t0) & "s"
  elif useWindow:
    var cfg = defaultConfig(width, height, title)
    cfg.scale = scale
    eng.openWindow(cfg)
  else:
    echo "Rendering offscreen..."
    eng.renderOffscreen(1)
    let outPath = inputFile.changeFileExt("png")
    eng.saveImage(outPath)
    echo "Saved to " & outPath

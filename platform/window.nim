import std/[times, tables, strutils, os]
import pixie
import ../core/dom
import ../core/animation
import ../css/resolver
import ../layout/engine
import ../render/painter
import ../script/jsbridge

proc fireTimersInEngine(jsEng: pointer) =
  when not defined(noQuickJs):
    from ../script/qjsengine import QJSEngine, fireTimers
    cast[QJSEngine](jsEng).fireTimers()

proc injectKeyEventToEngine(jsEng: pointer, kind, key: string, code: int, ctrl, shift, alt: bool) =
  when not defined(noQuickJs):
    from ../script/qjsengine import QJSEngine, injectKeyEvent
    cast[QJSEngine](jsEng).injectKeyEvent(kind, key, code, ctrl, shift, alt)

type
  KeyMod* {.pure.} = enum
    Shift, Ctrl, Alt, Super

  KeyAction* {.pure.} = enum
    Press, Release, Repeat

  MouseAction* {.pure.} = enum
    Press, Release

  WindowConfig* = object
    width*, height*: int
    title*: string
    resizable*: bool
    decorated*: bool
    transparent*: bool
    scale*: float32
    minWidth*, minHeight*: int
    maxWidth*, maxHeight*: int

  NimaxWindow* = ref object
    config*: WindowConfig
    dom*: Node
    styleResolver*: StyleResolver
    renderState*: RenderState
    layoutCtx*: LayoutContext
    animEngine*: AnimationEngine
    bridge*: JsBridge
    width*, height*: int
    scale*: float32
    mouseX*, mouseY*: float32
    hoveredNode*: Node
    focusedNode*: Node
    pressedNode*: Node
    frameBuffer*: seq[uint8]
    lastFrameTime*: float64
    frameCount*: uint64
    fps*: float32
    needsLayout*: bool
    needsPaint*: bool
    title*: string
    closed*: bool
    onFrame*: proc(win: NimaxWindow) {.closure.}
    onResize*: proc(win: NimaxWindow, w, h: int) {.closure.}
    onClose*: proc(win: NimaxWindow) {.closure.}

proc defaultConfig*(width = 1280, height = 720, title = "NiMax"): WindowConfig =
  WindowConfig(
    width: width, height: height,
    title: title,
    resizable: true,
    decorated: true,
    transparent: false,
    scale: 1.0,
    minWidth: 0, minHeight: 0,
    maxWidth: 0, maxHeight: 0
  )

proc newNimaxWindow*(config: WindowConfig, dom: Node): NimaxWindow =
  let rs = newRenderState(config.width, config.height, config.scale)
  result = NimaxWindow(
    config: config,
    dom: dom,
    renderState: rs,
    layoutCtx: newLayoutContext(config.width.float32, config.height.float32),
    animEngine: newAnimationEngine(),
    bridge: newJsBridge(dom),
    width: config.width,
    height: config.height,
    scale: config.scale,
    needsLayout: true,
    needsPaint: true,
    title: config.title,
    frameBuffer: newSeq[uint8](config.width * config.height * 4)
  )
  result.renderState.viewportWidth = config.width.float32
  result.renderState.viewportHeight = config.height.float32

proc invalidate*(win: NimaxWindow) =
  win.needsLayout = true
  win.needsPaint = true

proc layout*(win: NimaxWindow) =
  if not win.needsLayout: return
  let resolver = if win.styleResolver != nil: win.styleResolver else: newStyleResolver()
  resolver.viewportWidth = win.width.float32
  resolver.viewportHeight = win.height.float32
  resolver.resolveStyles(win.dom)
  win.layoutCtx.viewportWidth = win.width.float32
  win.layoutCtx.viewportHeight = win.height.float32
  win.layoutCtx.layout(win.dom)
  win.needsLayout = false

proc paint*(win: NimaxWindow) =
  if not win.needsPaint: return
  win.renderState.focusedNode = win.focusedNode
  win.renderState.hoveredNode = win.hoveredNode
  win.renderState.render(win.dom)
  let img = win.renderState.getImage()
  let px = img.data
  let stride = win.width * 4
  for y in 0..<win.height:
    for x in 0..<win.width:
      let src = y * win.width + x
      let dst = y * stride + x * 4
      if src < px.len:
        let c = px[src]
        win.frameBuffer[dst + 0] = c.r
        win.frameBuffer[dst + 1] = c.g
        win.frameBuffer[dst + 2] = c.b
        win.frameBuffer[dst + 3] = c.a
  win.needsPaint = false
  inc win.frameCount

proc frame*(win: NimaxWindow) =
  let t = epochTime()
  if win.animEngine.tick():
    win.needsLayout = true
    win.needsPaint = true
  win.layout()
  win.paint()
  let dt = epochTime() - t
  if dt > 0:
    win.fps = win.fps * 0.9 + (1.0 / dt).float32 * 0.1

proc hitTest*(win: NimaxWindow, x, y: float32): Node =
  proc hit(node: Node, ox, oy: float32): Node =
    if node.kind != nkElement: return nil
    if node.computedStyle == nil: return nil
    if node.computedStyle.display == dkNone: return nil
    if node.computedStyle.pointerEvents == peNone: return nil
    let box = node.layoutBox
    if box == nil: return nil
    let bx = ox + box.x
    let by = oy + box.y
    if x < bx or x > bx + box.borderWidth or y < by or y > by + box.borderHeight:
      return nil
    for i in countdown(node.children.len - 1, 0):
      let child = node.children[i]
      if child.kind == nkElement:
        let r = hit(child, bx, by)
        if r != nil: return r
    node
  hit(win.dom, 0, 0)

proc handleMouseMove*(win: NimaxWindow, x, y: float32) =
  win.mouseX = x
  win.mouseY = y
  let node = win.hitTest(x, y)
  if node != win.hoveredNode:
    if win.hoveredNode != nil:
      let ev = Event(kind: evMouseLeave, target: win.hoveredNode,
                     currentTarget: win.hoveredNode, x: x, y: y, bubbles: false)
      discard win.hoveredNode.dispatchEvent(ev)
      for tr in win.hoveredNode.computedStyle.transition:
        discard
    win.hoveredNode = node
    if node != nil:
      let ev = Event(kind: evMouseEnter, target: node,
                     currentTarget: node, x: x, y: y, bubbles: false)
      discard node.dispatchEvent(ev)
  if node != nil:
    let ev = Event(kind: evMouseMove, target: node, currentTarget: node,
                   x: x, y: y, bubbles: true, cancelable: true)
    discard node.dispatchEvent(ev)
  win.needsPaint = true

proc handleMouseDown*(win: NimaxWindow, x, y: float32, button: MouseButton) =
  let node = win.hitTest(x, y)
  win.pressedNode = node
  if node != nil:
    if win.focusedNode != node:
      if win.focusedNode != nil:
        win.focusedNode.focused = false
        let blurEv = Event(kind: evBlur, target: win.focusedNode,
                           currentTarget: win.focusedNode, bubbles: false)
        discard win.focusedNode.dispatchEvent(blurEv)
      win.focusedNode = node
      node.focused = true
      let focusEv = Event(kind: evFocus, target: node,
                          currentTarget: node, bubbles: false)
      discard node.dispatchEvent(focusEv)
    let ev = Event(kind: evMouseDown, target: node, currentTarget: node,
                   x: x, y: y, button: button, bubbles: true, cancelable: true)
    discard node.dispatchEvent(ev)
  win.needsPaint = true

proc handleMouseUp*(win: NimaxWindow, x, y: float32, button: MouseButton) =
  let node = win.hitTest(x, y)
  if node != nil:
    let ev = Event(kind: evMouseUp, target: node, currentTarget: node,
                   x: x, y: y, button: button, bubbles: true, cancelable: true)
    discard node.dispatchEvent(ev)
    if win.pressedNode == node or win.pressedNode != nil:
      let clickEv = Event(kind: evClick, target: node, currentTarget: node,
                          x: x, y: y, button: button, bubbles: true, cancelable: true)
      discard node.dispatchEvent(clickEv)
  win.pressedNode = nil
  win.needsPaint = true

proc handleKeyDown*(win: NimaxWindow, key: string, keyCode: int32,
                     modShift, modCtrl, modAlt: bool) =
  let target = if win.focusedNode != nil: win.focusedNode else: win.dom
  let ev = Event(kind: evKeyDown, target: target, currentTarget: target,
                  key: key, keyCode: keyCode,
                  modShift: modShift, modCtrl: modCtrl, modAlt: modAlt,
                  bubbles: true, cancelable: true)
  discard target.dispatchEvent(ev)
  if not ev.defaultPrevented:
    if win.focusedNode != nil and win.focusedNode.tag in ["input","textarea"]:
      if key.len == 1 and key[0] >= ' ':
        win.focusedNode.value.add(key)
        let inputEv = Event(kind: evInput, target: win.focusedNode,
                             currentTarget: win.focusedNode, bubbles: true)
        discard win.focusedNode.dispatchEvent(inputEv)
      elif keyCode == 8 and win.focusedNode.value.len > 0:
        win.focusedNode.value = win.focusedNode.value[0..^2]
        let inputEv = Event(kind: evInput, target: win.focusedNode,
                             currentTarget: win.focusedNode, bubbles: true)
        discard win.focusedNode.dispatchEvent(inputEv)
      elif keyCode == 13:
        let submitEv = Event(kind: evSubmit, target: win.focusedNode,
                              currentTarget: win.focusedNode, bubbles: true)
        discard win.focusedNode.dispatchEvent(submitEv)
  win.needsPaint = true

proc handleKeyUp*(win: NimaxWindow, key: string, keyCode: int32,
                   modShift, modCtrl, modAlt: bool) =
  let target = if win.focusedNode != nil: win.focusedNode else: win.dom
  let ev = Event(kind: evKeyUp, target: target, currentTarget: target,
                  key: key, keyCode: keyCode,
                  modShift: modShift, modCtrl: modCtrl, modAlt: modAlt,
                  bubbles: true, cancelable: true)
  discard target.dispatchEvent(ev)
  win.needsPaint = true

proc handleScroll*(win: NimaxWindow, x, y, dx, dy: float32) =
  let node = win.hitTest(x, y)
  if node != nil:
    node.scrollX = max(0, node.scrollX + dx)
    node.scrollY = max(0, node.scrollY + dy)
    let ev = Event(kind: evScroll, target: node, currentTarget: node,
                   x: x, y: y, bubbles: true)
    discard node.dispatchEvent(ev)
  win.needsLayout = true
  win.needsPaint = true

proc handleResize*(win: NimaxWindow, w, h: int) =
  win.width = w
  win.height = h
  win.layoutCtx.viewportWidth = w.float32
  win.layoutCtx.viewportHeight = h.float32
  win.renderState.viewportWidth = w.float32
  win.renderState.viewportHeight = h.float32
  win.frameBuffer.setLen(w * h * 4)
  let newImg = newImage(w, h)
  win.renderState.ctx = newContext(newImg)
  win.needsLayout = true
  win.needsPaint = true
  if win.onResize != nil: win.onResize(win, w, h)
  # Fire resize event in JS
  when not defined(noQuickJs):
    if win.bridge.onRenderRequest != nil: # We use this as a generic JS bridge access
       discard

when defined(nimaxGlfw):
  import opengl

  type
    GLFWwindow {.importc: "GLFWwindow", header: "<GLFW/glfw3.h>".} = object

  {.passC: "-I/usr/include".}
  {.passL: "-lglfw -lGL -lm -ldl".}

  proc glfwInit(): cint {.importc: "glfwInit", header: "<GLFW/glfw3.h>".}
  proc glfwTerminate() {.importc: "glfwTerminate", header: "<GLFW/glfw3.h>".}
  proc glfwCreateWindow(w, h: cint, title: cstring, monitor: pointer, share: pointer): ptr GLFWwindow {.importc: "glfwCreateWindow", header: "<GLFW/glfw3.h>".}
  proc glfwDestroyWindow(win: ptr GLFWwindow) {.importc: "glfwDestroyWindow", header: "<GLFW/glfw3.h>".}
  proc glfwWindowShouldClose(win: ptr GLFWwindow): cint {.importc: "glfwWindowShouldClose", header: "<GLFW/glfw3.h>".}
  proc glfwSetWindowShouldClose(win: ptr GLFWwindow, v: cint) {.importc: "glfwSetWindowShouldClose", header: "<GLFW/glfw3.h>".}
  proc glfwPollEvents() {.importc: "glfwPollEvents", header: "<GLFW/glfw3.h>".}
  proc glfwSwapBuffers(win: ptr GLFWwindow) {.importc: "glfwSwapBuffers", header: "<GLFW/glfw3.h>".}
  proc glfwMakeContextCurrent(win: ptr GLFWwindow) {.importc: "glfwMakeContextCurrent", header: "<GLFW/glfw3.h>".}
  proc glfwGetFramebufferSize(win: ptr GLFWwindow, w, h: ptr cint) {.importc: "glfwGetFramebufferSize", header: "<GLFW/glfw3.h>".}
  proc glfwGetWindowSize(win: ptr GLFWwindow, w, h: ptr cint) {.importc: "glfwGetWindowSize", header: "<GLFW/glfw3.h>".}
  proc glfwWindowHint(hint, value: cint) {.importc: "glfwWindowHint", header: "<GLFW/glfw3.h>".}
  proc glfwSetWindowTitle(win: ptr GLFWwindow, title: cstring) {.importc: "glfwSetWindowTitle", header: "<GLFW/glfw3.h>".}
  proc glfwGetTime(): float64 {.importc: "glfwGetTime", header: "<GLFW/glfw3.h>".}
  proc glfwSetWindowUserPointer(win: ptr GLFWwindow, p: pointer) {.importc: "glfwSetWindowUserPointer", header: "<GLFW/glfw3.h>".}
  proc glfwGetWindowUserPointer(win: ptr GLFWwindow): pointer {.importc: "glfwGetWindowUserPointer", header: "<GLFW/glfw3.h>".}
  proc glfwSetCursorPosCallback(win: ptr GLFWwindow, cb: pointer) {.importc: "glfwSetCursorPosCallback", header: "<GLFW/glfw3.h>".}
  proc glfwSetMouseButtonCallback(win: ptr GLFWwindow, cb: pointer) {.importc: "glfwSetMouseButtonCallback", header: "<GLFW/glfw3.h>".}
  proc glfwSetKeyCallback(win: ptr GLFWwindow, cb: pointer) {.importc: "glfwSetKeyCallback", header: "<GLFW/glfw3.h>".}
  proc glfwSetScrollCallback(win: ptr GLFWwindow, cb: pointer) {.importc: "glfwSetScrollCallback", header: "<GLFW/glfw3.h>".}
  proc glfwSetWindowSizeCallback(win: ptr GLFWwindow, cb: pointer) {.importc: "glfwSetWindowSizeCallback", header: "<GLFW/glfw3.h>".}
  proc glfwSetCharCallback(win: ptr GLFWwindow, cb: pointer) {.importc: "glfwSetCharCallback", header: "<GLFW/glfw3.h>".}
  proc glfwGetKey(win: ptr GLFWwindow, key: cint): cint {.importc: "glfwGetKey", header: "<GLFW/glfw3.h>".}
  proc glfwGetMouseButton(win: ptr GLFWwindow, button: cint): cint {.importc: "glfwGetMouseButton", header: "<GLFW/glfw3.h>".}

  const
    GLFW_RESIZABLE = 0x00020003
    GLFW_DECORATED = 0x00020005
    GLFW_TRANSPARENT_FRAMEBUFFER = 0x0002000A
    GLFW_CONTEXT_VERSION_MAJOR = 0x00022002
    GLFW_CONTEXT_VERSION_MINOR = 0x00022003
    GLFW_OPENGL_PROFILE = 0x00022008
    GLFW_OPENGL_CORE_PROFILE = 0x00032001
    GLFW_OPENGL_COMPAT_PROFILE = 0x00032002
    GLFW_SAMPLES = 0x0002100D
    GLFW_PRESS = 1
    GLFW_RELEASE = 0
    GLFW_REPEAT = 2

  var gNimaxWindow {.threadvar.}: NimaxWindow
  var gJsEngine {.threadvar.}: pointer

  proc cursorCallback(gwin: ptr GLFWwindow, x, y: float64) {.cdecl.} =
    if gNimaxWindow != nil:
      gNimaxWindow.handleMouseMove(x.float32, y.float32)
      if gNimaxWindow.bridge.onRenderRequest != nil:
        gNimaxWindow.bridge.onRenderRequest()

  proc mouseButtonCallback(gwin: ptr GLFWwindow, button, action, mods: cint) {.cdecl.} =
    if gNimaxWindow != nil:
      let mb = case button
        of 0: mbLeft
        of 1: mbRight
        of 2: mbMiddle
        else: mbLeft
      if action == GLFW_PRESS:
        gNimaxWindow.handleMouseDown(gNimaxWindow.mouseX, gNimaxWindow.mouseY, mb)
      else:
        gNimaxWindow.handleMouseUp(gNimaxWindow.mouseX, gNimaxWindow.mouseY, mb)

  proc glfwKeyToString(key: cint): string =
    if key >= 32 and key <= 126: return $chr(key.int)
    case key
    of 256: "Escape"
    of 257: "Enter"
    of 258: "Tab"
    of 259: "Backspace"
    of 260: "Insert"
    of 261: "Delete"
    of 262: "ArrowRight"
    of 263: "ArrowLeft"
    of 264: "ArrowDown"
    of 265: "ArrowUp"
    of 266: "PageUp"
    of 267: "PageDown"
    of 268: "Home"
    of 269: "End"
    of 290..301: "F" & $(key - 289)
    of 340: "Shift"
    of 341: "Control"
    of 342: "Alt"
    of 343, 347: "Meta"
    of 32: " "
    else: ""

  proc glfwKeyCode(key: cint): int32 =
    case key
    of 257: 13
    of 259: 8
    of 256: 27
    of 258: 9
    of 32: 32
    of 262: 39
    of 263: 37
    of 264: 40
    of 265: 38
    of 266: 33
    of 267: 34
    of 268: 36
    of 269: 35
    of 261: 46
    else:
      if key >= 65 and key <= 90: key.int32
      elif key >= 48 and key <= 57: key.int32
      else: key.int32

  proc keyCallback(gwin: ptr GLFWwindow, key, scancode, action, mods: cint) {.cdecl.} =
    if gNimaxWindow == nil: return
    let shift = (mods and 1) != 0
    let ctrl  = (mods and 2) != 0
    let alt   = (mods and 4) != 0
    let keyStr = glfwKeyToString(if shift and key >= 65 and key <= 90: key else: key)
    let keyCode = glfwKeyCode(key)
    if action == GLFW_PRESS or action == GLFW_REPEAT:
      gNimaxWindow.handleKeyDown(keyStr, keyCode, shift, ctrl, alt)
      if gJsEngine != nil:
        injectKeyEventToEngine(gJsEngine, "keydown", keyStr, keyCode.int, ctrl, shift, alt)
    elif action == GLFW_RELEASE:
      gNimaxWindow.handleKeyUp(keyStr, keyCode, shift, ctrl, alt)
      if gJsEngine != nil:
        injectKeyEventToEngine(gJsEngine, "keyup", keyStr, keyCode.int, ctrl, shift, alt)

  proc charCallback(gwin: ptr GLFWwindow, codepoint: uint32) {.cdecl.} =
    if gNimaxWindow == nil: return
    var buf: array[5, char]
    let cp = codepoint
    if cp < 0x80:
      buf[0] = char(cp)
      buf[1] = '\0'
    elif cp < 0x800:
      buf[0] = char(0xC0 or (cp shr 6))
      buf[1] = char(0x80 or (cp and 0x3F))
      buf[2] = '\0'
    else:
      buf[0] = char(0xE0 or (cp shr 12))
      buf[1] = char(0x80 or ((cp shr 6) and 0x3F))
      buf[2] = char(0x80 or (cp and 0x3F))
      buf[3] = '\0'
    let s = $cast[cstring](addr buf[0])
    if gNimaxWindow.focusedNode != nil and
       gNimaxWindow.focusedNode.tag in ["input","textarea"]:
      gNimaxWindow.focusedNode.value.add(s)
      let ev = Event(kind: evInput, target: gNimaxWindow.focusedNode,
                     currentTarget: gNimaxWindow.focusedNode, bubbles: true)
      discard gNimaxWindow.focusedNode.dispatchEvent(ev)
      gNimaxWindow.needsPaint = true

  proc scrollCallback(gwin: ptr GLFWwindow, xoff, yoff: float64) {.cdecl.} =
    if gNimaxWindow != nil:
      gNimaxWindow.handleScroll(gNimaxWindow.mouseX, gNimaxWindow.mouseY,
                                 xoff.float32 * 20, yoff.float32 * 20)

  proc resizeCallback(gwin: ptr GLFWwindow, w, h: cint) {.cdecl.} =
    if gNimaxWindow != nil:
      gNimaxWindow.handleResize(w.int, h.int)

  var gTexId: uint32

  proc runGlfwLoop*(win: NimaxWindow, jsEng: pointer = nil) =
    gNimaxWindow = win
    gJsEngine = jsEng

    if glfwInit() == 0:
      echo "GLFW init failed"
      return

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2)
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0)
    glfwWindowHint(GLFW_SAMPLES, 4)
    if win.config.resizable: glfwWindowHint(GLFW_RESIZABLE, 1) else: glfwWindowHint(GLFW_RESIZABLE, 0)
    if not win.config.decorated: glfwWindowHint(GLFW_DECORATED, 0)
    if win.config.transparent: glfwWindowHint(GLFW_TRANSPARENT_FRAMEBUFFER, 1)

    let gwin = glfwCreateWindow(win.width.cint, win.height.cint, win.title.cstring, nil, nil)
    if gwin == nil:
      glfwTerminate()
      echo "GLFW window creation failed"
      return

    glfwSetWindowUserPointer(gwin, cast[pointer](win))
    glfwSetCursorPosCallback(gwin, cursorCallback)
    glfwSetMouseButtonCallback(gwin, mouseButtonCallback)
    glfwSetKeyCallback(gwin, keyCallback)
    glfwSetScrollCallback(gwin, scrollCallback)
    glfwSetWindowSizeCallback(gwin, resizeCallback)
    glfwSetCharCallback(gwin, charCallback)
    glfwMakeContextCurrent(gwin)
    loadExtensions()

    glGenTextures(1, addr gTexId)
    glBindTexture(GL_TEXTURE_2D, gTexId)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)

    var lastFpsTime = glfwGetTime()
    var fpsFrames = 0

    while glfwWindowShouldClose(gwin) == 0 and not win.closed:
      glfwPollEvents()
      var fbW, fbH: cint
      glfwGetFramebufferSize(gwin, addr fbW, addr fbH)
      if fbW != win.width or fbH != win.height:
        win.handleResize(fbW.int, fbH.int)

      if jsEng != nil:
        fireTimersInEngine(jsEng)

      if win.animEngine.tick():
        win.needsLayout = true
        win.needsPaint = true

      if win.onFrame != nil: win.onFrame(win)
      win.layout()
      win.paint()

      glViewport(0, 0, fbW, fbH)
      glClearColor(1, 1, 1, 1)
      glClear(GL_COLOR_BUFFER_BIT)
      glEnable(GL_TEXTURE_2D)
      glBindTexture(GL_TEXTURE_2D, gTexId)
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA.GLint, win.width.GLsizei, win.height.GLsizei,
                   0, GL_RGBA, GL_UNSIGNED_BYTE, addr win.frameBuffer[0])
      glMatrixMode(GL_PROJECTION)
      glLoadIdentity()
      glOrtho(0, 1, 1, 0, -1, 1)
      glMatrixMode(GL_MODELVIEW)
      glLoadIdentity()
      glBegin(GL_QUADS)
      glTexCoord2f(0, 0); glVertex2f(0, 0)
      glTexCoord2f(1, 0); glVertex2f(1, 0)
      glTexCoord2f(1, 1); glVertex2f(1, 1)
      glTexCoord2f(0, 1); glVertex2f(0, 1)
      glEnd()
      glfwSwapBuffers(gwin)

      let now = glfwGetTime()
      inc fpsFrames
      if now - lastFpsTime >= 1.0:
        win.fps = fpsFrames.float32 / (now - lastFpsTime).float32
        fpsFrames = 0
        lastFpsTime = now

    glfwDestroyWindow(gwin)
    glfwTerminate()

else:
  proc runOffscreen*(win: NimaxWindow, jsEng: pointer = nil, frames = 1) =
    for i in 0..<frames:
      if jsEng != nil:
        fireTimersInEngine(jsEng)
      win.animEngine.dirty = win.animEngine.tick()
      if win.onFrame != nil: win.onFrame(win)
      win.layout()
      win.paint()

  proc saveFrame*(win: NimaxWindow, path: string) =
    win.renderState.getImage().writeFile(path)

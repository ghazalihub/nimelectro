import std/[tables, strutils, sequtils, times, json, os, options]
import ../core/dom
import ../css/resolver
import ./jsbridge

{.push raises: [].}

type
  JSRuntime  {.importc: "JSRuntime",  header: "<quickjs/quickjs.h>".} = object
  JSContext  {.importc: "JSContext",  header: "<quickjs/quickjs.h>".} = object
  JSValueRaw {.importc: "JSValue",    header: "<quickjs/quickjs.h>".} = object
  JSCFunction {.importc: "JSCFunction", header: "<quickjs/quickjs.h>".} =
    proc(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.}

{.passC: "-I/usr/include -I/usr/local/include".}
{.passL: "-lquickjs -lm".}

proc JS_NewRuntime(): ptr JSRuntime {.importc, header: "<quickjs/quickjs.h>".}
proc JS_FreeRuntime(rt: ptr JSRuntime) {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewContext(rt: ptr JSRuntime): ptr JSContext {.importc, header: "<quickjs/quickjs.h>".}
proc JS_FreeContext(ctx: ptr JSContext) {.importc, header: "<quickjs/quickjs.h>".}
proc JS_Eval(ctx: ptr JSContext, input: cstring, inputLen: csize_t,
             filename: cstring, evalFlags: cint): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_IsException(v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_ToCString(ctx: ptr JSContext, v: JSValueRaw): cstring {.importc, header: "<quickjs/quickjs.h>".}
proc JS_FreeCString(ctx: ptr JSContext, s: cstring) {.importc, header: "<quickjs/quickjs.h>".}
proc JS_FreeValue(ctx: ptr JSContext, v: JSValueRaw) {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetGlobalObject(ctx: ptr JSContext): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_SetPropertyStr(ctx: ptr JSContext, obj: JSValueRaw,
                        name: cstring, val: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetPropertyStr(ctx: ptr JSContext, obj: JSValueRaw,
                        name: cstring): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewCFunction(ctx: ptr JSContext, fn: JSCFunction,
                      name: cstring, len: cint): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewString(ctx: ptr JSContext, s: cstring): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewBool(ctx: ptr JSContext, v: cint): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewInt32(ctx: ptr JSContext, v: int32): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewFloat64(ctx: ptr JSContext, v: float64): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewObject(ctx: ptr JSContext): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewArray(ctx: ptr JSContext): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewNull(): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_NewUndefined(): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetException(ctx: ptr JSContext): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_IsString(v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_IsNumber(v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_IsBool(v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_IsNull(v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_IsObject(v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_IsArray(ctx: ptr JSContext, v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_ToFloat64(ctx: ptr JSContext, pres: ptr float64, v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_ToBool(ctx: ptr JSContext, v: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_Throw(ctx: ptr JSContext, v: JSValueRaw): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_ThrowTypeError(ctx: ptr JSContext, fmt: cstring): JSValueRaw {.importc, varargs, header: "<quickjs/quickjs.h>".}
proc JS_SetOpaque(v: JSValueRaw, opaque: pointer) {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetOpaque(v: JSValueRaw, classId: uint32): pointer {.importc, header: "<quickjs/quickjs.h>".}
proc JS_SetPropertyUint32(ctx: ptr JSContext, obj: JSValueRaw,
                           idx: uint32, val: JSValueRaw): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetPropertyUint32(ctx: ptr JSContext, obj: JSValueRaw,
                            idx: uint32): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_SetContextOpaque(ctx: ptr JSContext, opaque: pointer) {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetContextOpaque(ctx: ptr JSContext): pointer {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetRuntime(ctx: ptr JSContext): ptr JSRuntime {.importc, header: "<quickjs/quickjs.h>".}
proc JS_SetRuntimeOpaque(rt: ptr JSRuntime, opaque: pointer) {.importc, header: "<quickjs/quickjs.h>".}
proc JS_GetRuntimeOpaque(rt: ptr JSRuntime): pointer {.importc, header: "<quickjs/quickjs.h>".}
proc JS_ExecutePendingJob(rt: ptr JSRuntime, pctx: ptr ptr JSContext): cint {.importc, header: "<quickjs/quickjs.h>".}
proc JS_DupValue(ctx: ptr JSContext, v: JSValueRaw): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}
proc JS_Call(ctx: ptr JSContext, fnObj: JSValueRaw, thisObj: JSValueRaw,
              argc: cint, argv: ptr JSValueRaw): JSValueRaw {.importc, header: "<quickjs/quickjs.h>".}

const
  JS_EVAL_TYPE_GLOBAL = 0
  JS_EVAL_TYPE_MODULE = 1

type
  QJSEngine* = ref object
    rt*: ptr JSRuntime
    ctx*: ptr JSContext
    bridge*: JsBridge
    dom*: Node
    frameCallbacks*: seq[uint64]
    onRender*: proc() {.closure.}
    onNavigate*: proc(url: string) {.closure.}
    onTitleChange*: proc(title: string) {.closure.}

var gEngine {.threadvar.}: QJSEngine

proc jsValToStr(ctx: ptr JSContext, v: JSValueRaw): string =
  let cs = JS_ToCString(ctx, v)
  if cs == nil: return ""
  result = $cs
  JS_FreeCString(ctx, cs)

proc nimStrToJs(ctx: ptr JSContext, s: string): JSValueRaw =
  JS_NewString(ctx, s.cstring)

proc getArg(ctx: ptr JSContext, argv: ptr JSValueRaw, i: int): JSValueRaw =
  cast[ptr JSValueRaw](cast[int](argv) + i * sizeof(JSValueRaw))[]

proc camelToKebab(s: string): string =
  for i, c in s:
    if c in {'A'..'Z'} and i > 0:
      result.add('-')
      result.add(c.toLowerAscii())
    else:
      result.add(c.toLowerAscii())

proc getNodeById(engine: QJSEngine, id: uint32): Node =
  proc find(n: Node): Node =
    if n.nodeId == id: return n
    for c in n.children:
      let r = find(c)
      if r != nil: return r
    nil
  find(engine.dom)

proc computedStyleValue(node: Node, prop: string): string =
  if node.computedStyle == nil: return ""
  let s = node.computedStyle
  let kebab = prop.camelToKebab()
  case kebab
  of "display": return case s.display
    of dkBlock:"block"; of dkInline:"inline"; of dkInlineBlock:"inline-block"
    of dkFlex:"flex"; of dkInlineFlex:"inline-flex"; of dkGrid:"grid"
    of dkNone:"none"; of dkTable:"table"; of dkTableRow:"table-row"
    of dkTableCell:"table-cell"; of dkListItem:"list-item"; else:"block"
  of "width": return (if node.layoutBox!=nil: $node.layoutBox.borderWidth&"px" else: "auto")
  of "height": return (if node.layoutBox!=nil: $node.layoutBox.borderHeight&"px" else: "auto")
  of "color":
    let c = s.color
    return "rgb("&$c.r&","&$c.g&","&$c.b&")"
  of "background-color":
    let c = s.backgroundColor
    return "rgba("&$c.r&","&$c.g&","&$c.b&","&$(c.a.float32/255.0)&")"
  of "font-size": return $s.fontSize.value & "px"
  of "font-family": return s.fontFamily
  of "font-weight": return $ord(s.fontWeight)
  of "opacity": return $s.opacity
  of "position": return case s.position
    of pkRelative:"relative"; of pkAbsolute:"absolute"
    of pkFixed:"fixed"; of pkSticky:"sticky"; else:"static"
  of "overflow": return case s.overflowX
    of ovHidden:"hidden"; of ovScroll:"scroll"; of ovAuto:"auto"; else:"visible"
  of "visibility": return case s.visibility
    of viHidden:"hidden"; of viCollapse:"collapse"; else:"visible"
  of "z-index": return $s.zIndex
  of "cursor": return case s.cursor
    of cuPointer:"pointer"; of cuText:"text"; of cuMove:"move"
    of cuNotAllowed:"not-allowed"; of cuNone:"none"; else:"default"
  of "flex-direction": return case s.flexDirection
    of fdRow:"row"; of fdRowReverse:"row-reverse"
    of fdColumn:"column"; of fdColumnReverse:"column-reverse"
  of "justify-content": return case s.justifyContent
    of jcFlexEnd:"flex-end"; of jcCenter:"center"
    of jcSpaceBetween:"space-between"; of jcSpaceAround:"space-around"
    of jcSpaceEvenly:"space-evenly"; else:"flex-start"
  of "align-items": return case s.alignItems
    of aiFlexEnd:"flex-end"; of aiCenter:"center"
    of aiBaseline:"baseline"; of aiFlexStart:"flex-start"; else:"stretch"
  of "line-height": return if s.lineHeight.kind==cvAuto: "normal" else: $s.lineHeight.value&"px"
  of "letter-spacing": return $s.letterSpacing.value&"px"
  of "text-align": return case s.textAlign
    of taRight:"right"; of taCenter:"center"; of taJustify:"justify"; else:"left"
  of "border-radius":
    let tl = $s.borderTopLeftRadius.value
    return tl&"px"
  of "margin":
    return $s.marginTop.value&"px "&$s.marginRight.value&"px "&$s.marginBottom.value&"px "&$s.marginLeft.value&"px"
  of "padding":
    return $s.paddingTop.value&"px "&$s.paddingRight.value&"px "&$s.paddingBottom.value&"px "&$s.paddingLeft.value&"px"
  of "border-width":
    return $s.borderTopWidth.value&"px"
  of "border-style": return case s.borderTopStyle
    of bsSolid:"solid"; of bsDashed:"dashed"; of bsDotted:"dotted"; else:"none"
  of "transform":
    if s.transform.len == 0: return "none"
    return "matrix(1,0,0,1,0,0)"
  of "transition":
    if s.transition.len == 0: return "none"
    return s.transition.mapIt(it.property&" "&$it.duration&"s").join(", ")
  of "flex-grow": return $s.flexGrow
  of "flex-shrink": return $s.flexShrink
  of "max-width": return if s.maxWidth.kind==cvNone: "none" else: $s.maxWidth.value&"px"
  of "min-width": return $s.minWidth.value&"px"
  of "max-height": return if s.maxHeight.kind==cvNone: "none" else: $s.maxHeight.value&"px"
  of "min-height": return $s.minHeight.value&"px"
  of "pointer-events": return case s.pointerEvents
    of peNone:"none"; of peAll:"all"; else:"auto"
  of "user-select": return case s.userSelect
    of usNone:"none"; of usText:"text"; of usAll:"all"; else:"auto"
  of "object-fit": return case s.objectFit
    of ofContain:"contain"; of ofCover:"cover"; of ofNone:"none"
    of ofScaleDown:"scale-down"; else:"fill"
  of "gap": return $s.gap.value&"px"
  of "box-shadow":
    if s.boxShadow.len == 0: return "none"
    return s.boxShadow.mapIt($it.x&"px "&$it.y&"px "&$it.blur&"px rgba("&$it.color.r&","&$it.color.g&","&$it.color.b&","&$(it.color.a.float32/255)&")").join(", ")
  else: return ""

proc makeCFn(ctx: ptr JSContext, name: cstring,
              fn: proc(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.}): JSValueRaw =
  JS_NewCFunction(ctx, fn, name, 1)

proc nimLog(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  var level = "log"
  var msg = ""
  if argc >= 2:
    level = jsValToStr(ctx, getArg(ctx, argv, 0))
    msg = jsValToStr(ctx, getArg(ctx, argv, 1))
  elif argc == 1:
    msg = jsValToStr(ctx, getArg(ctx, argv, 0))
  echo "[JS:" & level & "] " & msg
  if eng != nil: eng.bridge.scriptLog.add("[" & level & "] " & msg)
  JS_NewUndefined()

proc nimScheduleTimer(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewInt32(ctx, 0)
  let id     = jsValToStr(ctx, getArg(ctx, argv, 0))
  let delay  = jsValToStr(ctx, getArg(ctx, argv, 1))
  let repeat = jsValToStr(ctx, getArg(ctx, argv, 2))
  let delayMs = try: parseFloat(delay) except: 0.0
  let rep     = repeat == "1"
  let fireCode = "__fireTimer(" & id & ");"
  discard eng.bridge.scheduleTimer(fireCode, delayMs, rep)
  JS_NewInt32(ctx, parseInt(id).int32)

proc nimCancelTimer(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng != nil and argc >= 1:
    let id = try: parseInt(jsValToStr(ctx, getArg(ctx, argv, 0))) except: 0
    eng.bridge.cancelTimer(id)
  JS_NewUndefined()

proc nimGetDocumentId(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil: return nimStrToJs(ctx, "0")
  nimStrToJs(ctx, $eng.dom.nodeId)

proc nimNodeInfo(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "null")
  let idStr = jsValToStr(ctx, getArg(ctx, argv, 0))
  let id = try: parseUInt(idStr).uint32 except: return nimStrToJs(ctx, "null")
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "null")
  var obj = %*{
    "nodeType": (case node.kind of nkElement: 1 of nkText: 3 of nkComment: 8 else: 9),
    "tagName": (if node.kind == nkElement: node.tag.toUpperAscii() else: newJNull()),
    "id": node.id,
    "className": node.classes.join(" "),
    "textContent": node.textContent,
    "value": node.value,
    "checked": node.checked,
    "disabled": node.disabled,
    "href": node.getAttribute("href"),
    "src": node.getAttribute("src"),
    "inputType": node.getAttribute("type"),
    "tabIndex": 0
  }
  nimStrToJs(ctx, $obj)

proc nimGetLayout(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "{}")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "{}")
  let node = eng.getNodeById(id)
  if node == nil or node.layoutBox == nil: return nimStrToJs(ctx, "{}")
  let b = node.layoutBox
  nimStrToJs(ctx, "{\"x\":"&$b.x&",\"y\":"&$b.y&",\"width\":"&$b.borderWidth&
    ",\"height\":"&$b.borderHeight&",\"clientWidth\":"&$b.clientWidth&
    ",\"clientHeight\":"&$b.clientHeight&",\"scrollWidth\":"&$b.scrollWidth&
    ",\"scrollHeight\":"&$b.scrollHeight&",\"scrollX\":"&$node.scrollX&
    ",\"scrollY\":"&$node.scrollY&"}")

proc nimGetBCR(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "{\"x\":0,\"y\":0,\"width\":0,\"height\":0,\"top\":0,\"left\":0,\"right\":0,\"bottom\":0}")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: 0u32
  let node = if id != 0: eng.getNodeById(id) else: nil
  if node == nil or node.layoutBox == nil:
    return nimStrToJs(ctx, "{\"x\":0,\"y\":0,\"width\":0,\"height\":0,\"top\":0,\"left\":0,\"right\":0,\"bottom\":0}")
  let b = node.layoutBox
  nimStrToJs(ctx,
    "{\"x\":"&$b.x&",\"y\":"&$b.y&",\"width\":"&$b.borderWidth&",\"height\":"&$b.borderHeight&
    ",\"top\":"&$b.y&",\"left\":"&$b.x&",\"right\":"&$(b.x+b.borderWidth)&",\"bottom\":"&$(b.y+b.borderHeight)&"}")

proc nimGetChildren(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "[]")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "[]")
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "[]")
  let ids = node.children.filterIt(it.kind == nkElement).mapIt($it.nodeId)
  nimStrToJs(ctx, "[" & ids.join(",") & "]")

proc nimGetParent(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let node = eng.getNodeById(id)
  if node == nil or node.parent == nil: return nimStrToJs(ctx, "")
  nimStrToJs(ctx, $node.parent.nodeId)

proc nimGetNextSibling(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let node = eng.getNodeById(id)
  if node == nil or node.nextSibling == nil: return nimStrToJs(ctx, "")
  nimStrToJs(ctx, $node.nextSibling.nodeId)

proc nimGetPrevSibling(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let node = eng.getNodeById(id)
  if node == nil or node.prevSibling == nil: return nimStrToJs(ctx, "")
  nimStrToJs(ctx, $node.prevSibling.nodeId)

proc nimQuerySelector(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "")
  let rootId = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let sel = jsValToStr(ctx, getArg(ctx, argv, 1))
  let root = eng.getNodeById(rootId)
  if root == nil: return nimStrToJs(ctx, "")
  let found = root.querySelector(sel)
  if found == nil: return nimStrToJs(ctx, "")
  nimStrToJs(ctx, $found.nodeId)

proc nimQuerySelectorAll(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "[]")
  let rootId = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "[]")
  let sel = jsValToStr(ctx, getArg(ctx, argv, 1))
  let root = eng.getNodeById(rootId)
  if root == nil: return nimStrToJs(ctx, "[]")
  let found = root.querySelectorAll(sel)
  nimStrToJs(ctx, "[" & found.mapIt($it.nodeId).join(",") & "]")

proc nimGetAttr(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "\x00")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "\x00")
  let name = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "\x00")
  let val = node.getAttribute(name)
  if val.len == 0 and not node.hasAttribute(name): return nimStrToJs(ctx, "\x00")
  nimStrToJs(ctx, val)

proc nimSetAttr(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let name = jsValToStr(ctx, getArg(ctx, argv, 1))
  let val  = jsValToStr(ctx, getArg(ctx, argv, 2))
  let node = eng.getNodeById(id)
  if node != nil:
    node.setAttribute(name, val)
    node.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimHasAttr(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "false")
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "false")
  let name = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  nimStrToJs(ctx, if node != nil and node.hasAttribute(name): "true" else: "false")

proc nimRemoveAttr(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return JS_NewUndefined()
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let name = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node != nil:
    node.removeAttribute(name)
    node.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimGetAttrNames(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "[]")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "[]")
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "[]")
  let keys = toSeq(node.attrs.keys).mapIt("\"" & it & "\"")
  nimStrToJs(ctx, "[" & keys.join(",") & "]")

proc nimGetStyle(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "")
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let prop = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "")
  let kebab = prop.camelToKebab()
  if kebab in node.inlineStyle:
    return nimStrToJs(ctx, node.inlineStyle[kebab])
  nimStrToJs(ctx, computedStyleValue(node, kebab))

proc nimSetStyle(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let prop = jsValToStr(ctx, getArg(ctx, argv, 1))
  let val  = jsValToStr(ctx, getArg(ctx, argv, 2))
  let node = eng.getNodeById(id)
  if node != nil:
    let kebab = prop.camelToKebab()
    if val.len == 0:
      node.inlineStyle.del(kebab)
    else:
      node.inlineStyle[kebab] = val
    node.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimGetComputedStyle(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "")
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let prop = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "")
  nimStrToJs(ctx, computedStyleValue(node, prop))

proc nimClassOp(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return nimStrToJs(ctx, "")
  let id  = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let op  = jsValToStr(ctx, getArg(ctx, argv, 1))
  let cls = jsValToStr(ctx, getArg(ctx, argv, 2))
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "")
  case op
  of "add":
    node.addClass(cls)
    if eng.onRender != nil: eng.onRender()
    return nimStrToJs(ctx, "")
  of "remove":
    node.removeClass(cls)
    if eng.onRender != nil: eng.onRender()
    return nimStrToJs(ctx, "")
  of "toggle":
    let r = node.toggleClass(cls)
    if eng.onRender != nil: eng.onRender()
    return nimStrToJs(ctx, if r: "true" else: "false")
  of "contains":
    return nimStrToJs(ctx, if node.hasClass(cls): "true" else: "false")
  of "value":
    return nimStrToJs(ctx, node.classes.join(" "))
  of "replace":
    let parts = cls.split(' ')
    if parts.len >= 2:
      node.removeClass(parts[0])
      node.addClass(parts[1])
      if eng.onRender != nil: eng.onRender()
  nimStrToJs(ctx, "")

proc nimCreateElement(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "0")
  let tag = jsValToStr(ctx, getArg(ctx, argv, 0))
  let el = newElement(tag)
  nimStrToJs(ctx, $el.nodeId)

proc nimCreateTextNode(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let text = if argc >= 1: jsValToStr(ctx, getArg(ctx, argv, 0)) else: ""
  let el = newTextNode(text)
  nimStrToJs(ctx, $el.nodeId)

proc nimCreateFragment(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let frag = newNode(nkDocument, "#fragment")
  nimStrToJs(ctx, $frag.nodeId)

proc nimAppendChild(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return JS_NewUndefined()
  let parentId = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let childId  = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 1))).uint32 except: return JS_NewUndefined()
  let parent = eng.getNodeById(parentId)
  let child  = eng.getNodeById(childId)
  if parent != nil and child != nil:
    if child.parent != nil: child.parent.removeChild(child)
    parent.appendChild(child)
    parent.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimRemoveChild(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return JS_NewUndefined()
  let parentId = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let childId  = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 1))).uint32 except: return JS_NewUndefined()
  let parent = eng.getNodeById(parentId)
  let child  = eng.getNodeById(childId)
  if parent != nil and child != nil:
    parent.removeChild(child)
    parent.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimInsertBefore(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let parentId = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let newId    = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 1))).uint32 except: return JS_NewUndefined()
  let refIdStr = jsValToStr(ctx, getArg(ctx, argv, 2))
  let refId    = try: parseUInt(refIdStr).uint32 except: 0u32
  let parent = eng.getNodeById(parentId)
  let newChild = eng.getNodeById(newId)
  if parent != nil and newChild != nil:
    if newChild.parent != nil: newChild.parent.removeChild(newChild)
    if refId != 0:
      let refNode = eng.getNodeById(refId)
      if refNode != nil: parent.insertBefore(newChild, refNode)
      else: parent.appendChild(newChild)
    else:
      parent.appendChild(newChild)
    parent.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimReplaceChild(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let parentId = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let newId    = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 1))).uint32 except: return JS_NewUndefined()
  let oldId    = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 2))).uint32 except: return JS_NewUndefined()
  let parent   = eng.getNodeById(parentId)
  let newChild = eng.getNodeById(newId)
  let oldChild = eng.getNodeById(oldId)
  if parent != nil and newChild != nil and oldChild != nil:
    parent.replaceChild(newChild, oldChild)
    parent.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimCloneNode(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "0")
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "0")
  let deep = argc >= 2 and jsValToStr(ctx, getArg(ctx, argv, 1)) == "1"
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "0")
  let cloned = node.cloneNode(deep)
  nimStrToJs(ctx, $cloned.nodeId)

proc nimSetTextContent(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return JS_NewUndefined()
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let text = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node != nil:
    for c in node.children:
      c.parent = nil
    node.children = @[]
    node.firstChild = nil
    node.lastChild = nil
    node.textContent = text
    if node.kind == nkText:
      node.textContent = text
    else:
      let t = newTextNode(text)
      node.appendChild(t)
    node.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimGetInnerHTML(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "")
  proc serializeNode(n: Node): string =
    if n.kind == nkText: return n.textContent
    if n.kind != nkElement: return ""
    var s = "<" & n.tag
    for k, v in n.attrs: s.add(" " & k & "=\"" & v & "\"")
    if n.children.len == 0:
      let void = ["area","base","br","col","embed","hr","img","input","link","meta","param","source","track","wbr"]
      if n.tag in void: s.add("/>"); return s
    s.add(">")
    for c in n.children: s.add(serializeNode(c))
    s.add("</" & n.tag & ">")
    s
  var html = ""
  for c in node.children: html.add(serializeNode(c))
  nimStrToJs(ctx, html)

proc nimSetInnerHTML(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return JS_NewUndefined()
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let html = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node != nil:
    for c in node.children: c.parent = nil
    node.children = @[]
    node.firstChild = nil
    node.lastChild = nil
    from ../core/html_parser import parseHtml
    let fragment = parseHtml("<div id=\"__frag__\">" & html & "</div>")
    let frag = fragment.querySelector("#__frag__")
    if frag != nil:
      for c in frag.children:
        c.parent = nil
        node.appendChild(c)
    node.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimGetOuterHTML(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return nimStrToJs(ctx, "")
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let node = eng.getNodeById(id)
  if node == nil or node.kind != nkElement: return nimStrToJs(ctx, "")
  proc ser(n: Node): string =
    if n.kind == nkText: return n.textContent
    var s = "<" & n.tag
    for k, v in n.attrs: s.add(" " & k & "=\"" & v & "\"")
    s.add(">")
    for c in n.children: s.add(ser(c))
    s.add("</" & n.tag & ">")
    s
  nimStrToJs(ctx, ser(node))

proc nimInsertAdjacent(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let id    = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let pos   = jsValToStr(ctx, getArg(ctx, argv, 1))
  let othId = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 2))).uint32 except: return JS_NewUndefined()
  let node  = eng.getNodeById(id)
  let other = eng.getNodeById(othId)
  if node != nil and other != nil:
    case pos
    of "beforebegin":
      if node.parent != nil: node.parent.insertBefore(other, node)
    of "afterbegin":
      if node.firstChild != nil: node.insertBefore(other, node.firstChild)
      else: node.appendChild(other)
    of "beforeend":
      node.appendChild(other)
    of "afterend":
      if node.parent != nil:
        if node.nextSibling != nil: node.parent.insertBefore(other, node.nextSibling)
        else: node.parent.appendChild(other)
    else: discard
    node.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimInsertAdjacentHTML(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let id   = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let pos  = jsValToStr(ctx, getArg(ctx, argv, 1))
  let html = jsValToStr(ctx, getArg(ctx, argv, 2))
  let node = eng.getNodeById(id)
  if node != nil:
    from ../core/html_parser import parseHtml
    let frag = parseHtml("<div id=\"__adj__\">" & html & "</div>")
    let container = frag.querySelector("#__adj__")
    if container != nil:
      var parsed: seq[Node]
      for c in container.children:
        c.parent = nil
        parsed.add(c)
      case pos
      of "beforebegin":
        if node.parent != nil:
          for p in parsed: node.parent.insertBefore(p, node)
      of "afterbegin":
        var ref2 = node.firstChild
        for p in parsed:
          if ref2 != nil: node.insertBefore(p, ref2)
          else: node.appendChild(p)
      of "beforeend":
        for p in parsed: node.appendChild(p)
      of "afterend":
        if node.parent != nil:
          let nxt = node.nextSibling
          for p in parsed:
            if nxt != nil: node.parent.insertBefore(p, nxt)
            else: node.parent.appendChild(p)
      else: discard
    node.markDirty()
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimMatches(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "false")
  let id  = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "false")
  let sel = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  nimStrToJs(ctx, if node != nil and node.matches(sel): "true" else: "false")

proc nimClosest(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "")
  let id  = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let sel = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "")
  var cur = node
  while cur != nil:
    if cur.matches(sel): return nimStrToJs(ctx, $cur.nodeId)
    cur = cur.parent
  nimStrToJs(ctx, "")

proc nimContains(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "false")
  let aid = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "false")
  let bid = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 1))).uint32 except: return nimStrToJs(ctx, "false")
  let a = eng.getNodeById(aid)
  let b = eng.getNodeById(bid)
  if a == nil or b == nil: return nimStrToJs(ctx, "false")
  var cur = b
  while cur != nil:
    if cur.nodeId == a.nodeId: return nimStrToJs(ctx, "true")
    cur = cur.parent
  nimStrToJs(ctx, "false")

proc nimFocus(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return JS_NewUndefined()
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let node = eng.getNodeById(id)
  if node != nil:
    node.focused = true
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimBlur(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 1: return JS_NewUndefined()
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let node = eng.getNodeById(id)
  if node != nil: node.focused = false
  JS_NewUndefined()

proc nimGetActiveElement(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil: return nimStrToJs(ctx, "")
  proc findFocused(n: Node): Node =
    if n.focused: return n
    for c in n.children:
      let r = findFocused(c)
      if r != nil: return r
    nil
  let focused = findFocused(eng.dom)
  if focused != nil: nimStrToJs(ctx, $focused.nodeId) else: nimStrToJs(ctx, "")

proc nimAddListener(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  JS_NewUndefined()

proc nimDispatchEvent(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return JS_NewUndefined()
  let id       = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let evType   = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node     = eng.getNodeById(id)
  if node != nil:
    let evKind = case evType
      of "click": evClick
      of "mousedown": evMouseDown; of "mouseup": evMouseUp
      of "mousemove": evMouseMove
      of "keydown": evKeyDown; of "keyup": evKeyUp; of "keypress": evKeyPress
      of "focus": evFocus; of "blur": evBlur
      of "change": evChange; of "input": evInput
      of "submit": evSubmit; of "scroll": evScroll
      else: evCustom
    let ev = Event(kind: evKind, target: node, currentTarget: node,
                   bubbles: true, cancelable: true, customName: evType)
    discard node.dispatchEvent(ev)
  JS_NewUndefined()

proc nimScrollIntoView(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  JS_NewUndefined()

proc nimSetScroll(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let id = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let sx = jsValToStr(ctx, getArg(ctx, argv, 1))
  let sy = jsValToStr(ctx, getArg(ctx, argv, 2))
  let node = eng.getNodeById(id)
  if node != nil:
    if sx != "null": (try: node.scrollX = parseFloat(sx).float32 except: discard)
    if sy != "null": (try: node.scrollY = parseFloat(sy).float32 except: discard)
    if eng.onRender != nil: eng.onRender()
  JS_NewUndefined()

proc nimGetDataset(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "")
  let id  = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return nimStrToJs(ctx, "")
  let key = jsValToStr(ctx, getArg(ctx, argv, 1))
  let node = eng.getNodeById(id)
  if node == nil: return nimStrToJs(ctx, "")
  nimStrToJs(ctx, node.dataset.getOrDefault(key, ""))

proc nimSetDataset(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 3: return JS_NewUndefined()
  let id  = try: parseUInt(jsValToStr(ctx, getArg(ctx, argv, 0))).uint32 except: return JS_NewUndefined()
  let key = jsValToStr(ctx, getArg(ctx, argv, 1))
  let val = jsValToStr(ctx, getArg(ctx, argv, 2))
  let node = eng.getNodeById(id)
  if node != nil: node.dataset[key] = val
  JS_NewUndefined()

proc nimNavigate(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng != nil and argc >= 1 and eng.onNavigate != nil:
    eng.onNavigate(jsValToStr(ctx, getArg(ctx, argv, 0)))
  JS_NewUndefined()

proc nimTitleChange(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng != nil and argc >= 1 and eng.onTitleChange != nil:
    eng.onTitleChange(jsValToStr(ctx, getArg(ctx, argv, 0)))
  JS_NewUndefined()

proc nimFetch(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  nimStrToJs(ctx, "{\"ok\":false,\"status\":0,\"statusText\":\"Network disabled\",\"body\":\"\"}")

proc nimAnimate(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  JS_NewUndefined()

proc nimObserveResize(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  JS_NewUndefined()

proc nimCallNative(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.} =
  let eng = cast[QJSEngine](JS_GetContextOpaque(ctx))
  if eng == nil or argc < 2: return nimStrToJs(ctx, "")
  let name = jsValToStr(ctx, getArg(ctx, argv, 0))
  let args = jsValToStr(ctx, getArg(ctx, argv, 1))
  if name in eng.bridge.nativeProcs:
    let parsed = try:
      let j = parseJson(args)
      j.getElems().mapIt(it.getStr())
    except: @[args]
    let res = eng.bridge.nativeProcs[name](parsed)
    return nimStrToJs(ctx, res)
  nimStrToJs(ctx, "")

proc registerFn(eng: QJSEngine, global: JSValueRaw, name: string,
                 fn: proc(ctx: ptr JSContext, this: JSValueRaw, argc: cint, argv: ptr JSValueRaw): JSValueRaw {.cdecl.}) =
  let jsFn = JS_NewCFunction(eng.ctx, fn, name.cstring, 1)
  discard JS_SetPropertyStr(eng.ctx, global, name.cstring, jsFn)

proc newQJSEngine*(dom: Node): QJSEngine =
  let rt = JS_NewRuntime()
  let ctx = JS_NewContext(rt)
  let eng = QJSEngine(rt: rt, ctx: ctx, dom: dom, bridge: newJsBridge(dom))
  JS_SetContextOpaque(ctx, cast[pointer](eng))
  JS_SetRuntimeOpaque(rt, cast[pointer](eng))
  gEngine = eng
  let global = JS_GetGlobalObject(ctx)
  eng.registerFn(global, "__nim_log",              nimLog)
  eng.registerFn(global, "__nim_scheduleTimer",    nimScheduleTimer)
  eng.registerFn(global, "__nim_cancelTimer",      nimCancelTimer)
  eng.registerFn(global, "__nim_getDocumentId",    nimGetDocumentId)
  eng.registerFn(global, "__nim_nodeInfo",         nimNodeInfo)
  eng.registerFn(global, "__nim_getLayout",        nimGetLayout)
  eng.registerFn(global, "__nim_getBCR",           nimGetBCR)
  eng.registerFn(global, "__nim_getChildren",      nimGetChildren)
  eng.registerFn(global, "__nim_getParent",        nimGetParent)
  eng.registerFn(global, "__nim_getNextSibling",   nimGetNextSibling)
  eng.registerFn(global, "__nim_getPrevSibling",   nimGetPrevSibling)
  eng.registerFn(global, "__nim_querySelector",    nimQuerySelector)
  eng.registerFn(global, "__nim_querySelectorAll", nimQuerySelectorAll)
  eng.registerFn(global, "__nim_getAttr",          nimGetAttr)
  eng.registerFn(global, "__nim_setAttr",          nimSetAttr)
  eng.registerFn(global, "__nim_hasAttr",          nimHasAttr)
  eng.registerFn(global, "__nim_removeAttr",       nimRemoveAttr)
  eng.registerFn(global, "__nim_getAttrNames",     nimGetAttrNames)
  eng.registerFn(global, "__nim_getStyle",         nimGetStyle)
  eng.registerFn(global, "__nim_setStyle",         nimSetStyle)
  eng.registerFn(global, "__nim_getComputedStyle", nimGetComputedStyle)
  eng.registerFn(global, "__nim_classOp",          nimClassOp)
  eng.registerFn(global, "__nim_createElement",    nimCreateElement)
  eng.registerFn(global, "__nim_createTextNode",   nimCreateTextNode)
  eng.registerFn(global, "__nim_createFragment",   nimCreateFragment)
  eng.registerFn(global, "__nim_appendChild",      nimAppendChild)
  eng.registerFn(global, "__nim_removeChild",      nimRemoveChild)
  eng.registerFn(global, "__nim_insertBefore",     nimInsertBefore)
  eng.registerFn(global, "__nim_replaceChild",     nimReplaceChild)
  eng.registerFn(global, "__nim_cloneNode",        nimCloneNode)
  eng.registerFn(global, "__nim_setTextContent",   nimSetTextContent)
  eng.registerFn(global, "__nim_getInnerHTML",     nimGetInnerHTML)
  eng.registerFn(global, "__nim_setInnerHTML",     nimSetInnerHTML)
  eng.registerFn(global, "__nim_getOuterHTML",     nimGetOuterHTML)
  eng.registerFn(global, "__nim_insertAdjacent",   nimInsertAdjacent)
  eng.registerFn(global, "__nim_insertAdjacentHTML", nimInsertAdjacentHTML)
  eng.registerFn(global, "__nim_matches",          nimMatches)
  eng.registerFn(global, "__nim_closest",          nimClosest)
  eng.registerFn(global, "__nim_contains",         nimContains)
  eng.registerFn(global, "__nim_focus",            nimFocus)
  eng.registerFn(global, "__nim_blur",             nimBlur)
  eng.registerFn(global, "__nim_getActiveElement", nimGetActiveElement)
  eng.registerFn(global, "__nim_addListener",      nimAddListener)
  eng.registerFn(global, "__nim_dispatchEvent",    nimDispatchEvent)
  eng.registerFn(global, "__nim_scrollIntoView",   nimScrollIntoView)
  eng.registerFn(global, "__nim_setScroll",        nimSetScroll)
  eng.registerFn(global, "__nim_getDataset",       nimGetDataset)
  eng.registerFn(global, "__nim_setDataset",       nimSetDataset)
  eng.registerFn(global, "__nim_navigate",         nimNavigate)
  eng.registerFn(global, "__nim_titleChange",      nimTitleChange)
  eng.registerFn(global, "__nim_fetch",            nimFetch)
  eng.registerFn(global, "__nim_animate",          nimAnimate)
  eng.registerFn(global, "__nim_observeResize",    nimObserveResize)
  eng.registerFn(global, "__nim_callNative",       nimCallNative)
  JS_FreeValue(ctx, global)
  let runtimeSrc = eng.bridge.synthesizeRuntimeJs()
  let initResult = JS_Eval(ctx, runtimeSrc.cstring, runtimeSrc.len.csize_t, "<nimax-runtime>".cstring, JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(initResult) != 0:
    let ex = JS_GetException(ctx)
    echo "[NIMAX INIT ERROR] " & jsValToStr(ctx, ex)
    JS_FreeValue(ctx, ex)
  JS_FreeValue(ctx, initResult)
  eng

proc eval*(eng: QJSEngine, code: string, filename = "<script>"): string =
  let result = JS_Eval(eng.ctx, code.cstring, code.len.csize_t, filename.cstring, JS_EVAL_TYPE_GLOBAL)
  if JS_IsException(result) != 0:
    let ex = JS_GetException(eng.ctx)
    let msg = jsValToStr(eng.ctx, ex)
    JS_FreeValue(eng.ctx, ex)
    JS_FreeValue(eng.ctx, result)
    echo "[JS ERROR in " & filename & "] " & msg
    return "error:" & msg
  let s = jsValToStr(eng.ctx, result)
  JS_FreeValue(eng.ctx, result)
  s

proc drainMicrotasks*(eng: QJSEngine) =
  var pctx: ptr JSContext = nil
  while JS_ExecutePendingJob(eng.rt, addr pctx) > 0: discard

proc fireTimers*(eng: QJSEngine) =
  let fired = eng.bridge.collectFiredTimers()
  for t in fired:
    discard eng.eval(t.src, "<timer>")
  eng.drainMicrotasks()

proc injectMouseEvent*(eng: QJSEngine, kind: string, x, y: float32,
                        button: int = 0, ctrl, shift, alt: bool = false) =
  let code = "__dispatchNativeEvent && __dispatchNativeEvent(" &
    $eng.dom.nodeId & ",'" & kind & "',{" &
    "type:'" & kind & "'," &
    "clientX:" & $x & ",clientY:" & $y & "," &
    "pageX:" & $x & ",pageY:" & $y & "," &
    "button:" & $button & "," &
    "ctrlKey:" & $ctrl & ",shiftKey:" & $shift & ",altKey:" & $alt & "," &
    "bubbles:true,cancelable:true" &
    "});"
  discard eng.eval(code, "<mouse-event>")
  eng.drainMicrotasks()

proc injectKeyEvent*(eng: QJSEngine, kind: string, key: string, keyCode: int,
                      ctrl, shift, alt: bool = false) =
  let safeKey = key.replace("'", "\\'").replace("\\", "\\\\")
  let code = "__dispatchNativeEvent && __dispatchNativeEvent(" &
    $eng.dom.nodeId & ",'" & kind & "',{" &
    "type:'" & kind & "'," &
    "key:'" & safeKey & "',code:'" & safeKey & "'," &
    "keyCode:" & $keyCode & ",charCode:" & $keyCode & ",which:" & $keyCode & "," &
    "ctrlKey:" & $ctrl & ",shiftKey:" & $shift & ",altKey:" & $alt & "," &
    "bubbles:true,cancelable:true" &
    "});"
  discard eng.eval(code, "<key-event>")
  eng.drainMicrotasks()

proc injectDOMContentLoaded*(eng: QJSEngine) =
  let code = "__dispatchNativeEvent && __dispatchNativeEvent(" & $eng.dom.nodeId & ",'DOMContentLoaded',{type:'DOMContentLoaded',bubbles:false,cancelable:false});"
  discard eng.eval(code, "<dcl>")
  let code2 = "__dispatchNativeEvent && __dispatchNativeEvent(" & $eng.dom.nodeId & ",'load',{type:'load',bubbles:false,cancelable:false});"
  discard eng.eval(code2, "<load>")
  eng.drainMicrotasks()

proc destroy*(eng: QJSEngine) =
  JS_FreeContext(eng.ctx)
  JS_FreeRuntime(eng.rt)

{.pop.}

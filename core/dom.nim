import std/[tables, hashes, strutils, sequtils, options]

type
  NodeKind* = enum
    nkElement, nkText, nkComment, nkDocument, nkDoctype

  EventKind* = enum
    evClick, evMouseDown, evMouseUp, evMouseMove, evMouseEnter, evMouseLeave,
    evKeyDown, evKeyUp, evKeyPress, evFocus, evBlur, evChange, evInput,
    evSubmit, evScroll, evResize, evLoad, evDOMContentLoaded, evCustom

  MouseButton* = enum
    mbLeft, mbRight, mbMiddle

  EventFlags* = set[enum]

  Event* = ref object
    kind*: EventKind
    target*: Node
    currentTarget*: Node
    bubbles*: bool
    cancelable*: bool
    defaultPrevented*: bool
    propagationStopped*: bool
    x*, y*: float32
    button*: MouseButton
    keyCode*: int32
    key*: string
    modShift*, modCtrl*, modAlt*, modMeta*: bool
    detail*: int32
    customName*: string
    customData*: pointer

  EventListener* = proc(ev: Event) {.closure.}

  AttrMap* = Table[string, string]
  ClassSet* = seq[string]

  ComputedStyle* = ref object
    display*: DisplayKind
    position*: PositionKind
    float*: FloatKind
    clear*: ClearKind
    overflowX*, overflowY*: OverflowKind
    visibility*: VisibilityKind
    opacity*: float32
    zIndex*: int32
    left*, top*, right*, bottom*: CssValue
    width*, height*: CssValue
    minWidth*, minHeight*: CssValue
    maxWidth*, maxHeight*: CssValue
    marginTop*, marginRight*, marginBottom*, marginLeft*: CssValue
    paddingTop*, paddingRight*, paddingBottom*, paddingLeft*: CssValue
    borderTopWidth*, borderRightWidth*, borderBottomWidth*, borderLeftWidth*: CssValue
    borderTopColor*, borderRightColor*, borderBottomColor*, borderLeftColor*: ColorRGBA
    borderTopStyle*, borderRightStyle*, borderBottomStyle*, borderLeftStyle*: BorderStyleKind
    borderTopLeftRadius*, borderTopRightRadius*: CssValue
    borderBottomLeftRadius*, borderBottomRightRadius*: CssValue
    backgroundColor*: ColorRGBA
    backgroundImage*: string
    backgroundSize*: BackgroundSizeKind
    backgroundRepeat*: BackgroundRepeatKind
    backgroundPosition*: tuple[x, y: CssValue]
    color*: ColorRGBA
    fontSize*: CssValue
    fontFamily*: string
    fontWeight*: FontWeightKind
    fontStyle*: FontStyleKind
    lineHeight*: CssValue
    letterSpacing*: CssValue
    textAlign*: TextAlignKind
    textDecoration*: TextDecorationKind
    textTransform*: TextTransformKind
    textOverflow*: TextOverflowKind
    whiteSpace*: WhiteSpaceKind
    wordBreak*: WordBreakKind
    verticalAlign*: VerticalAlignKind
    flexDirection*: FlexDirectionKind
    flexWrap*: FlexWrapKind
    justifyContent*: JustifyContentKind
    alignItems*: AlignItemsKind
    alignContent*: AlignContentKind
    alignSelf*: AlignSelfKind
    flexGrow*: float32
    flexShrink*: float32
    flexBasis*: CssValue
    order*: int32
    gap*, rowGap*, columnGap*: CssValue
    gridTemplateColumns*, gridTemplateRows*: string
    gridColumn*, gridRow*: string
    cursor*: CursorKind
    pointerEvents*: PointerEventsKind
    userSelect*: UserSelectKind
    boxShadow*: seq[BoxShadow]
    textShadow*: seq[TextShadow]
    transform*: seq[Transform2D]
    transformOrigin*: tuple[x, y: CssValue]
    transition*: seq[Transition]
    animation*: seq[Animation]
    outline*: CssValue
    outlineColor*: ColorRGBA
    outlineStyle*: BorderStyleKind
    filter*: seq[CssFilter]
    backdropFilter*: seq[CssFilter]
    mixBlendMode*: BlendModeKind
    clipPath*: string
    content*: string
    listStyleType*: ListStyleKind
    tableLayout*: TableLayoutKind
    borderCollapse*: BorderCollapseKind
    borderSpacing*: tuple[x, y: CssValue]
    resize*: ResizeKind
    appearance*: AppearanceKind
    caretColor*: ColorRGBA
    accentColor*: ColorRGBA
    scrollBehavior*: ScrollBehaviorKind
    objectFit*: ObjectFitKind
    objectPosition*: tuple[x, y: CssValue]
    aspectRatio*: Option[tuple[w, h: float32]]

  DisplayKind* = enum
    dkNone, dkBlock, dkInline, dkInlineBlock, dkFlex, dkInlineFlex,
    dkGrid, dkInlineGrid, dkTable, dkTableRow, dkTableCell,
    dkTableHeader, dkTableFooter, dkListItem, dkContents

  PositionKind* = enum
    pkStatic, pkRelative, pkAbsolute, pkFixed, pkSticky

  FloatKind* = enum
    fkNone, fkLeft, fkRight

  ClearKind* = enum
    ckNone, ckLeft, ckRight, ckBoth

  OverflowKind* = enum
    ovVisible, ovHidden, ovScroll, ovAuto, ovClip

  VisibilityKind* = enum
    viVisible, viHidden, viCollapse

  CssValueKind* = enum
    cvAuto, cvLength, cvPercent, cvVw, cvVh, cvVmin, cvVmax,
    cvEm, cvRem, cvCh, cvEx, cvFr, cvFitContent, cvMinContent, cvMaxContent,
    cvNone, cvInitial, cvInherit, cvUnset

  CssValue* = object
    kind*: CssValueKind
    value*: float32

  ColorRGBA* = object
    r*, g*, b*, a*: uint8

  BorderStyleKind* = enum
    bsNone, bsHidden, bsDotted, bsDashed, bsSolid,
    bsDouble, bsGroove, bsRidge, bsInset, bsOutset

  BackgroundSizeKind* = enum
    bszAuto, bszCover, bszContain, bszCustom

  BackgroundRepeatKind* = enum
    brRepeat, brRepeatX, brRepeatY, brNoRepeat, brRound, brSpace

  FontWeightKind* = enum
    fw100, fw200, fw300, fw400, fw500, fw600, fw700, fw800, fw900

  FontStyleKind* = enum
    fsNormal, fsItalic, fsOblique

  TextAlignKind* = enum
    taLeft, taRight, taCenter, taJustify, taStart, taEnd

  TextDecorationKind* = enum
    tdNone, tdUnderline, tdOverline, tdLineThrough

  TextTransformKind* = enum
    ttNone, ttUppercase, ttLowercase, ttCapitalize

  TextOverflowKind* = enum
    toClip, toEllipsis

  WhiteSpaceKind* = enum
    wsNormal, wsPre, wsNowrap, wsPreWrap, wsPreLine, wsBreakSpaces

  WordBreakKind* = enum
    wbNormal, wbBreakAll, wbKeepAll, wbBreakWord

  VerticalAlignKind* = enum
    vaBaseline, vaTop, vaMiddle, vaBottom, vaTextTop, vaTextBottom,
    vaSub, vaSuper

  FlexDirectionKind* = enum
    fdRow, fdRowReverse, fdColumn, fdColumnReverse

  FlexWrapKind* = enum
    fwNowrap, fwWrap, fwWrapReverse

  JustifyContentKind* = enum
    jcFlexStart, jcFlexEnd, jcCenter, jcSpaceBetween, jcSpaceAround,
    jcSpaceEvenly, jcStart, jcEnd, jcStretch

  AlignItemsKind* = enum
    aiFlexStart, aiFlexEnd, aiCenter, aiBaseline, aiStretch,
    aiStart, aiEnd

  AlignContentKind* = enum
    acFlexStart, acFlexEnd, acCenter, acSpaceBetween, acSpaceAround,
    acStretch, acSpaceEvenly

  AlignSelfKind* = enum
    asAuto, asFlexStart, asFlexEnd, asCenter, asBaseline, asStretch

  CursorKind* = enum
    cuAuto, cuDefault, cuPointer, cuCrosshair, cuText, cuMove,
    cuNotAllowed, cuWait, cuHelp, cuNResize, cuEResize, cuSResize,
    cuWResize, cuNEResize, cuNWResize, cuSEResize, cuSWResize,
    cuEWResize, cuNSResize, cuNESWResize, cuNWSEResize, cuColResize,
    cuRowResize, cuAllScroll, cuZoomIn, cuZoomOut, cuGrab, cuGrabbing,
    cuNone

  PointerEventsKind* = enum
    peAuto, peNone, peAll

  UserSelectKind* = enum
    usAuto, usNone, usText, usAll, usContainment

  BlendModeKind* = enum
    bmNormal, bmMultiply, bmScreen, bmOverlay, bmDarken, bmLighten,
    bmColorDodge, bmColorBurn, bmHardLight, bmSoftLight, bmDifference,
    bmExclusion, bmHue, bmSaturation, bmColor, bmLuminosity

  BoxShadow* = object
    inset*: bool
    x*, y*, blur*, spread*: float32
    color*: ColorRGBA

  TextShadow* = object
    x*, y*, blur*: float32
    color*: ColorRGBA

  Transform2DKind* = enum
    trTranslate, trScale, trRotate, trSkewX, trSkewY, trMatrix, trTranslateX,
    trTranslateY, trScaleX, trScaleY, trRotateX, trRotateY, trPerspective

  Transform2D* = object
    kind*: Transform2DKind
    values*: array[6, float32]

  Transition* = object
    property*: string
    duration*: float32
    timingFunction*: EasingKind
    delay*: float32

  EasingKind* = enum
    ekLinear, ekEase, ekEaseIn, ekEaseOut, ekEaseInOut,
    ekStepStart, ekStepEnd, ekCubicBezier

  Animation* = object
    name*: string
    duration*: float32
    timingFunction*: EasingKind
    delay*: float32
    iterationCount*: float32
    direction*: AnimationDirectionKind
    fillMode*: AnimationFillModeKind
    playState*: AnimationPlayStateKind

  AnimationDirectionKind* = enum
    adNormal, adReverse, adAlternate, adAlternateReverse

  AnimationFillModeKind* = enum
    afNone, afForwards, afBackwards, afBoth

  AnimationPlayStateKind* = enum
    apRunning, apPaused

  CssFilterKind* = enum
    cfBlur, cfBrightness, cfContrast, cfDropShadow, cfGrayscale,
    cfHueRotate, cfInvert, cfOpacity, cfSaturate, cfSepia

  CssFilter* = object
    kind*: CssFilterKind
    value*: float32
    shadow*: Option[BoxShadow]

  ListStyleKind* = enum
    lsNone, lsDisc, lsCircle, lsSquare, lsDecimal, lsAlpha,
    lsUpperAlpha, lsRoman, lsUpperRoman

  TableLayoutKind* = enum
    tlAuto, tlFixed

  BorderCollapseKind* = enum
    bcSeparate, bcCollapse

  ResizeKind* = enum
    rkNone, rkBoth, rkHorizontal, rkVertical

  AppearanceKind* = enum
    apNone, apAuto, apButton, apTextfield, apCheckbox, apRadio

  ScrollBehaviorKind* = enum
    sbAuto, sbSmooth

  ObjectFitKind* = enum
    ofFill, ofContain, ofCover, ofNone, ofScaleDown

  LayoutBox* = ref object
    x*, y*, width*, height*: float32
    scrollX*, scrollY*: float32
    scrollWidth*, scrollHeight*: float32
    clientWidth*, clientHeight*: float32
    baseline*: float32
    contentX*, contentY*, contentWidth*, contentHeight*: float32
    borderX*, borderY*, borderWidth*, borderHeight*: float32
    marginLeft*, marginTop*, marginRight*, marginBottom*: float32
    paddingLeft*, paddingTop*, paddingRight*, paddingBottom*: float32
    lineBoxes*: seq[LineBox]

  LineBox* = object
    y*, height*, baseline*: float32
    fragments*: seq[InlineFragment]

  InlineFragment* = object
    node*: Node
    x*, y*, width*, height*, baseline*: float32
    text*: string
    startChar*, endChar*: int

  PseudoElement* = enum
    peBefore, peAfter, peFirstLine, peFirstLetter, peSelection,
    pePlaceholder, peScrollbar, peScrollbarThumb, peScrollbarTrack

  Node* = ref object
    kind*: NodeKind
    tag*: string
    id*: string
    classes*: ClassSet
    attrs*: AttrMap
    parent*: Node
    children*: seq[Node]
    textContent*: string
    ownerDocument*: Node
    style*: ComputedStyle
    inlineStyle*: Table[string, string]
    computedStyle*: ComputedStyle
    layoutBox*: LayoutBox
    eventListeners*: Table[EventKind, seq[EventListener]]
    dataset*: Table[string, string]
    dirty*: bool
    layoutDirty*: bool
    paintDirty*: bool
    nodeId*: uint32
    jsObject*: pointer
    pseudos*: Table[PseudoElement, Node]
    shadowRoot*: Node
    scrollX*, scrollY*: float32
    focused*: bool
    checked*: bool
    disabled*: bool
    readOnly*: bool
    value*: string
    innerHTML*: string
    prevSibling*: Node
    nextSibling*: Node
    firstChild*: Node
    lastChild*: Node

var nodeIdCounter {.global.}: uint32 = 0

proc newNode*(kind: NodeKind, tag = ""): Node =
  inc nodeIdCounter
  result = Node(
    kind: kind,
    tag: tag.toLowerAscii,
    attrs: initTable[string, string](),
    inlineStyle: initTable[string, string](),
    eventListeners: initTable[EventKind, seq[EventListener]](),
    dataset: initTable[string, string](),
    pseudos: initTable[PseudoElement, Node](),
    dirty: true,
    layoutDirty: true,
    paintDirty: true,
    nodeId: nodeIdCounter,
    computedStyle: ComputedStyle()
  )

proc newElement*(tag: string): Node = newNode(nkElement, tag)
proc newTextNode*(text: string): Node =
  result = newNode(nkText)
  result.textContent = text

proc newDocument*(): Node =
  result = newNode(nkDocument, "#document")
  result.ownerDocument = result

proc appendChild*(parent, child: Node) =
  child.parent = parent
  if parent.children.len > 0:
    let prev = parent.children[^1]
    prev.nextSibling = child
    child.prevSibling = prev
  parent.children.add(child)
  parent.firstChild = parent.children[0]
  parent.lastChild = child
  parent.dirty = true

proc removeChild*(parent, child: Node) =
  let idx = parent.children.find(child)
  if idx >= 0:
    if child.prevSibling != nil:
      child.prevSibling.nextSibling = child.nextSibling
    if child.nextSibling != nil:
      child.nextSibling.prevSibling = child.prevSibling
    parent.children.del(idx)
    if parent.children.len > 0:
      parent.firstChild = parent.children[0]
      parent.lastChild = parent.children[^1]
    else:
      parent.firstChild = nil
      parent.lastChild = nil
    child.parent = nil
    parent.dirty = true

proc insertBefore*(parent, newChild, refChild: Node) =
  let idx = parent.children.find(refChild)
  if idx < 0:
    parent.appendChild(newChild)
    return
  newChild.parent = parent
  parent.children.insert(newChild, idx)
  if idx > 0:
    parent.children[idx - 1].nextSibling = newChild
    newChild.prevSibling = parent.children[idx - 1]
  newChild.nextSibling = refChild
  refChild.prevSibling = newChild
  parent.firstChild = parent.children[0]
  parent.dirty = true

proc replaceChild*(parent, newChild, oldChild: Node) =
  let idx = parent.children.find(oldChild)
  if idx < 0: return
  newChild.parent = parent
  if idx > 0:
    parent.children[idx - 1].nextSibling = newChild
    newChild.prevSibling = parent.children[idx - 1]
  if idx < parent.children.len - 1:
    parent.children[idx + 1].prevSibling = newChild
    newChild.nextSibling = parent.children[idx + 1]
  parent.children[idx] = newChild
  parent.dirty = true

proc cloneNode*(node: Node, deep = false): Node =
  result = newNode(node.kind, node.tag)
  result.id = node.id
  result.classes = node.classes
  result.attrs = node.attrs
  result.textContent = node.textContent
  result.inlineStyle = node.inlineStyle
  if deep:
    for child in node.children:
      result.appendChild(cloneNode(child, true))

proc setAttribute*(node: Node, name, value: string) =
  node.attrs[name] = value
  if name == "id":
    node.id = value
  elif name == "class":
    node.classes = value.split(' ').filterIt(it.len > 0)
  elif name.startsWith("data-"):
    node.dataset[name[5..^1]] = value
  elif name == "style":
    discard
  node.dirty = true

proc getAttribute*(node: Node, name: string): string =
  result = node.attrs.getOrDefault(name, "")

proc hasAttribute*(node: Node, name: string): bool =
  node.attrs.hasKey(name)

proc removeAttribute*(node: Node, name: string) =
  node.attrs.del(name)
  node.dirty = true

proc addClass*(node: Node, cls: string) =
  if cls notin node.classes:
    node.classes.add(cls)
    node.dirty = true

proc removeClass*(node: Node, cls: string) =
  let idx = node.classes.find(cls)
  if idx >= 0:
    node.classes.del(idx)
    node.dirty = true

proc toggleClass*(node: Node, cls: string): bool =
  if cls in node.classes:
    node.removeClass(cls)
    result = false
  else:
    node.addClass(cls)
    result = true

proc hasClass*(node: Node, cls: string): bool = cls in node.classes

proc matches*(node: Node, selector: string): bool

proc querySelector*(root: Node, selector: string): Node =
  if root.kind == nkElement and root.matches(selector):
    return root
  for child in root.children:
    result = child.querySelector(selector)
    if result != nil: return

proc querySelectorAll*(root: Node, selector: string): seq[Node] =
  if root.kind == nkElement and root.matches(selector):
    result.add(root)
  for child in root.children:
    result.add(child.querySelectorAll(selector))

proc getElementById*(root: Node, id: string): Node =
  root.querySelector("#" & id)

proc getElementsByTagName*(root: Node, tag: string): seq[Node] =
  root.querySelectorAll(tag)

proc getElementsByClassName*(root: Node, cls: string): seq[Node] =
  root.querySelectorAll("." & cls)

proc addEventListener*(node: Node, kind: EventKind, listener: EventListener) =
  if kind notin node.eventListeners:
    node.eventListeners[kind] = @[]
  node.eventListeners[kind].add(listener)

proc removeEventListener*(node: Node, kind: EventKind, listener: EventListener) =
  if kind in node.eventListeners:
    node.eventListeners[kind] = node.eventListeners[kind].filterIt(it != listener)

proc dispatchEvent*(node: Node, ev: Event): bool =
  ev.target = node
  ev.currentTarget = node
  result = true
  if ev.kind in node.eventListeners:
    for listener in node.eventListeners[ev.kind]:
      listener(ev)
      if ev.propagationStopped: break
  if ev.bubbles and not ev.propagationStopped and node.parent != nil:
    result = node.parent.dispatchEvent(ev)
  result = not ev.defaultPrevented

proc markDirty*(node: Node) =
  node.dirty = true
  node.layoutDirty = true
  node.paintDirty = true
  if node.parent != nil:
    node.parent.paintDirty = true
    var p = node.parent
    while p != nil:
      p.layoutDirty = true
      p = p.parent

proc cssVal*(v: float32, kind = cvLength): CssValue =
  CssValue(kind: kind, value: v)

proc cssAuto*(): CssValue = CssValue(kind: cvAuto)
proc cssNone*(): CssValue = CssValue(kind: cvNone)
proc cssPercent*(v: float32): CssValue = CssValue(kind: cvPercent, value: v)
proc cssEm*(v: float32): CssValue = CssValue(kind: cvEm, value: v)
proc cssRem*(v: float32): CssValue = CssValue(kind: cvRem, value: v)

proc rgba*(r, g, b: uint8, a: uint8 = 255): ColorRGBA = ColorRGBA(r: r, g: g, b: b, a: a)
proc transparent*(): ColorRGBA = ColorRGBA(r: 0, g: 0, b: 0, a: 0)

proc defaultStyle*(): ComputedStyle =
  result = ComputedStyle(
    display: dkBlock,
    position: pkStatic,
    float: fkNone,
    clear: ckNone,
    overflowX: ovVisible,
    overflowY: ovVisible,
    visibility: viVisible,
    opacity: 1.0,
    zIndex: 0,
    left: cssAuto(),
    top: cssAuto(),
    right: cssAuto(),
    bottom: cssAuto(),
    width: cssAuto(),
    height: cssAuto(),
    minWidth: cssVal(0),
    minHeight: cssVal(0),
    maxWidth: cssNone(),
    maxHeight: cssNone(),
    marginTop: cssVal(0),
    marginRight: cssVal(0),
    marginBottom: cssVal(0),
    marginLeft: cssVal(0),
    paddingTop: cssVal(0),
    paddingRight: cssVal(0),
    paddingBottom: cssVal(0),
    paddingLeft: cssVal(0),
    borderTopWidth: cssVal(0),
    borderRightWidth: cssVal(0),
    borderBottomWidth: cssVal(0),
    borderLeftWidth: cssVal(0),
    borderTopStyle: bsNone,
    borderRightStyle: bsNone,
    borderBottomStyle: bsNone,
    borderLeftStyle: bsNone,
    borderTopColor: rgba(0, 0, 0),
    borderRightColor: rgba(0, 0, 0),
    borderBottomColor: rgba(0, 0, 0),
    borderLeftColor: rgba(0, 0, 0),
    borderTopLeftRadius: cssVal(0),
    borderTopRightRadius: cssVal(0),
    borderBottomLeftRadius: cssVal(0),
    borderBottomRightRadius: cssVal(0),
    backgroundColor: transparent(),
    color: rgba(0, 0, 0),
    fontSize: cssVal(16),
    fontFamily: "sans-serif",
    fontWeight: fw400,
    fontStyle: fsNormal,
    lineHeight: cssAuto(),
    letterSpacing: cssVal(0),
    textAlign: taLeft,
    textDecoration: tdNone,
    textTransform: ttNone,
    textOverflow: toClip,
    whiteSpace: wsNormal,
    wordBreak: wbNormal,
    verticalAlign: vaBaseline,
    flexDirection: fdRow,
    flexWrap: fwNowrap,
    justifyContent: jcFlexStart,
    alignItems: aiStretch,
    alignContent: acStretch,
    alignSelf: asAuto,
    flexGrow: 0,
    flexShrink: 1,
    flexBasis: cssAuto(),
    order: 0,
    gap: cssVal(0),
    rowGap: cssVal(0),
    columnGap: cssVal(0),
    cursor: cuDefault,
    pointerEvents: peAuto,
    userSelect: usAuto,
    mixBlendMode: bmNormal,
    listStyleType: lsDisc,
    tableLayout: tlAuto,
    borderCollapse: bcSeparate,
    resize: rkNone,
    appearance: apAuto,
    caretColor: rgba(0, 0, 0),
    accentColor: rgba(0, 100, 210),
    scrollBehavior: sbAuto,
    objectFit: ofFill,
    objectPosition: (x: cssPercent(50), y: cssPercent(50))
  )

proc inlineDefaultStyle*(tag: string): ComputedStyle =
  result = defaultStyle()
  case tag
  of "div", "section", "article", "aside", "header", "footer", "main", "nav",
     "p", "h1", "h2", "h3", "h4", "h5", "h6", "form", "fieldset", "table",
     "ul", "ol", "li", "dl", "dt", "dd", "blockquote", "pre", "figure",
     "figcaption", "address", "details", "summary":
    result.display = dkBlock
  of "span", "a", "strong", "em", "b", "i", "u", "s", "code", "kbd",
     "samp", "var", "cite", "abbr", "time", "mark", "small", "sub", "sup",
     "bdi", "bdo", "q", "ruby", "rp", "rt":
    result.display = dkInline
  of "button", "input", "select", "textarea", "label", "img", "canvas",
     "video", "audio", "object", "embed", "iframe":
    result.display = dkInlineBlock
  of "table":
    result.display = dkTable
  of "tr":
    result.display = dkTableRow
  of "td", "th":
    result.display = dkTableCell
  of "thead":
    result.display = dkTableHeader
  of "tfoot":
    result.display = dkTableFooter
  of "li":
    result.display = dkListItem
  of "head", "script", "style", "meta", "link", "title":
    result.display = dkNone
  of "h1":
    result.fontSize = cssVal(32)
    result.fontWeight = fw700
    result.marginTop = cssVal(21)
    result.marginBottom = cssVal(21)
  of "h2":
    result.fontSize = cssVal(24)
    result.fontWeight = fw700
    result.marginTop = cssVal(19)
    result.marginBottom = cssVal(19)
  of "h3":
    result.fontSize = cssVal(18)
    result.fontWeight = fw700
    result.marginTop = cssVal(18)
    result.marginBottom = cssVal(18)
  of "h4":
    result.fontSize = cssVal(16)
    result.fontWeight = fw700
    result.marginTop = cssVal(21)
    result.marginBottom = cssVal(21)
  of "h5":
    result.fontSize = cssVal(13)
    result.fontWeight = fw700
    result.marginTop = cssVal(22)
    result.marginBottom = cssVal(22)
  of "h6":
    result.fontSize = cssVal(10)
    result.fontWeight = fw700
    result.marginTop = cssVal(24)
    result.marginBottom = cssVal(24)
  of "p":
    result.marginTop = cssVal(16)
    result.marginBottom = cssVal(16)
  of "a":
    result.color = rgba(0, 0, 238)
    result.textDecoration = tdUnderline
    result.cursor = cuPointer
  of "button":
    result.cursor = cuPointer
    result.appearance = apButton
    result.paddingTop = cssVal(2)
    result.paddingRight = cssVal(6)
    result.paddingBottom = cssVal(2)
    result.paddingLeft = cssVal(6)
    result.borderTopWidth = cssVal(1)
    result.borderRightWidth = cssVal(1)
    result.borderBottomWidth = cssVal(1)
    result.borderLeftWidth = cssVal(1)
    result.borderTopStyle = bsSolid
    result.borderRightStyle = bsSolid
    result.borderBottomStyle = bsSolid
    result.borderLeftStyle = bsSolid
  of "input":
    result.appearance = apTextfield
    result.paddingTop = cssVal(1)
    result.paddingRight = cssVal(2)
    result.paddingBottom = cssVal(1)
    result.paddingLeft = cssVal(2)
    result.borderTopWidth = cssVal(1)
    result.borderRightWidth = cssVal(1)
    result.borderBottomWidth = cssVal(1)
    result.borderLeftWidth = cssVal(1)
    result.borderTopStyle = bsSolid
    result.borderRightStyle = bsSolid
    result.borderBottomStyle = bsSolid
    result.borderLeftStyle = bsSolid
  of "img":
    result.width = cssAuto()
    result.height = cssAuto()
  of "pre", "code", "kbd", "samp":
    result.fontFamily = "monospace"
  of "strong", "b":
    result.fontWeight = fw700
  of "em", "i":
    result.fontStyle = fsItalic
  of "ul", "ol":
    result.paddingLeft = cssVal(40)
    result.marginTop = cssVal(16)
    result.marginBottom = cssVal(16)
  of "blockquote":
    result.marginLeft = cssVal(40)
    result.marginRight = cssVal(40)
    result.marginTop = cssVal(16)
    result.marginBottom = cssVal(16)
  else: discard

proc matches*(node: Node, selector: string): bool =
  if node.kind != nkElement: return false
  let sel = selector.strip()
  if sel == "*": return true
  if sel == node.tag: return true
  if sel.startsWith("#"):
    return node.id == sel[1..^1]
  if sel.startsWith("."):
    return sel[1..^1] in node.classes
  if sel.startsWith("["):
    let inner = sel[1..^2]
    if "=" in inner:
      let parts = inner.split('=', 1)
      let attrName = parts[0].strip(chars = {'[', ']', ' ', '"', '\''})
      let attrVal = parts[1].strip(chars = {'"', '\'', ' '})
      return node.getAttribute(attrName) == attrVal
    else:
      return node.hasAttribute(inner.strip())
  if "." in sel and not sel.startsWith("."):
    let parts = sel.split('.')
    if parts[0] != "" and parts[0] != node.tag: return false
    for i in 1..<parts.len:
      if parts[i] notin node.classes: return false
    return true
  if "#" in sel and not sel.startsWith("#"):
    let parts = sel.split('#')
    if parts[0] != "" and parts[0] != node.tag: return false
    return node.id == parts[1]
  false

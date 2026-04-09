import std/[tables, strutils, strscans, sequtils, parseutils, math, options, algorithm]
import ../core/dom

type
  SelectorPart* = object
    tag*: string
    id*: string
    classes*: seq[string]
    attrs*: seq[tuple[name, op, value: string]]
    pseudoClass*: seq[string]
    pseudoElement*: string
    combinator*: char

  Selector* = seq[SelectorPart]

  StyleRule* = object
    selectors*: seq[Selector]
    declarations*: Table[string, string]
    specificity*: tuple[a, b, c: int]
    sourceOrder*: int

  StyleSheet* = ref object
    rules*: seq[StyleRule]
    mediaRules*: seq[tuple[query: string, rules: seq[StyleRule]]]
    keyframes*: Table[string, seq[tuple[stop: float32, decls: Table[string, string]]]]
    source*: string

  CssParser* = ref object
    source*: string
    pos*: int
    sourceOrder*: int

proc newCssParser*(source: string): CssParser =
  CssParser(source: source, pos: 0, sourceOrder: 0)

proc peek(p: CssParser): char =
  if p.pos < p.source.len: p.source[p.pos] else: '\0'

proc advance(p: CssParser): char =
  result = p.source[p.pos]
  inc p.pos

proc skip(p: CssParser) =
  while p.pos < p.source.len and p.source[p.pos] in {' ', '\t', '\n', '\r'}:
    inc p.pos

proc skipWhitespaceAndComments(p: CssParser) =
  while p.pos < p.source.len:
    if p.source[p.pos] in {' ', '\t', '\n', '\r'}:
      inc p.pos
    elif p.pos + 1 < p.source.len and p.source[p.pos] == '/' and p.source[p.pos + 1] == '*':
      p.pos += 2
      while p.pos + 1 < p.source.len:
        if p.source[p.pos] == '*' and p.source[p.pos + 1] == '/':
          p.pos += 2
          break
        inc p.pos
    else:
      break

proc readIdent(p: CssParser): string =
  while p.pos < p.source.len and p.source[p.pos] in {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.'}:
    result.add(p.advance())

proc readUntil(p: CssParser, stop: set[char]): string =
  while p.pos < p.source.len and p.source[p.pos] notin stop:
    if p.source[p.pos] == '\\' and p.pos + 1 < p.source.len:
      inc p.pos
      result.add(p.advance())
    else:
      result.add(p.advance())

proc readString(p: CssParser): string =
  let q = p.advance()
  while p.pos < p.source.len and p.source[p.pos] != q:
    if p.source[p.pos] == '\\' and p.pos + 1 < p.source.len:
      inc p.pos
      result.add(p.advance())
    else:
      result.add(p.advance())
  if p.pos < p.source.len: inc p.pos

proc parseSelector*(s: string): seq[Selector] =
  var selectorGroups = s.split(',')
  for group in selectorGroups:
    var selector: Selector
    var parts = group.strip().splitWhitespace()
    var i = 0
    while i < parts.len:
      var part = parts[i]
      var sp = SelectorPart(combinator: ' ')
      if part in [">", "+", "~"]:
        sp.combinator = part[0]
        inc i
        if i < parts.len:
          part = parts[i]
        else: break
      var j = 0
      while j < part.len:
        case part[j]
        of '#':
          inc j
          var id = ""
          while j < part.len and part[j] notin {'#', '.', '[', ':'}:
            id.add(part[j])
            inc j
          sp.id = id
        of '.':
          inc j
          var cls = ""
          while j < part.len and part[j] notin {'#', '.', '[', ':'}:
            cls.add(part[j])
            inc j
          sp.classes.add(cls)
        of '[':
          inc j
          var attrStr = ""
          var depth = 1
          while j < part.len and depth > 0:
            if part[j] == '[': inc depth
            elif part[j] == ']': dec depth
            if depth > 0: attrStr.add(part[j])
            inc j
          var op = ""
          var name = ""
          var val = ""
          var k = 0
          while k < attrStr.len and attrStr[k] notin {'=', '~', '|', '^', '$', '*'}:
            name.add(attrStr[k])
            inc k
          if k < attrStr.len:
            if attrStr[k] in {'~', '|', '^', '$', '*'}:
              op.add(attrStr[k])
              inc k
            if k < attrStr.len and attrStr[k] == '=':
              op.add('=')
              inc k
            val = attrStr[k..^1].strip(chars = {'"', '\'', ' '})
          sp.attrs.add((name.strip(), op, val))
        of ':':
          inc j
          var isDouble = false
          if j < part.len and part[j] == ':':
            isDouble = true
            inc j
          var pseudo = ""
          var depth2 = 0
          while j < part.len:
            if part[j] == '(': inc depth2
            elif part[j] == ')': dec depth2
            if depth2 == 0 and part[j] in {'#', '.', '[', ':'}:
              break
            pseudo.add(part[j])
            inc j
          if isDouble:
            sp.pseudoElement = pseudo
          else:
            sp.pseudoClass.add(pseudo)
        else:
          var tag = ""
          while j < part.len and part[j] notin {'#', '.', '[', ':'}:
            tag.add(part[j])
            inc j
          sp.tag = tag
      selector.add(sp)
      inc i
    if selector.len > 0:
      result.add(selector)

proc calcSpecificity*(selector: Selector): tuple[a, b, c: int] =
  for part in selector:
    if part.id != "": inc result.a
    result.b += part.classes.len + part.attrs.len + part.pseudoClass.len
    if part.tag != "" and part.tag != "*": inc result.c
    if part.pseudoElement != "": inc result.c

proc matchesSelectorPart*(node: Node, part: SelectorPart): bool =
  if part.tag != "" and part.tag != "*" and part.tag != node.tag: return false
  if part.id != "" and part.id != node.id: return false
  for cls in part.classes:
    if cls notin node.classes: return false
  for attr in part.attrs:
    let val = node.getAttribute(attr.name)
    case attr.op
    of "": 
      if not node.hasAttribute(attr.name): return false
    of "=": 
      if val != attr.value: return false
    of "~=": 
      if attr.value notin val.split(' '): return false
    of "|=": 
      if val != attr.value and not val.startsWith(attr.value & "-"): return false
    of "^=": 
      if not val.startsWith(attr.value): return false
    of "$=": 
      if not val.endsWith(attr.value): return false
    of "*=": 
      if attr.value notin val: return false
    else: discard
  for pseudo in part.pseudoClass:
    let pname = pseudo.toLowerAscii()
    case pname
    of "hover", "active", "focus-within": discard
    of "focus":
      if not node.focused: return false
    of "checked":
      if not node.checked: return false
    of "disabled":
      if not node.disabled: return false
    of "enabled":
      if node.disabled: return false
    of "readonly", "read-only":
      if not node.readOnly: return false
    of "first-child":
      if node.prevSibling != nil: return false
    of "last-child":
      if node.nextSibling != nil: return false
    of "only-child":
      if node.prevSibling != nil or node.nextSibling != nil: return false
    of "root":
      if node.parent != nil and node.parent.kind != nkDocument: return false
    of "empty":
      if node.children.len > 0 or node.textContent.len > 0: return false
    else:
      if pname.startsWith("nth-child(") or pname.startsWith("nth-of-type("):
        discard
      elif pname.startsWith("not("):
        let inner = pname[4..^2]
        if node.matches(inner): return false
      elif pname.startsWith("is(") or pname.startsWith("where("):
        let inner = pname[pname.find('(') + 1..^2]
        var anyMatch = false
        for s in inner.split(','):
          if node.matches(s.strip()):
            anyMatch = true
            break
        if not anyMatch: return false
  result = true

proc matchesSelector*(node: Node, selector: Selector): bool =
  if selector.len == 0: return false
  var idx = selector.len - 1
  var current = node
  while idx >= 0 and current != nil:
    let part = selector[idx]
    if not current.matchesSelectorPart(part): return false
    dec idx
    if idx < 0: return true
    let nextPart = selector[idx]
    case nextPart.combinator
    of '>':
      current = current.parent
    of '+':
      current = current.prevSibling
    of '~':
      current = current.prevSibling
      while current != nil:
        if current.matchesSelectorPart(selector[idx]):
          break
        current = current.prevSibling
      if current == nil: return false
      dec idx
      if idx < 0: return true
      current = current.parent
    else:
      current = current.parent
      while current != nil:
        if current.matchesSelectorPart(selector[idx]):
          break
        current = current.parent
      if current == nil: return false
  result = idx < 0

proc parseDeclarations*(p: CssParser): Table[string, string] =
  p.skipWhitespaceAndComments()
  while p.pos < p.source.len and p.peek() != '}':
    p.skipWhitespaceAndComments()
    if p.peek() == '}': break
    let prop = p.readUntil({':',' ', '\t', '\n'}).toLowerAscii().strip()
    p.skipWhitespaceAndComments()
    if p.peek() == ':':
      discard p.advance()
      p.skipWhitespaceAndComments()
      var val = ""
      var depth = 0
      while p.pos < p.source.len:
        let c = p.peek()
        if c == '(' : inc depth
        elif c == ')': dec depth
        if depth == 0 and (c == ';' or c == '}'): break
        if c == '"' or c == '\'':
          val.add(p.readString())
        else:
          val.add(p.advance())
      val = val.strip()
      if val.endsWith("!important"):
        val = val[0..^11].strip()
      if prop.len > 0 and val.len > 0:
        result[prop] = val
      if p.peek() == ';': discard p.advance()
    else:
      discard p.readUntil({';', '}'})
      if p.peek() == ';': discard p.advance()
    p.skipWhitespaceAndComments()

proc parse*(p: CssParser): StyleSheet =
  result = StyleSheet(
    rules: @[],
    keyframes: initTable[string, seq[tuple[stop: float32, decls: Table[string, string]]]]()
  )
  while p.pos < p.source.len:
    p.skipWhitespaceAndComments()
    if p.pos >= p.source.len: break
    if p.peek() == '@':
      discard p.advance()
      let atRule = p.readIdent().toLowerAscii()
      p.skipWhitespaceAndComments()
      case atRule
      of "media":
        let query = p.readUntil({'{'}). strip()
        if p.peek() == '{': discard p.advance()
        var mediaRules: seq[StyleRule]
        p.skipWhitespaceAndComments()
        while p.pos < p.source.len and p.peek() != '}':
          p.skipWhitespaceAndComments()
          if p.peek() == '}': break
          let selStr = p.readUntil({'{', '}'}).strip()
          if p.peek() == '{':
            discard p.advance()
            let decls = p.parseDeclarations()
            if p.peek() == '}': discard p.advance()
            for sel in parseSelector(selStr):
              var rule = StyleRule(
                selectors: @[sel],
                declarations: decls,
                specificity: calcSpecificity(sel),
                sourceOrder: p.sourceOrder
              )
              inc p.sourceOrder
              mediaRules.add(rule)
          p.skipWhitespaceAndComments()
        if p.peek() == '}': discard p.advance()
        result.mediaRules.add((query, mediaRules))
      of "keyframes", "-webkit-keyframes":
        let animName = p.readUntil({'{', ' '}).strip()
        p.skipWhitespaceAndComments()
        if p.peek() == '{': discard p.advance()
        var frames: seq[tuple[stop: float32, decls: Table[string, string]]]
        p.skipWhitespaceAndComments()
        while p.pos < p.source.len and p.peek() != '}':
          let stopStr = p.readUntil({'{', '}'}).strip()
          if p.peek() == '{':
            discard p.advance()
            let decls = p.parseDeclarations()
            if p.peek() == '}': discard p.advance()
            let stopVal = if stopStr == "from": 0.0f
                         elif stopStr == "to": 100.0f
                         else: parseFloat(stopStr.replace("%", "")).float32
            frames.add((stopVal, decls))
          p.skipWhitespaceAndComments()
        if p.peek() == '}': discard p.advance()
        result.keyframes[animName] = frames
      of "font-face":
        if p.peek() == '{': discard p.advance()
        discard p.parseDeclarations()
        if p.peek() == '}': discard p.advance()
      of "import":
        discard p.readUntil({';', '\n'})
        if p.peek() == ';': discard p.advance()
      of "charset":
        discard p.readUntil({';'})
        if p.peek() == ';': discard p.advance()
      else:
        discard p.readUntil({'{', ';'})
        if p.peek() == '{':
          discard p.advance()
          var depth = 1
          while p.pos < p.source.len and depth > 0:
            let c = p.advance()
            if c == '{': inc depth
            elif c == '}': dec depth
        elif p.peek() == ';':
          discard p.advance()
    else:
      let selStr = p.readUntil({'{', '}'}).strip()
      if selStr.len == 0:
        if p.peek() in {'{', '}'}: discard p.advance()
        continue
      if p.peek() == '{':
        discard p.advance()
        let decls = p.parseDeclarations()
        if p.peek() == '}': discard p.advance()
        for sel in parseSelector(selStr):
          var rule = StyleRule(
            selectors: @[sel],
            declarations: decls,
            specificity: calcSpecificity(sel),
            sourceOrder: p.sourceOrder
          )
          inc p.sourceOrder
          result.rules.add(rule)
      elif p.peek() == '}':
        discard p.advance()

proc parseStyleSheet*(css: string): StyleSheet =
  let p = newCssParser(css)
  result = p.parse()
  result.source = css

proc parseInlineStyle*(style: string): Table[string, string] =
  let p = newCssParser(style & "}")
  result = p.parseDeclarations()

proc parseColor*(s: string): ColorRGBA =
  let v = s.strip().toLowerAscii()
  if v == "transparent" or v == "": return transparent()
  if v == "black": return rgba(0, 0, 0)
  if v == "white": return rgba(255, 255, 255)
  if v == "red": return rgba(255, 0, 0)
  if v == "green": return rgba(0, 128, 0)
  if v == "blue": return rgba(0, 0, 255)
  if v == "yellow": return rgba(255, 255, 0)
  if v == "cyan" or v == "aqua": return rgba(0, 255, 255)
  if v == "magenta" or v == "fuchsia": return rgba(255, 0, 255)
  if v == "orange": return rgba(255, 165, 0)
  if v == "purple": return rgba(128, 0, 128)
  if v == "pink": return rgba(255, 192, 203)
  if v == "brown": return rgba(165, 42, 42)
  if v == "gray" or v == "grey": return rgba(128, 128, 128)
  if v == "lightgray" or v == "lightgrey": return rgba(211, 211, 211)
  if v == "darkgray" or v == "darkgrey": return rgba(169, 169, 169)
  if v == "silver": return rgba(192, 192, 192)
  if v == "gold": return rgba(255, 215, 0)
  if v == "coral": return rgba(255, 127, 80)
  if v == "salmon": return rgba(250, 128, 114)
  if v == "tomato": return rgba(255, 99, 71)
  if v == "crimson": return rgba(220, 20, 60)
  if v == "navy": return rgba(0, 0, 128)
  if v == "teal": return rgba(0, 128, 128)
  if v == "olive": return rgba(128, 128, 0)
  if v == "maroon": return rgba(128, 0, 0)
  if v == "lime": return rgba(0, 255, 0)
  if v == "indigo": return rgba(75, 0, 130)
  if v == "violet": return rgba(238, 130, 238)
  if v == "turquoise": return rgba(64, 224, 208)
  if v == "skyblue": return rgba(135, 206, 235)
  if v == "steelblue": return rgba(70, 130, 180)
  if v == "currentcolor": return rgba(0, 0, 0)
  if v == "inherit" or v == "initial" or v == "unset": return rgba(0, 0, 0)
  if v.startsWith("#"):
    let h = v[1..^1]
    case h.len
    of 3:
      let r = parseHexInt($h[0] & $h[0]).uint8
      let g = parseHexInt($h[1] & $h[1]).uint8
      let b = parseHexInt($h[2] & $h[2]).uint8
      return rgba(r, g, b)
    of 4:
      let r = parseHexInt($h[0] & $h[0]).uint8
      let g = parseHexInt($h[1] & $h[1]).uint8
      let b = parseHexInt($h[2] & $h[2]).uint8
      let a = parseHexInt($h[3] & $h[3]).uint8
      return rgba(r, g, b, a)
    of 6:
      let r = parseHexInt(h[0..1]).uint8
      let g = parseHexInt(h[2..3]).uint8
      let b = parseHexInt(h[4..5]).uint8
      return rgba(r, g, b)
    of 8:
      let r = parseHexInt(h[0..1]).uint8
      let g = parseHexInt(h[2..3]).uint8
      let b = parseHexInt(h[4..5]).uint8
      let a = parseHexInt(h[6..7]).uint8
      return rgba(r, g, b, a)
    else: discard
  if v.startsWith("rgb(") or v.startsWith("rgba("):
    let inner = v[v.find('(') + 1..^2]
    let parts = inner.split(',')
    if parts.len >= 3:
      let r = parseInt(parts[0].strip()).uint8
      let g = parseInt(parts[1].strip()).uint8
      let b = parseInt(parts[2].strip()).uint8
      let a = if parts.len >= 4: (parseFloat(parts[3].strip()) * 255).uint8 else: 255u8
      return rgba(r, g, b, a)
  if v.startsWith("hsl(") or v.startsWith("hsla("):
    let inner = v[v.find('(') + 1..^2]
    let parts = inner.split(',')
    if parts.len >= 3:
      let h = parseFloat(parts[0].strip())
      let s = parseFloat(parts[1].strip().replace("%","")) / 100.0
      let l = parseFloat(parts[2].strip().replace("%","")) / 100.0
      let a = if parts.len >= 4: (parseFloat(parts[3].strip()) * 255).uint8 else: 255u8
      let c = (1.0 - abs(2.0 * l - 1.0)) * s
      let x = c * (1.0 - abs((h / 60.0) mod 2.0 - 1.0))
      let m = l - c / 2.0
      var r1, g1, b1: float64
      let hi = int(h / 60.0) mod 6
      case hi
      of 0: r1 = c; g1 = x; b1 = 0
      of 1: r1 = x; g1 = c; b1 = 0
      of 2: r1 = 0; g1 = c; b1 = x
      of 3: r1 = 0; g1 = x; b1 = c
      of 4: r1 = x; g1 = 0; b1 = c
      else: r1 = c; g1 = 0; b1 = x
      return rgba(
        ((r1 + m) * 255).uint8,
        ((g1 + m) * 255).uint8,
        ((b1 + m) * 255).uint8,
        a
      )
  transparent()

proc parseCssValue*(s: string, base: float32 = 16.0, rootBase: float32 = 16.0): CssValue =
  let v = s.strip().toLowerAscii()
  if v == "auto": return cssAuto()
  if v == "none": return cssNone()
  if v == "0": return cssVal(0)
  if v.endsWith("%"):
    let n = parseFloat(v[0..^2])
    return cssPercent(n.float32)
  if v.endsWith("px"):
    return cssVal(parseFloat(v[0..^3]).float32)
  if v.endsWith("em"):
    let n = parseFloat(v[0..^3])
    return cssEm(n.float32)
  if v.endsWith("rem"):
    let n = parseFloat(v[0..^4])
    return cssRem(n.float32)
  if v.endsWith("vw"):
    return CssValue(kind: cvVw, value: parseFloat(v[0..^3]).float32)
  if v.endsWith("vh"):
    return CssValue(kind: cvVh, value: parseFloat(v[0..^3]).float32)
  if v.endsWith("vmin"):
    return CssValue(kind: cvVmin, value: parseFloat(v[0..^5]).float32)
  if v.endsWith("vmax"):
    return CssValue(kind: cvVmax, value: parseFloat(v[0..^5]).float32)
  if v.endsWith("pt"):
    return cssVal((parseFloat(v[0..^3]) * 1.333333).float32)
  if v.endsWith("pc"):
    return cssVal((parseFloat(v[0..^3]) * 16).float32)
  if v.endsWith("cm"):
    return cssVal((parseFloat(v[0..^3]) * 37.7952755906).float32)
  if v.endsWith("mm"):
    return cssVal((parseFloat(v[0..^3]) * 3.77952755906).float32)
  if v.endsWith("in"):
    return cssVal((parseFloat(v[0..^3]) * 96).float32)
  if v.endsWith("fr"):
    return CssValue(kind: cvFr, value: parseFloat(v[0..^3]).float32)
  if v.endsWith("ch"):
    return CssValue(kind: cvCh, value: parseFloat(v[0..^3]).float32)
  if v.endsWith("ex"):
    return CssValue(kind: cvEx, value: parseFloat(v[0..^3]).float32)
  if v == "fit-content": return CssValue(kind: cvFitContent)
  if v == "min-content": return CssValue(kind: cvMinContent)
  if v == "max-content": return CssValue(kind: cvMaxContent)
  if v == "inherit": return CssValue(kind: cvInherit)
  if v == "initial": return CssValue(kind: cvInitial)
  if v == "unset": return CssValue(kind: cvUnset)
  try:
    return cssVal(parseFloat(v).float32)
  except: discard
  cssAuto()

proc resolveValue*(cv: CssValue, base: float32, rootBase: float32 = 16.0,
                   viewportW: float32 = 1280, viewportH: float32 = 720): float32 =
  case cv.kind
  of cvLength: cv.value
  of cvPercent: base * cv.value / 100.0
  of cvEm: base * cv.value
  of cvRem: rootBase * cv.value
  of cvVw: viewportW * cv.value / 100.0
  of cvVh: viewportH * cv.value / 100.0
  of cvVmin: min(viewportW, viewportH) * cv.value / 100.0
  of cvVmax: max(viewportW, viewportH) * cv.value / 100.0
  of cvCh: base * 0.5 * cv.value
  of cvEx: base * 0.5 * cv.value
  of cvFr: cv.value
  else: 0.0

proc applyDeclaration*(style: ComputedStyle, prop: string, value: string,
                        parentStyle: ComputedStyle = nil) =
  let v = value.strip()
  case prop
  of "display":
    if v == "none": style.display = dkNone
    elif v == "block": style.display = dkBlock
    elif v == "inline": style.display = dkInline
    elif v == "inline-block": style.display = dkInlineBlock
    elif v == "flex": style.display = dkFlex
    elif v == "inline-flex": style.display = dkInlineFlex
    elif v == "grid": style.display = dkGrid
    elif v == "inline-grid": style.display = dkInlineGrid
    elif v == "table": style.display = dkTable
    elif v == "table-row": style.display = dkTableRow
    elif v == "table-cell": style.display = dkTableCell
    elif v == "table-header-group": style.display = dkTableHeader
    elif v == "table-footer-group": style.display = dkTableFooter
    elif v == "list-item": style.display = dkListItem
    elif v == "contents": style.display = dkContents
    else: style.display = dkBlock
  of "position":
    if v == "static": style.position = pkStatic
    elif v == "relative": style.position = pkRelative
    elif v == "absolute": style.position = pkAbsolute
    elif v == "fixed": style.position = pkFixed
    elif v == "sticky": style.position = pkSticky
    else: style.position = pkStatic
  of "float":
    if v == "left": style.float = fkLeft
    elif v == "right": style.float = fkRight
    else: style.float = fkNone
  of "overflow":
    if v == "hidden": style.overflowX = ovHidden
    elif v == "scroll": style.overflowX = ovScroll
    elif v == "auto": style.overflowX = ovAuto
    elif v == "clip": style.overflowX = ovClip
    else: style.overflowX = ovVisible
    style.overflowY = style.overflowX
  of "overflow-x":
    if v == "hidden": style.overflowX = ovHidden
    elif v == "scroll": style.overflowX = ovScroll
    elif v == "auto": style.overflowX = ovAuto
    else: style.overflowX = ovVisible
  of "overflow-y":
    if v == "hidden": style.overflowY = ovHidden
    elif v == "scroll": style.overflowY = ovScroll
    elif v == "auto": style.overflowY = ovAuto
    else: style.overflowY = ovVisible
  of "visibility":
    if v == "hidden": style.visibility = viHidden
    elif v == "collapse": style.visibility = viCollapse
    else: style.visibility = viVisible
  of "opacity":
    try: style.opacity = parseFloat(v).float32
    except: discard
  of "z-index":
    try: style.zIndex = parseInt(v).int32
    except: discard
  of "left": style.left = parseCssValue(v)
  of "top": style.top = parseCssValue(v)
  of "right": style.right = parseCssValue(v)
  of "bottom": style.bottom = parseCssValue(v)
  of "width": style.width = parseCssValue(v)
  of "height": style.height = parseCssValue(v)
  of "min-width": style.minWidth = parseCssValue(v)
  of "min-height": style.minHeight = parseCssValue(v)
  of "max-width": style.maxWidth = parseCssValue(v)
  of "max-height": style.maxHeight = parseCssValue(v)
  of "margin":
    let parts = v.splitWhitespace()
    case parts.len
    of 1:
      let m = parseCssValue(parts[0])
      style.marginTop = m; style.marginRight = m
      style.marginBottom = m; style.marginLeft = m
    of 2:
      let mv = parseCssValue(parts[0]); let mh = parseCssValue(parts[1])
      style.marginTop = mv; style.marginBottom = mv
      style.marginLeft = mh; style.marginRight = mh
    of 3:
      style.marginTop = parseCssValue(parts[0])
      style.marginLeft = parseCssValue(parts[1])
      style.marginRight = parseCssValue(parts[1])
      style.marginBottom = parseCssValue(parts[2])
    of 4:
      style.marginTop = parseCssValue(parts[0])
      style.marginRight = parseCssValue(parts[1])
      style.marginBottom = parseCssValue(parts[2])
      style.marginLeft = parseCssValue(parts[3])
    else: discard
  of "margin-top": style.marginTop = parseCssValue(v)
  of "margin-right": style.marginRight = parseCssValue(v)
  of "margin-bottom": style.marginBottom = parseCssValue(v)
  of "margin-left": style.marginLeft = parseCssValue(v)
  of "padding":
    let parts = v.splitWhitespace()
    case parts.len
    of 1:
      let p = parseCssValue(parts[0])
      style.paddingTop = p; style.paddingRight = p
      style.paddingBottom = p; style.paddingLeft = p
    of 2:
      let pv = parseCssValue(parts[0]); let ph = parseCssValue(parts[1])
      style.paddingTop = pv; style.paddingBottom = pv
      style.paddingLeft = ph; style.paddingRight = ph
    of 3:
      style.paddingTop = parseCssValue(parts[0])
      style.paddingLeft = parseCssValue(parts[1])
      style.paddingRight = parseCssValue(parts[1])
      style.paddingBottom = parseCssValue(parts[2])
    of 4:
      style.paddingTop = parseCssValue(parts[0])
      style.paddingRight = parseCssValue(parts[1])
      style.paddingBottom = parseCssValue(parts[2])
      style.paddingLeft = parseCssValue(parts[3])
    else: discard
  of "padding-top": style.paddingTop = parseCssValue(v)
  of "padding-right": style.paddingRight = parseCssValue(v)
  of "padding-bottom": style.paddingBottom = parseCssValue(v)
  of "padding-left": style.paddingLeft = parseCssValue(v)
  of "border-width":
    let bw = parseCssValue(v)
    style.borderTopWidth = bw; style.borderRightWidth = bw
    style.borderBottomWidth = bw; style.borderLeftWidth = bw
  of "border-top-width": style.borderTopWidth = parseCssValue(v)
  of "border-right-width": style.borderRightWidth = parseCssValue(v)
  of "border-bottom-width": style.borderBottomWidth = parseCssValue(v)
  of "border-left-width": style.borderLeftWidth = parseCssValue(v)
  of "border-color":
    let bc = parseColor(v)
    style.borderTopColor = bc; style.borderRightColor = bc
    style.borderBottomColor = bc; style.borderLeftColor = bc
  of "border-top-color": style.borderTopColor = parseColor(v)
  of "border-right-color": style.borderRightColor = parseColor(v)
  of "border-bottom-color": style.borderBottomColor = parseColor(v)
  of "border-left-color": style.borderLeftColor = parseColor(v)
  of "border-style":
    var bs = bsNone
    if v == "solid": bs = bsSolid
    elif v == "dashed": bs = bsDashed
    elif v == "dotted": bs = bsDotted
    elif v == "double": bs = bsDouble
    elif v == "groove": bs = bsGroove
    elif v == "ridge": bs = bsRidge
    elif v == "inset": bs = bsInset
    elif v == "outset": bs = bsOutset
    elif v == "hidden": bs = bsHidden
    style.borderTopStyle = bs; style.borderRightStyle = bs
    style.borderBottomStyle = bs; style.borderLeftStyle = bs
  of "border-top-style":
    if v == "solid": style.borderTopStyle = bsSolid
    elif v == "dashed": style.borderTopStyle = bsDashed
    elif v == "dotted": style.borderTopStyle = bsDotted
    else: style.borderTopStyle = bsNone
  of "border-right-style":
    if v == "solid": style.borderRightStyle = bsSolid
    elif v == "dashed": style.borderRightStyle = bsDashed
    elif v == "dotted": style.borderRightStyle = bsDotted
    else: style.borderRightStyle = bsNone
  of "border-bottom-style":
    if v == "solid": style.borderBottomStyle = bsSolid
    elif v == "dashed": style.borderBottomStyle = bsDashed
    elif v == "dotted": style.borderBottomStyle = bsDotted
    else: style.borderBottomStyle = bsNone
  of "border-left-style":
    if v == "solid": style.borderLeftStyle = bsSolid
    elif v == "dashed": style.borderLeftStyle = bsDashed
    elif v == "dotted": style.borderLeftStyle = bsDotted
    else: style.borderLeftStyle = bsNone
  of "border":
    let parts = v.splitWhitespace()
    for part in parts:
      let lp = part.toLowerAscii()
      if lp.endsWith("px") or lp.endsWith("em") or lp == "0":
        let bw = parseCssValue(lp)
        style.borderTopWidth = bw; style.borderRightWidth = bw
        style.borderBottomWidth = bw; style.borderLeftWidth = bw
      elif lp in ["solid","dashed","dotted","double","groove","ridge","inset","outset","none","hidden"]:
        var bs = bsNone
        if lp == "solid": bs = bsSolid
        elif lp == "dashed": bs = bsDashed
        elif lp == "dotted": bs = bsDotted
        elif lp == "double": bs = bsDouble
        style.borderTopStyle = bs; style.borderRightStyle = bs
        style.borderBottomStyle = bs; style.borderLeftStyle = bs
      elif lp != "none" and lp.len > 0:
        let bc = parseColor(lp)
        if bc.a > 0 or lp == "transparent":
          style.borderTopColor = bc; style.borderRightColor = bc
          style.borderBottomColor = bc; style.borderLeftColor = bc
  of "border-radius":
    let parts = v.split('/')
    let radii = parts[0].splitWhitespace()
    case radii.len
    of 1:
      let r = parseCssValue(radii[0])
      style.borderTopLeftRadius = r; style.borderTopRightRadius = r
      style.borderBottomRightRadius = r; style.borderBottomLeftRadius = r
    of 2:
      style.borderTopLeftRadius = parseCssValue(radii[0])
      style.borderTopRightRadius = parseCssValue(radii[1])
      style.borderBottomRightRadius = parseCssValue(radii[0])
      style.borderBottomLeftRadius = parseCssValue(radii[1])
    of 3:
      style.borderTopLeftRadius = parseCssValue(radii[0])
      style.borderTopRightRadius = parseCssValue(radii[1])
      style.borderBottomRightRadius = parseCssValue(radii[2])
      style.borderBottomLeftRadius = parseCssValue(radii[1])
    of 4:
      style.borderTopLeftRadius = parseCssValue(radii[0])
      style.borderTopRightRadius = parseCssValue(radii[1])
      style.borderBottomRightRadius = parseCssValue(radii[2])
      style.borderBottomLeftRadius = parseCssValue(radii[3])
    else: discard
  of "border-top-left-radius": style.borderTopLeftRadius = parseCssValue(v)
  of "border-top-right-radius": style.borderTopRightRadius = parseCssValue(v)
  of "border-bottom-left-radius": style.borderBottomLeftRadius = parseCssValue(v)
  of "border-bottom-right-radius": style.borderBottomRightRadius = parseCssValue(v)
  of "background-color": style.backgroundColor = parseColor(v)
  of "background-image": style.backgroundImage = v
  of "background-repeat":
    if v == "no-repeat": style.backgroundRepeat = brNoRepeat
    elif v == "repeat-x": style.backgroundRepeat = brRepeatX
    elif v == "repeat-y": style.backgroundRepeat = brRepeatY
    elif v == "round": style.backgroundRepeat = brRound
    elif v == "space": style.backgroundRepeat = brSpace
    else: style.backgroundRepeat = brRepeat
  of "background-size":
    if v == "cover": style.backgroundSize = bszCover
    elif v == "contain": style.backgroundSize = bszContain
    else: style.backgroundSize = bszCustom # Simplified
  of "background":
    if v == "none" or v == "transparent":
      style.backgroundColor = transparent()
    elif v.startsWith("linear-gradient") or v.startsWith("radial-gradient") or
         v.startsWith("url("):
      style.backgroundImage = v
    else:
      style.backgroundColor = parseColor(v)
  of "color":
    if v == "inherit" and parentStyle != nil:
      style.color = parentStyle.color
    else:
      style.color = parseColor(v)
  of "font-size":
    if v == "inherit" and parentStyle != nil:
      style.fontSize = parentStyle.fontSize
    elif v == "smaller":
      style.fontSize = cssVal(
        if parentStyle != nil: parentStyle.fontSize.value * 0.833
        else: 13.333
      )
    elif v == "larger":
      style.fontSize = cssVal(
        if parentStyle != nil: parentStyle.fontSize.value * 1.2
        else: 19.2
      )
    elif v in ["xx-small","x-small","small","medium","large","x-large","xx-large"]:
      style.fontSize = cssVal(case v
        of "xx-small": 9.0
        of "x-small": 10.0
        of "small": 13.333
        of "medium": 16.0
        of "large": 18.0
        of "x-large": 24.0
        of "xx-large": 32.0
        else: 16.0
      )
    else:
      style.fontSize = parseCssValue(v, if parentStyle != nil: parentStyle.fontSize.value else: 16.0)
  of "font-family": style.fontFamily = v.strip(chars = {'"', '\''})
  of "font-weight":
    if v == "100": style.fontWeight = fw100
    elif v == "200": style.fontWeight = fw200
    elif v == "300": style.fontWeight = fw300
    elif v == "400" or v == "normal": style.fontWeight = fw400
    elif v == "500": style.fontWeight = fw500
    elif v == "600": style.fontWeight = fw600
    elif v == "700" or v == "bold": style.fontWeight = fw700
    elif v == "800": style.fontWeight = fw800
    elif v == "900": style.fontWeight = fw900
    else: style.fontWeight = fw400
  of "font-style":
    if v == "italic": style.fontStyle = fsItalic
    elif v == "oblique": style.fontStyle = fsOblique
    else: style.fontStyle = fsNormal
  of "font":
    let parts = v.splitWhitespace()
    var i = 0
    while i < parts.len - 1:
      let p = parts[i].toLowerAscii()
      if p in ["italic","oblique"]:
        style.fontStyle = if p == "italic": fsItalic else: fsOblique
      elif p in ["bold","100","200","300","400","500","600","700","800","900",
                 "lighter","bolder"]:
        if p == "bold" or p == "700": style.fontWeight = fw700
        elif p == "100": style.fontWeight = fw100
        elif p == "200": style.fontWeight = fw200
        elif p == "300" or p == "lighter": style.fontWeight = fw300
        elif p == "400" or p == "normal": style.fontWeight = fw400
        elif p == "500": style.fontWeight = fw500
        elif p == "600": style.fontWeight = fw600
        elif p == "800": style.fontWeight = fw800
        elif p == "900" or p == "bolder": style.fontWeight = fw900
        else: style.fontWeight = fw400
      elif "/" in p:
        let fparts = p.split('/')
        if fparts.len >= 1: style.fontSize = parseCssValue(fparts[0])
        if fparts.len >= 2: style.lineHeight = parseCssValue(fparts[1])
      elif p.endsWith("px") or p.endsWith("em") or p.endsWith("pt") or
           p.endsWith("rem") or p.endsWith("%"):
        style.fontSize = parseCssValue(p)
      inc i
    if parts.len > 0:
      style.fontFamily = parts[^1].strip(chars = {'"', '\''})
  of "line-height":
    if v == "normal": style.lineHeight = cssAuto()
    else: style.lineHeight = parseCssValue(v)
  of "letter-spacing": style.letterSpacing = parseCssValue(v)
  of "text-align":
    if v == "right": style.textAlign = taRight
    elif v == "center": style.textAlign = taCenter
    elif v == "justify": style.textAlign = taJustify
    elif v == "start": style.textAlign = taStart
    elif v == "end": style.textAlign = taEnd
    else: style.textAlign = taLeft
  of "text-decoration":
    if v == "underline": style.textDecoration = tdUnderline
    elif v == "overline": style.textDecoration = tdOverline
    elif v == "line-through": style.textDecoration = tdLineThrough
    else: style.textDecoration = tdNone
  of "text-transform":
    if v == "uppercase": style.textTransform = ttUppercase
    elif v == "lowercase": style.textTransform = ttLowercase
    elif v == "capitalize": style.textTransform = ttCapitalize
    else: style.textTransform = ttNone
  of "text-overflow":
    style.textOverflow = if v == "ellipsis": toEllipsis else: toClip
  of "white-space":
    if v == "pre": style.whiteSpace = wsPre
    elif v == "nowrap": style.whiteSpace = wsNowrap
    elif v == "pre-wrap": style.whiteSpace = wsPreWrap
    elif v == "pre-line": style.whiteSpace = wsPreLine
    elif v == "break-spaces": style.whiteSpace = wsBreakSpaces
    else: style.whiteSpace = wsNormal
  of "word-break":
    if v == "break-all": style.wordBreak = wbBreakAll
    elif v == "keep-all": style.wordBreak = wbKeepAll
    elif v == "break-word": style.wordBreak = wbBreakWord
    else: style.wordBreak = wbNormal
  of "vertical-align":
    if v == "top": style.verticalAlign = vaTop
    elif v == "middle": style.verticalAlign = vaMiddle
    elif v == "bottom": style.verticalAlign = vaBottom
    elif v == "text-top": style.verticalAlign = vaTextTop
    elif v == "text-bottom": style.verticalAlign = vaTextBottom
    elif v == "sub": style.verticalAlign = vaSub
    elif v == "super": style.verticalAlign = vaSuper
    else: style.verticalAlign = vaBaseline
  of "flex-direction":
    if v == "row-reverse": style.flexDirection = fdRowReverse
    elif v == "column": style.flexDirection = fdColumn
    elif v == "column-reverse": style.flexDirection = fdColumnReverse
    else: style.flexDirection = fdRow
  of "flex-wrap":
    if v == "wrap": style.flexWrap = fwWrap
    elif v == "wrap-reverse": style.flexWrap = fwWrapReverse
    else: style.flexWrap = fwNowrap
  of "flex-flow":
    let parts = v.splitWhitespace()
    for part in parts:
      applyDeclaration(style, "flex-direction", part)
      applyDeclaration(style, "flex-wrap", part)
  of "justify-content":
    if v == "flex-end" or v == "end": style.justifyContent = jcFlexEnd
    elif v == "center": style.justifyContent = jcCenter
    elif v == "space-between": style.justifyContent = jcSpaceBetween
    elif v == "space-around": style.justifyContent = jcSpaceAround
    elif v == "space-evenly": style.justifyContent = jcSpaceEvenly
    elif v == "stretch": style.justifyContent = jcStretch
    else: style.justifyContent = jcFlexStart
  of "align-items":
    if v == "flex-end" or v == "end": style.alignItems = aiFlexEnd
    elif v == "center": style.alignItems = aiCenter
    elif v == "baseline": style.alignItems = aiBaseline
    elif v == "flex-start" or v == "start": style.alignItems = aiFlexStart
    else: style.alignItems = aiStretch
  of "align-content":
    if v == "flex-end": style.alignContent = acFlexEnd
    elif v == "center": style.alignContent = acCenter
    elif v == "space-between": style.alignContent = acSpaceBetween
    elif v == "space-around": style.alignContent = acSpaceAround
    elif v == "stretch": style.alignContent = acStretch
    else: style.alignContent = acFlexStart
  of "align-self":
    if v == "flex-start" or v == "start": style.alignSelf = asFlexStart
    elif v == "flex-end" or v == "end": style.alignSelf = asFlexEnd
    elif v == "center": style.alignSelf = asCenter
    elif v == "baseline": style.alignSelf = asBaseline
    elif v == "stretch": style.alignSelf = asStretch
    else: style.alignSelf = asAuto
  of "flex-grow":
    try: style.flexGrow = parseFloat(v).float32
    except: discard
  of "flex-shrink":
    try: style.flexShrink = parseFloat(v).float32
    except: discard
  of "flex-basis": style.flexBasis = parseCssValue(v)
  of "flex":
    if v == "none":
      style.flexGrow = 0; style.flexShrink = 0; style.flexBasis = cssAuto()
    elif v == "auto":
      style.flexGrow = 1; style.flexShrink = 1; style.flexBasis = cssAuto()
    elif v == "1" or v == "1 1 0%":
      style.flexGrow = 1; style.flexShrink = 1; style.flexBasis = cssVal(0)
    else:
      let parts = v.splitWhitespace()
      if parts.len >= 1: (try: style.flexGrow = parseFloat(parts[0]).float32 except: discard)
      if parts.len >= 2: (try: style.flexShrink = parseFloat(parts[1]).float32 except: discard)
      if parts.len >= 3: style.flexBasis = parseCssValue(parts[2])
  of "order":
    try: style.order = parseInt(v).int32
    except: discard
  of "gap", "grid-gap":
    let parts = v.splitWhitespace()
    if parts.len >= 1:
      let g = parseCssValue(parts[0])
      style.gap = g; style.rowGap = g; style.columnGap = g
    if parts.len >= 2:
      style.rowGap = parseCssValue(parts[0])
      style.columnGap = parseCssValue(parts[1])
  of "row-gap": style.rowGap = parseCssValue(v)
  of "column-gap": style.columnGap = parseCssValue(v)
  of "grid-template-columns": style.gridTemplateColumns = v
  of "grid-template-rows": style.gridTemplateRows = v
  of "grid-column": style.gridColumn = v
  of "grid-row": style.gridRow = v
  of "cursor":
    if v == "pointer": style.cursor = cuPointer
    elif v == "crosshair": style.cursor = cuCrosshair
    elif v == "text": style.cursor = cuText
    elif v == "move": style.cursor = cuMove
    elif v == "not-allowed": style.cursor = cuNotAllowed
    elif v == "wait": style.cursor = cuWait
    elif v == "help": style.cursor = cuHelp
    elif v == "n-resize": style.cursor = cuNResize
    elif v == "e-resize": style.cursor = cuEResize
    elif v == "s-resize": style.cursor = cuSResize
    elif v == "w-resize": style.cursor = cuWResize
    elif v == "ew-resize": style.cursor = cuEWResize
    elif v == "ns-resize": style.cursor = cuNSResize
    elif v == "grab": style.cursor = cuGrab
    elif v == "grabbing": style.cursor = cuGrabbing
    elif v == "zoom-in": style.cursor = cuZoomIn
    elif v == "zoom-out": style.cursor = cuZoomOut
    elif v == "none": style.cursor = cuNone
    else: style.cursor = cuDefault
  of "pointer-events":
    if v == "none": style.pointerEvents = peNone
    elif v == "all": style.pointerEvents = peAll
    else: style.pointerEvents = peAuto
  of "user-select":
    if v == "none": style.userSelect = usNone
    elif v == "text": style.userSelect = usText
    elif v == "all": style.userSelect = usAll
    else: style.userSelect = usAuto
  of "box-shadow":
    if v == "none":
      style.boxShadow = @[]
    else:
      style.boxShadow = @[]
      for shadowStr in v.split(", "):
        let parts = shadowStr.strip().splitWhitespace()
        if parts.len >= 4:
          var shadow = BoxShadow()
          var i2 = 0
          if parts[i2].toLowerAscii() == "inset":
            shadow.inset = true
            inc i2
          try:
            shadow.x = parseFloat(parts[i2].replace("px","")).float32; inc i2
            shadow.y = parseFloat(parts[i2].replace("px","")).float32; inc i2
            if i2 < parts.len:
              shadow.blur = parseFloat(parts[i2].replace("px","")).float32; inc i2
            if i2 < parts.len and (parts[i2].endsWith("px") or parts[i2][0].isDigit):
              shadow.spread = parseFloat(parts[i2].replace("px","")).float32; inc i2
            if i2 < parts.len:
              shadow.color = parseColor(parts[i2])
            style.boxShadow.add(shadow)
          except: discard
  of "text-shadow":
    if v == "none":
      style.textShadow = @[]
    else:
      style.textShadow = @[]
      for shadowStr in v.split(", "):
        let parts = shadowStr.strip().splitWhitespace()
        if parts.len >= 3:
          try:
            var shadow = TextShadow()
            shadow.x = parseFloat(parts[0].replace("px","")).float32
            shadow.y = parseFloat(parts[1].replace("px","")).float32
            shadow.blur = parseFloat(parts[2].replace("px","")).float32
            if parts.len >= 4:
              shadow.color = parseColor(parts[3])
            style.textShadow.add(shadow)
          except: discard
  of "transform":
    style.transform = @[]
    if v == "none": return
    var pos = 0
    while pos < v.len:
      while pos < v.len and v[pos] == ' ': inc pos
      var name = ""
      while pos < v.len and v[pos] notin {'(', ' '}: name.add(v[pos]); inc pos
      if pos < v.len and v[pos] == '(':
        inc pos
        var args = ""
        var depth = 1
        while pos < v.len and depth > 0:
          if v[pos] == '(': inc depth
          elif v[pos] == ')': dec depth
          if depth > 0: args.add(v[pos])
          inc pos
        var tr = Transform2D()
        case name.toLowerAscii()
        of "translate":
          tr.kind = trTranslate
          let p2 = args.split(',')
          tr.values[0] = try: parseFloat(p2[0].strip().replace("px","")).float32 except: 0
          tr.values[1] = if p2.len > 1: (try: parseFloat(p2[1].strip().replace("px","")).float32 except: 0) else: 0
        of "translatex":
          tr.kind = trTranslateX
          tr.values[0] = try: parseFloat(args.replace("px","")).float32 except: 0
        of "translatey":
          tr.kind = trTranslateY
          tr.values[0] = try: parseFloat(args.replace("px","")).float32 except: 0
        of "scale":
          tr.kind = trScale
          let p2 = args.split(',')
          tr.values[0] = try: parseFloat(p2[0].strip()).float32 except: 1
          tr.values[1] = if p2.len > 1: (try: parseFloat(p2[1].strip()).float32 except: 1) else: tr.values[0]
        of "scalex":
          tr.kind = trScaleX
          tr.values[0] = try: parseFloat(args).float32 except: 1
        of "scaley":
          tr.kind = trScaleY
          tr.values[0] = try: parseFloat(args).float32 except: 1
        of "rotate":
          tr.kind = trRotate
          tr.values[0] = try:
            if args.endsWith("deg"): parseFloat(args[0..^4]).float32
            elif args.endsWith("rad"): (parseFloat(args[0..^4]) * 180.0 / PI).float32
            elif args.endsWith("turn"): (parseFloat(args[0..^5]) * 360.0).float32
            else: parseFloat(args).float32
          except: 0
        of "skewx":
          tr.kind = trSkewX
          tr.values[0] = try: parseFloat(args.replace("deg","")).float32 except: 0
        of "skewy":
          tr.kind = trSkewY
          tr.values[0] = try: parseFloat(args.replace("deg","")).float32 except: 0
        of "matrix":
          tr.kind = trMatrix
          let p2 = args.split(',')
          for k in 0..<min(6, p2.len):
            tr.values[k] = try: parseFloat(p2[k].strip()).float32 except: 0
        of "perspective":
          tr.kind = trPerspective
          tr.values[0] = try: parseFloat(args.replace("px","")).float32 except: 0
        else: discard
        style.transform.add(tr)
  of "transition":
    style.transition = @[]
    if v == "none": return
    for tStr in v.split(", "):
      let parts = tStr.strip().splitWhitespace()
      if parts.len >= 2:
        var tr = Transition()
        tr.property = parts[0]
        tr.duration = try:
          if parts[1].endsWith("ms"): parseFloat(parts[1][0..^3]).float32 / 1000.0
          elif parts[1].endsWith("s"): parseFloat(parts[1][0..^2]).float32
          else: parseFloat(parts[1]).float32
        except: 0
        if parts.len >= 3:
          let tf = parts[2]
          if tf == "linear": tr.timingFunction = ekLinear
          elif tf == "ease-in": tr.timingFunction = ekEaseIn
          elif tf == "ease-out": tr.timingFunction = ekEaseOut
          elif tf == "ease-in-out": tr.timingFunction = ekEaseInOut
          elif tf == "step-start": tr.timingFunction = ekStepStart
          elif tf == "step-end": tr.timingFunction = ekStepEnd
          else: tr.timingFunction = ekEase
        if parts.len >= 4:
          tr.delay = try:
            if parts[3].endsWith("ms"): parseFloat(parts[3][0..^3]).float32 / 1000.0
            elif parts[3].endsWith("s"): parseFloat(parts[3][0..^2]).float32
            else: parseFloat(parts[3]).float32
          except: 0
        style.transition.add(tr)
  of "mix-blend-mode":
    if v == "multiply": style.mixBlendMode = bmMultiply
    elif v == "screen": style.mixBlendMode = bmScreen
    elif v == "overlay": style.mixBlendMode = bmOverlay
    elif v == "darken": style.mixBlendMode = bmDarken
    elif v == "lighten": style.mixBlendMode = bmLighten
    elif v == "color-dodge": style.mixBlendMode = bmColorDodge
    elif v == "color-burn": style.mixBlendMode = bmColorBurn
    elif v == "hard-light": style.mixBlendMode = bmHardLight
    elif v == "soft-light": style.mixBlendMode = bmSoftLight
    elif v == "difference": style.mixBlendMode = bmDifference
    elif v == "exclusion": style.mixBlendMode = bmExclusion
    elif v == "hue": style.mixBlendMode = bmHue
    elif v == "saturation": style.mixBlendMode = bmSaturation
    elif v == "color": style.mixBlendMode = bmColor
    elif v == "luminosity": style.mixBlendMode = bmLuminosity
    else: style.mixBlendMode = bmNormal
  of "object-fit":
    if v == "contain": style.objectFit = ofContain
    elif v == "cover": style.objectFit = ofCover
    elif v == "none": style.objectFit = ofNone
    elif v == "scale-down": style.objectFit = ofScaleDown
    else: style.objectFit = ofFill
  of "box-sizing":
    if v == "border-box": style.boxSizing = bszBorderBox
    else: style.boxSizing = bszContentBox
  of "aspect-ratio":
    if v == "auto":
      style.aspectRatio = none(tuple[w, h: float32])
    else:
      let parts = v.split('/')
      if parts.len == 2:
        try:
          style.aspectRatio = some((
            parseFloat(parts[0].strip()).float32,
            parseFloat(parts[1].strip()).float32
          ))
        except: discard
      elif parts.len == 1:
        try:
          style.aspectRatio = some((parseFloat(parts[0].strip()).float32, 1.0f32))
        except: discard
  of "content":
    style.content = v.strip(chars = {'"', '\''})
  of "list-style-type":
    if v == "none": style.listStyleType = lsNone
    elif v == "disc": style.listStyleType = lsDisc
    elif v == "circle": style.listStyleType = lsCircle
    elif v == "square": style.listStyleType = lsSquare
    elif v == "decimal": style.listStyleType = lsDecimal
    elif v == "lower-alpha": style.listStyleType = lsAlpha
    elif v == "upper-alpha": style.listStyleType = lsUpperAlpha
    elif v == "lower-roman": style.listStyleType = lsRoman
    elif v == "upper-roman": style.listStyleType = lsUpperRoman
    else: style.listStyleType = lsDisc
  of "table-layout":
    style.tableLayout = if v == "fixed": tlFixed else: tlAuto
  of "border-collapse":
    style.borderCollapse = if v == "collapse": bcCollapse else: bcSeparate
  of "resize":
    if v == "both": style.resize = rkBoth
    elif v == "horizontal": style.resize = rkHorizontal
    elif v == "vertical": style.resize = rkVertical
    else: style.resize = rkNone
  of "scroll-behavior":
    style.scrollBehavior = if v == "smooth": sbSmooth else: sbAuto
  of "caret-color": style.caretColor = parseColor(v)
  of "accent-color": style.accentColor = parseColor(v)
  of "outline":
    let parts = v.splitWhitespace()
    for part in parts:
      let lp = part.toLowerAscii()
      if lp.endsWith("px") or lp == "0":
        style.outline = parseCssValue(lp)
      elif lp in ["solid","dashed","dotted","double","none"]:
        if lp == "solid": style.outlineStyle = bsSolid
        elif lp == "dashed": style.outlineStyle = bsDashed
        elif lp == "dotted": style.outlineStyle = bsDotted
        else: style.outlineStyle = bsNone
      else:
        style.outlineColor = parseColor(lp)
  of "clip-path": style.clipPath = v
  of "filter", "backdrop-filter":
    var filters: seq[CssFilter]
    var pos2 = 0
    while pos2 < v.len:
      while pos2 < v.len and v[pos2] == ' ': inc pos2
      var fname = ""
      while pos2 < v.len and v[pos2] notin {'(', ' '}: fname.add(v[pos2]); inc pos2
      if pos2 < v.len and v[pos2] == '(':
        inc pos2
        var fargs = ""
        var depth = 1
        while pos2 < v.len and depth > 0:
          if v[pos2] == '(': inc depth
          elif v[pos2] == ')': dec depth
          if depth > 0: fargs.add(v[pos2])
          inc pos2
        var f = CssFilter()
        case fname.toLowerAscii()
        of "blur":
          f.kind = cfBlur
          f.value = try: parseFloat(fargs.replace("px","")).float32 except: 0
        of "brightness":
          f.kind = cfBrightness
          f.value = try:
            let s = fargs.replace("%","")
            let n = parseFloat(s)
            if "%" in fargs: n.float32 / 100.0 else: n.float32
          except: 1.0
        of "contrast":
          f.kind = cfContrast
          f.value = try:
            let s = fargs.replace("%","")
            let n = parseFloat(s)
            if "%" in fargs: n.float32 / 100.0 else: n.float32
          except: 1.0
        of "grayscale":
          f.kind = cfGrayscale
          f.value = try:
            let s = fargs.replace("%","")
            let n = parseFloat(s)
            if "%" in fargs: n.float32 / 100.0 else: n.float32
          except: 0
        of "hue-rotate":
          f.kind = cfHueRotate
          f.value = try: parseFloat(fargs.replace("deg","")).float32 except: 0
        of "invert":
          f.kind = cfInvert
          f.value = try:
            let s = fargs.replace("%","")
            if "%" in fargs: parseFloat(s).float32 / 100.0 else: parseFloat(s).float32
          except: 0
        of "opacity":
          f.kind = cfOpacity
          f.value = try:
            let s = fargs.replace("%","")
            if "%" in fargs: parseFloat(s).float32 / 100.0 else: parseFloat(s).float32
          except: 1
        of "saturate":
          f.kind = cfSaturate
          f.value = try:
            let s = fargs.replace("%","")
            if "%" in fargs: parseFloat(s).float32 / 100.0 else: parseFloat(s).float32
          except: 1
        of "sepia":
          f.kind = cfSepia
          f.value = try:
            let s = fargs.replace("%","")
            if "%" in fargs: parseFloat(s).float32 / 100.0 else: parseFloat(s).float32
          except: 0
        else: discard
        filters.add(f)
    if prop == "filter": style.filter = filters
    else: style.backdropFilter = filters
  else: discard

type
  StyleResolver* = ref object
    sheets*: seq[StyleSheet]
    userAgentSheet*: StyleSheet
    inlineOverrides*: Table[uint32, Table[string, string]]
    viewportWidth*, viewportHeight*: float32
    rootFontSize*: float32
    matchCache*: Table[uint64, bool]

proc newStyleResolver*(): StyleResolver =
  result = StyleResolver(
    sheets: @[],
    viewportWidth: 1280,
    viewportHeight: 720,
    rootFontSize: 16.0,
    matchCache: initTable[uint64, bool]()
  )

proc addStyleSheet*(resolver: StyleResolver, sheet: StyleSheet) =
  resolver.sheets.add(sheet)

proc resolveStyles*(resolver: StyleResolver, root: Node) =
  proc resolveNode(node: Node, parentStyle: ComputedStyle) =
    if node.kind == nkText:
      node.computedStyle = if parentStyle != nil: parentStyle else: defaultStyle()
      return
    if node.kind != nkElement:
      for child in node.children:
        resolveNode(child, parentStyle)
      return
    var style = inlineDefaultStyle(node.tag)
    if parentStyle != nil:
      style.color = parentStyle.color
      style.fontSize = parentStyle.fontSize
      style.fontFamily = parentStyle.fontFamily
      style.fontWeight = parentStyle.fontWeight
      style.fontStyle = parentStyle.fontStyle
      style.lineHeight = parentStyle.lineHeight
      style.textAlign = parentStyle.textAlign
      style.visibility = parentStyle.visibility
      style.cursor = parentStyle.cursor
      style.listStyleType = parentStyle.listStyleType
    var matchedRules: seq[tuple[spec: tuple[a,b,c: int], order: int, decls: Table[string, string]]]
    for sheet in resolver.sheets:
      for rule in sheet.rules:
        for selector in rule.selectors:
          if node.matchesSelector(selector):
            matchedRules.add((rule.specificity, rule.sourceOrder, rule.declarations))
            break
    sort(matchedRules, proc(a, b: tuple[spec: tuple[a,b,c: int], order: int, decls: Table[string, string]]): int =
      if a.spec.a != b.spec.a: return cmp(a.spec.a, b.spec.a)
      if a.spec.b != b.spec.b: return cmp(a.spec.b, b.spec.b)
      if a.spec.c != b.spec.c: return cmp(a.spec.c, b.spec.c)
      cmp(a.order, b.order)
    )
    for rule in matchedRules:
      for prop, val in rule.decls:
        applyDeclaration(style, prop, val, parentStyle)
    for prop, val in node.inlineStyle:
      applyDeclaration(style, prop, val, parentStyle)
    node.computedStyle = style
    for child in node.children:
      resolveNode(child, style)
  resolveNode(root, nil)

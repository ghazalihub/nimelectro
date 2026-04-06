import std/[math, strutils, tables, sequtils, options]
import pixie
import pixie/fontformats/opentype
import ../core/dom
import ../css/resolver
import ../layout/engine

type
  FontCache* = ref object
    fonts*: Table[string, Font]
    typefaces*: Table[string, Typeface]
    defaultTypeface*: Typeface

  ImageCache* = ref object
    images*: Table[string, Image]

  RenderState* = ref object
    ctx*: Context
    fontCache*: FontCache
    imageCache*: ImageCache
    viewportWidth*: float32
    viewportHeight*: float32
    scale*: float32
    rootFontSize*: float32
    hoveredNode*: Node
    focusedNode*: Node
    activeNode*: Node
    selectionStart*: Node
    selectionEnd*: Node

  GradientStop* = object
    offset*: float32
    color*: ColorRGBA

proc newFontCache*(): FontCache =
  FontCache(
    fonts: initTable[string, Font](),
    typefaces: initTable[string, Typeface]()
  )

proc newRenderState*(width, height: int, scale: float32 = 1.0): RenderState =
  let img = newImage(width, height)
  result = RenderState(
    ctx: newContext(img),
    fontCache: newFontCache(),
    imageCache: ImageCache(images: initTable[string, Image]()),
    viewportWidth: width.float32,
    viewportHeight: height.float32,
    scale: scale,
    rootFontSize: 16.0
  )

proc getFont*(fc: FontCache, family: string, size: float32,
               weight: FontWeightKind, style: FontStyleKind): Font =
  let key = family & ":" & $size & ":" & $weight & ":" & $style
  if key in fc.fonts: return fc.fonts[key]
  var tf: Typeface
  if family in fc.typefaces:
    tf = fc.typefaces[family]
  elif fc.defaultTypeface != nil:
    tf = fc.defaultTypeface
  else:
    try:
      let paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Arial.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/noto/NotoSans-Regular.ttf"
      ]
      var loaded = false
      for path in paths:
        try:
          tf = readTypeface(path)
          fc.defaultTypeface = tf
          loaded = true
          break
        except: discard
      if not loaded:
        let f = Font()
        fc.fonts[key] = f
        return f
    except:
      let f = Font()
      fc.fonts[key] = f
      return f
  var f = newFont(tf)
  f.size = size
  fc.fonts[key] = f
  result = f

proc toPColor*(c: ColorRGBA): pixie.Color =
  pixie.color(c.r.float32 / 255, c.g.float32 / 255, c.b.float32 / 255, c.a.float32 / 255)

proc toRGBX*(c: ColorRGBA): ColorRGBX =
  rgba(c.r, c.g, c.b, c.a).asRGBX()

proc alphaBlend*(base, overlay: ColorRGBA): ColorRGBA =
  let a = overlay.a.float32 / 255.0
  let ia = 1.0 - a
  result.r = uint8(overlay.r.float32 * a + base.r.float32 * ia)
  result.g = uint8(overlay.g.float32 * a + base.g.float32 * ia)
  result.b = uint8(overlay.b.float32 * a + base.b.float32 * ia)
  result.a = uint8(min(255.0, base.a.float32 + overlay.a.float32 * ia))

proc parseGradient*(s: string): seq[GradientStop] =
  let inner = s[s.find('(') + 1..^2]
  var colorStops: seq[GradientStop]
  var depth = 0
  var current = ""
  var parts: seq[string]
  for c in inner:
    if c == '(': inc depth
    elif c == ')': dec depth
    if c == ',' and depth == 0:
      parts.add(current.strip())
      current = ""
    else:
      current.add(c)
  if current.strip().len > 0: parts.add(current.strip())
  var colorCount = 0
  var colorParts: seq[string]
  var anglePart = ""
  for i, p in parts:
    if i == 0 and (p.endsWith("deg") or p.endsWith("turn") or p.startsWith("to ")):
      anglePart = p
    else:
      colorParts.add(p)
  for i, p in colorParts:
    let tokens = p.splitWhitespace()
    if tokens.len >= 1:
      let col = parseColor(tokens[0])
      var offset = float32(i) / max(float32(colorParts.len - 1), 1)
      if tokens.len >= 2 and tokens[1].endsWith("%"):
        try: offset = parseFloat(tokens[1].replace("%","")).float32 / 100.0
        except: discard
      colorStops.add(GradientStop(offset: offset, color: col))
  result = colorStops

proc makeGradientPaint*(s: string, x, y, w, h: float32): Paint =
  let gradType = if s.startsWith("linear"): "linear"
                 elif s.startsWith("radial"): "radial"
                 else: "linear"
  let stops = parseGradient(s)
  if gradType == "linear":
    var angle = 180.0f32
    if "deg" in s:
      let dPos = s.find("deg")
      var i = dPos - 1
      var numStr = ""
      while i >= 0 and (s[i].isDigit or s[i] == '.' or s[i] == '-'):
        numStr = $s[i] & numStr
        dec i
      try: angle = parseFloat(numStr).float32
      except: discard
    elif s.startsWith("linear-gradient(to "):
      let dir = s[19..s.find(',') - 1].strip()
      case dir
      of "right": angle = 90
      of "left": angle = 270
      of "top": angle = 0
      of "bottom": angle = 180
      of "bottom right": angle = 135
      of "bottom left": angle = 225
      of "top right": angle = 45
      of "top left": angle = 315
      else: discard
    let rad = angle * PI / 180.0
    let cx = x + w / 2; let cy = y + h / 2
    let len = sqrt(w * w + h * h) / 2
    result = newPaint(LinearGradientPaint)
    result.gradientHandlePositions = @[
      vec2(cx - sin(rad) * len, cy + cos(rad) * len),
      vec2(cx + sin(rad) * len, cy - cos(rad) * len)
    ]
  else:
    result = newPaint(RadialGradientPaint)
    result.gradientHandlePositions = @[
      vec2(x + w / 2, y + h / 2),
      vec2(x + w, y + h / 2),
      vec2(x + w / 2, y + h)
    ]
  var colorStops: seq[ColorStop]
  for stop in stops:
    colorStops.add(ColorStop(
      color: stop.color.toPColor(),
      position: stop.offset
    ))
  result.gradientStops = colorStops

proc roundedRectPath*(x, y, w, h,
                       tl, tr, br, bl: float32): Path =
  result = newPath()
  let rx0 = min(tl, min(w / 2, h / 2))
  let rx1 = min(tr, min(w / 2, h / 2))
  let rx2 = min(br, min(w / 2, h / 2))
  let rx3 = min(bl, min(w / 2, h / 2))
  result.moveTo(x + rx0, y)
  result.lineTo(x + w - rx1, y)
  if rx1 > 0: result.arcTo(x + w, y, x + w, y + rx1, rx1)
  result.lineTo(x + w, y + h - rx2)
  if rx2 > 0: result.arcTo(x + w, y + h, x + w - rx2, y + h, rx2)
  result.lineTo(x + rx3, y + h)
  if rx3 > 0: result.arcTo(x, y + h, x, y + h - rx3, rx3)
  result.lineTo(x, y + rx0)
  if rx0 > 0: result.arcTo(x, y, x + rx0, y, rx0)
  result.closePath()

proc dashPath*(ctx: Context, path: Path, dashLen, gapLen: float32) =
  ctx.stroke(path)

proc drawBorder*(ctx: Context, x, y, w, h: float32,
                  style: ComputedStyle, fontSize: float32, rootFontSize: float32,
                  vw: float32, vh: float32) =
  proc rv(cv: CssValue, base: float32): float32 =
    resolveLength(cv, base, fontSize, rootFontSize, vw, vh)

  let bt = rv(style.borderTopWidth, w)
  let br = rv(style.borderRightWidth, w)
  let bb = rv(style.borderBottomWidth, w)
  let bl = rv(style.borderLeftWidth, w)
  let rtl = rv(style.borderTopLeftRadius, w)
  let rtr = rv(style.borderTopRightRadius, w)
  let rbr = rv(style.borderBottomRightRadius, w)
  let rbl = rv(style.borderBottomLeftRadius, w)

  proc drawSide(x1, y1, x2, y2: float32, width: float32, col: ColorRGBA,
                 bstyle: BorderStyleKind) =
    if width <= 0 or bstyle == bsNone or bstyle == bsHidden: return
    if col.a == 0: return
    ctx.strokeStyle = col.toPColor()
    ctx.lineWidth = width
    let p = newPath()
    p.moveTo(x1, y1)
    p.lineTo(x2, y2)
    case bstyle
    of bsDashed:
      ctx.setLineDash(@[width * 3, width * 2])
    of bsDotted:
      ctx.setLineDash(@[width, width])
    else:
      ctx.setLineDash(@[])
    ctx.stroke(p)
    ctx.setLineDash(@[])

  if rtl == 0 and rtr == 0 and rbr == 0 and rbl == 0:
    drawSide(x + bl/2, y + bt/2, x + w - br/2, y + bt/2, bt, style.borderTopColor, style.borderTopStyle)
    drawSide(x + w - br/2, y + bt/2, x + w - br/2, y + h - bb/2, br, style.borderRightColor, style.borderRightStyle)
    drawSide(x + bl/2, y + h - bb/2, x + w - br/2, y + h - bb/2, bb, style.borderBottomColor, style.borderBottomStyle)
    drawSide(x + bl/2, y + bt/2, x + bl/2, y + h - bb/2, bl, style.borderLeftColor, style.borderLeftStyle)
  else:
    if bt > 0 and style.borderTopStyle != bsNone and style.borderTopColor.a > 0:
      let path = roundedRectPath(x + bt/2, y + bt/2, w - bt, h - bt, rtl, rtr, rbr, rbl)
      ctx.strokeStyle = style.borderTopColor.toPColor()
      ctx.lineWidth = bt
      ctx.stroke(path)

proc drawBoxShadows*(ctx: Context, x, y, w, h: float32,
                      shadows: seq[BoxShadow], rtl, rtr, rbr, rbl: float32,
                      inset: bool = false) =
  for shadow in shadows:
    if shadow.inset != inset: continue
    if shadow.color.a == 0: continue
    if inset:
      let clipPath = roundedRectPath(x, y, w, h, rtl, rtr, rbr, rbl)
      ctx.save()
      ctx.clip(clipPath)
      let shadowPath = roundedRectPath(
        x + shadow.x - shadow.spread,
        y + shadow.y - shadow.spread,
        w + shadow.spread * 2,
        h + shadow.spread * 2,
        rtl, rtr, rbr, rbl
      )
      ctx.fillStyle = shadow.color.toPColor()
      ctx.fill(shadowPath)
      ctx.restore()
    else:
      let shadowPath = roundedRectPath(
        x + shadow.x - shadow.spread,
        y + shadow.y - shadow.spread,
        w + shadow.spread * 2,
        h + shadow.spread * 2,
        rtl, rtr, rbr, rbl
      )
      if shadow.blur > 0:
        let shadowImg = newImage(
          int(w + abs(shadow.x) * 2 + shadow.spread * 2 + shadow.blur * 4) + 4,
          int(h + abs(shadow.y) * 2 + shadow.spread * 2 + shadow.blur * 4) + 4
        )
        let shadowCtx = newContext(shadowImg)
        let offX = abs(shadow.x) + shadow.spread + shadow.blur * 2 + 2
        let offY = abs(shadow.y) + shadow.spread + shadow.blur * 2 + 2
        let sp2 = roundedRectPath(offX, offY,
          w + shadow.spread * 2, h + shadow.spread * 2,
          rtl, rtr, rbr, rbl)
        shadowCtx.fillStyle = shadow.color.toPColor()
        shadowCtx.fill(sp2)
        shadowImg.blur(shadow.blur)
        ctx.drawImage(shadowImg,
          x - offX + shadow.x - shadow.spread,
          y - offY + shadow.y - shadow.spread)
      else:
        ctx.fillStyle = shadow.color.toPColor()
        ctx.fill(shadowPath)

proc applyFilter*(img: Image, filters: seq[CssFilter]) =
  for f in filters:
    case f.kind
    of cfBlur:
      if f.value > 0: img.blur(f.value)
    of cfGrayscale:
      if f.value > 0:
        for i in 0..<img.width * img.height:
          let p = img.data[i]
          let gray = uint8((p.r.float32 * 0.299 + p.g.float32 * 0.587 + p.b.float32 * 0.114) * f.value +
                          (p.r.float32 * (1 - f.value)))
          let g2 = uint8(p.g.float32 * (1 - f.value) + p.g.float32 * 0.587 * f.value)
          let b2 = uint8(p.b.float32 * (1 - f.value) + p.b.float32 * 0.114 * f.value)
          img.data[i] = ColorRGBX(r: gray, g: gray, b: gray, a: p.a)
    of cfBrightness:
      for i in 0..<img.width * img.height:
        let p = img.data[i]
        img.data[i] = ColorRGBX(
          r: uint8(min(255.0, p.r.float32 * f.value)),
          g: uint8(min(255.0, p.g.float32 * f.value)),
          b: uint8(min(255.0, p.b.float32 * f.value)),
          a: p.a
        )
    of cfContrast:
      for i in 0..<img.width * img.height:
        let p = img.data[i]
        img.data[i] = ColorRGBX(
          r: uint8(max(0.0, min(255.0, (p.r.float32 - 128) * f.value + 128))),
          g: uint8(max(0.0, min(255.0, (p.g.float32 - 128) * f.value + 128))),
          b: uint8(max(0.0, min(255.0, (p.b.float32 - 128) * f.value + 128))),
          a: p.a
        )
    of cfInvert:
      for i in 0..<img.width * img.height:
        let p = img.data[i]
        let pf = f.value
        img.data[i] = ColorRGBX(
          r: uint8(p.r.float32 * (1 - pf) + (255 - p.r.float32) * pf),
          g: uint8(p.g.float32 * (1 - pf) + (255 - p.g.float32) * pf),
          b: uint8(p.b.float32 * (1 - pf) + (255 - p.b.float32) * pf),
          a: p.a
        )
    of cfOpacity:
      for i in 0..<img.width * img.height:
        let p = img.data[i]
        img.data[i] = ColorRGBX(r: p.r, g: p.g, b: p.b, a: uint8(p.a.float32 * f.value))
    else: discard

proc renderNode*(rs: RenderState, node: Node, offsetX, offsetY: float32)

proc renderBackground*(rs: RenderState, node: Node, x, y, w, h: float32) =
  let style = node.computedStyle
  if style == nil: return
  let fontSize = style.fontSize.value
  let rtl = resolveLength(style.borderTopLeftRadius, w, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
  let rtr = resolveLength(style.borderTopRightRadius, w, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
  let rbr = resolveLength(style.borderBottomRightRadius, w, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
  let rbl = resolveLength(style.borderBottomLeftRadius, w, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)

  drawBoxShadows(rs.ctx, x, y, w, h, style.boxShadow, rtl, rtr, rbr, rbl, false)

  if style.backgroundColor.a > 0 or style.backgroundImage.len > 0:
    let path = roundedRectPath(x, y, w, h, rtl, rtr, rbr, rbl)
    if style.backgroundImage.len > 0 and
       (style.backgroundImage.startsWith("linear-gradient") or
        style.backgroundImage.startsWith("radial-gradient")):
      let paint = makeGradientPaint(style.backgroundImage, x, y, w, h)
      rs.ctx.fillStyle = paint
      rs.ctx.fill(path)
      if style.backgroundColor.a > 0:
        rs.ctx.fillStyle = style.backgroundColor.toPColor()
    elif style.backgroundColor.a > 0:
      rs.ctx.fillStyle = style.backgroundColor.toPColor()
      rs.ctx.fill(path)
    else:
      rs.ctx.fillStyle = style.backgroundColor.toPColor()
      rs.ctx.fill(path)

  drawBoxShadows(rs.ctx, x, y, w, h, style.boxShadow, rtl, rtr, rbr, rbl, true)

proc measureText*(rs: RenderState, text: string, style: ComputedStyle): tuple[w, h: float32] =
  let fontSize = style.fontSize.value
  let font = rs.fontCache.getFont(style.fontFamily, fontSize * rs.scale,
                                   style.fontWeight, style.fontStyle)
  if font.typeface == nil:
    result.w = float32(text.len) * fontSize * 0.6
    result.h = fontSize * 1.2
    return
  let bounds = font.layoutBounds(text)
  result.w = bounds.x
  result.h = bounds.y

proc renderText*(rs: RenderState, text: string, x, y, maxWidth: float32,
                  style: ComputedStyle) =
  if text.strip().len == 0: return
  let fontSize = style.fontSize.value
  let font = rs.fontCache.getFont(style.fontFamily, fontSize * rs.scale,
                                   style.fontWeight, style.fontStyle)
  if font.typeface == nil:
    return
  var displayText = text
  case style.textTransform
  of ttUppercase: displayText = text.toUpperAscii()
  of ttLowercase: displayText = text.toLowerAscii()
  of ttCapitalize:
    var res = ""
    var cap = true
    for c in text:
      if c in {' ', '\t', '\n'}: cap = true; res.add(c)
      elif cap: res.add(c.toUpperAscii()); cap = false
      else: res.add(c)
    displayText = res
  else: discard

  let color = style.color.toPColor()
  if style.textShadow.len > 0:
    for shadow in style.textShadow:
      let sc = shadow.color.toPColor()
      if shadow.blur > 0:
        let tw = int(measureText(rs, displayText, style).w) + int(abs(shadow.x)) * 2 + int(shadow.blur) * 4 + 4
        let th = int(fontSize * 1.5) + int(abs(shadow.y)) * 2 + int(shadow.blur) * 4 + 4
        let shadowImg = newImage(max(tw, 1), max(th, 1))
        let shadowCtx = newContext(shadowImg)
        shadowCtx.font = font
        shadowCtx.fillStyle = sc
        shadowCtx.fillText(displayText,
          abs(shadow.x) + shadow.blur * 2,
          fontSize + abs(shadow.y) + shadow.blur * 2)
        shadowImg.blur(shadow.blur)
        rs.ctx.drawImage(shadowImg,
          x + shadow.x - abs(shadow.x) - shadow.blur * 2,
          y + shadow.y - abs(shadow.y) - shadow.blur * 2)
      else:
        rs.ctx.font = font
        rs.ctx.fillStyle = sc
        rs.ctx.fillText(displayText, x + shadow.x, y + shadow.y)

  rs.ctx.font = font
  rs.ctx.fillStyle = color

  let lineHeight = resolveLength(style.lineHeight,
    fontSize, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
  let effectiveLH = if style.lineHeight.kind == cvAuto: fontSize * 1.2 else: lineHeight

  if maxWidth > 0 and style.whiteSpace notin {wsPre, wsNowrap}:
    let words = displayText.split(' ')
    var line = ""
    var curY = y
    for word in words:
      let testLine = if line.len == 0: word else: line & " " & word
      let bounds = font.layoutBounds(testLine)
      if bounds.x > maxWidth and line.len > 0:
        case style.textAlign
        of taRight:
          let lb = font.layoutBounds(line)
          rs.ctx.fillText(line, x + maxWidth - lb.x, curY)
        of taCenter:
          let lb = font.layoutBounds(line)
          rs.ctx.fillText(line, x + (maxWidth - lb.x) / 2, curY)
        else:
          rs.ctx.fillText(line, x, curY)
        line = word
        curY += effectiveLH
      else:
        line = testLine
    if line.len > 0:
      case style.textAlign
      of taRight:
        let lb = font.layoutBounds(line)
        rs.ctx.fillText(line, x + maxWidth - lb.x, curY)
      of taCenter:
        let lb = font.layoutBounds(line)
        rs.ctx.fillText(line, x + (maxWidth - lb.x) / 2, curY)
      else:
        rs.ctx.fillText(line, x, curY)
  else:
    case style.textAlign
    of taRight:
      let lb = font.layoutBounds(displayText)
      rs.ctx.fillText(displayText, x + maxWidth - lb.x, y)
    of taCenter:
      let lb = font.layoutBounds(displayText)
      rs.ctx.fillText(displayText, x + (maxWidth - lb.x) / 2, y)
    else:
      rs.ctx.fillText(displayText, x, y)

  if style.textDecoration != tdNone:
    let bounds = font.layoutBounds(displayText)
    let tw = min(bounds.x, if maxWidth > 0: maxWidth else: bounds.x)
    let lineY = case style.textDecoration
      of tdUnderline: y + fontSize * 0.15
      of tdOverline: y - fontSize * 0.9
      of tdLineThrough: y - fontSize * 0.35
      else: y
    let p = newPath()
    p.moveTo(x, lineY)
    p.lineTo(x + tw, lineY)
    rs.ctx.strokeStyle = color
    rs.ctx.lineWidth = max(1, fontSize * 0.07)
    rs.ctx.stroke(p)

proc renderNode*(rs: RenderState, node: Node, offsetX, offsetY: float32) =
  if node.kind == nkDocument:
    for child in node.children:
      renderNode(rs, child, offsetX, offsetY)
    return
  if node.kind == nkText:
    if node.parent != nil and node.parent.computedStyle != nil:
      let style = node.parent.computedStyle
      if style.visibility == viHidden: return
      let box = node.parent.layoutBox
      if box == nil: return
      let x = offsetX + box.x + box.contentX
      let y = offsetY + box.y + box.contentY + style.fontSize.value
      let maxW = box.contentWidth
      renderText(rs, node.textContent, x, y, maxW, style)
    return
  if node.kind != nkElement: return
  let style = node.computedStyle
  if style == nil: return
  if style.display == dkNone: return
  if style.visibility == viCollapse: return
  let box = node.layoutBox
  if box == nil: return

  let ax = offsetX + box.x
  let ay = offsetY + box.y

  if style.opacity < 0.001:
    return

  var needsLayer = style.opacity < 1.0 or style.mixBlendMode != bmNormal or
                   style.filter.len > 0 or style.transform.len > 0

  var layerImg: Image
  var layerCtx: Context
  var savedCtx: Context

  if needsLayer:
    let lw = max(1, int(box.borderWidth + 2))
    let lh = max(1, int(box.borderHeight + 2))
    layerImg = newImage(lw, lh)
    layerCtx = newContext(layerImg)
    savedCtx = rs.ctx
    rs.ctx = layerCtx

  let bx = if needsLayer: 0.0f32 else: ax
  let by = if needsLayer: 0.0f32 else: ay

  renderBackground(rs, node, bx, by, box.borderWidth, box.borderHeight)

  let needsClip = style.overflowX == ovHidden or style.overflowY == ovHidden or
                   style.overflowX == ovClip or style.overflowY == ovClip
  if needsClip:
    let fontSize = style.fontSize.value
    let rtl = resolveLength(style.borderTopLeftRadius, box.borderWidth, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
    let rtr = resolveLength(style.borderTopRightRadius, box.borderWidth, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
    let rbr = resolveLength(style.borderBottomRightRadius, box.borderWidth, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
    let rbl = resolveLength(style.borderBottomLeftRadius, box.borderWidth, fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)
    let clipPath = roundedRectPath(bx + box.contentX - box.paddingLeft,
                                    by + box.contentY - box.paddingTop,
                                    box.clientWidth, box.clientHeight,
                                    rtl, rtr, rbr, rbl)
    rs.ctx.save()
    rs.ctx.clip(clipPath)

  for child in node.children:
    if child.computedStyle != nil and child.computedStyle.position in {pkAbsolute, pkFixed}:
      continue
    if child.kind == nkText:
      renderNode(rs, child, if needsLayer: -ax else: offsetX,
                             if needsLayer: -ay else: offsetY)
    else:
      renderNode(rs, child, if needsLayer: -ax + bx else: offsetX,
                             if needsLayer: -ay + by else: offsetY)

  for child in node.children:
    if child.computedStyle != nil and child.computedStyle.position in {pkAbsolute, pkFixed}:
      renderNode(rs, child, if needsLayer: -ax + bx else: offsetX,
                              if needsLayer: -ay + by else: offsetY)

  if needsClip:
    rs.ctx.restore()

  let fontSize = style.fontSize.value
  drawBorder(rs.ctx, bx, by, box.borderWidth, box.borderHeight, style,
             fontSize, rs.rootFontSize, rs.viewportWidth, rs.viewportHeight)

  if node.focused and rs.focusedNode == node:
    let outlineW = if style.outline.kind != cvAuto: style.outline.value else: 2.0f32
    if outlineW > 0:
      let outlineColor = if style.outlineColor.a > 0: style.outlineColor
                         else: rgba(0, 100, 200, 200)
      let op = newPath()
      op.rect(bx - outlineW, by - outlineW, box.borderWidth + outlineW * 2, box.borderHeight + outlineW * 2)
      rs.ctx.strokeStyle = outlineColor.toPColor()
      rs.ctx.lineWidth = outlineW
      rs.ctx.stroke(op)

  if needsLayer:
    rs.ctx = savedCtx
    if style.filter.len > 0:
      applyFilter(layerImg, style.filter)
    rs.ctx.save()
    rs.ctx.globalAlpha = style.opacity
    rs.ctx.drawImage(layerImg, ax, ay)
    rs.ctx.restore()

proc render*(rs: RenderState, root: Node) =
  rs.ctx.clearRect(0, 0, rs.viewportWidth, rs.viewportHeight)
  renderNode(rs, root, 0, 0)

proc getImage*(rs: RenderState): Image =
  rs.ctx.image

proc hitTest*(node: Node, x, y: float32): Node =
  if node.kind != nkElement: return nil
  let style = node.computedStyle
  if style == nil: return nil
  if style.display == dkNone: return nil
  if style.pointerEvents == peNone: return nil
  let box = node.layoutBox
  if box == nil: return nil
  let bx = box.x
  let by = box.y
  let bw = box.borderWidth
  let bh = box.borderHeight
  if x < bx or x > bx + bw or y < by or y > by + bh: return nil
  for i in countdown(node.children.len - 1, 0):
    let child = node.children[i]
    let hit = hitTest(child, x - bx + box.x, y - by + box.y)
    if hit != nil: return hit
  if x >= bx and x <= bx + bw and y >= by and y <= by + bh:
    return node
  nil

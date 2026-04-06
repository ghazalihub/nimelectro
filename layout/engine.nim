import std/[math, algorithm, sequtils, strutils, options]
import ../core/dom
import ../css/resolver

type
  LayoutContext* = ref object
    viewportWidth*: float32
    viewportHeight*: float32
    rootFontSize*: float32
    containingBlocks*: seq[tuple[w, h: float32]]
    floats*: seq[tuple[node: Node, x, y, w, h: float32, side: FloatKind]]

proc newLayoutContext*(vw, vh: float32): LayoutContext =
  LayoutContext(
    viewportWidth: vw,
    viewportHeight: vh,
    rootFontSize: 16.0,
    containingBlocks: @[(vw, vh)]
  )

proc resolveLength*(cv: CssValue, base: float32, fontSize: float32,
                    rootFontSize: float32, vw: float32, vh: float32): float32 =
  case cv.kind
  of cvLength: cv.value
  of cvPercent: base * cv.value / 100.0
  of cvEm: fontSize * cv.value
  of cvRem: rootFontSize * cv.value
  of cvVw: vw * cv.value / 100.0
  of cvVh: vh * cv.value / 100.0
  of cvVmin: min(vw, vh) * cv.value / 100.0
  of cvVmax: max(vw, vh) * cv.value / 100.0
  of cvCh: fontSize * 0.5 * cv.value
  of cvEx: fontSize * 0.5 * cv.value
  of cvFr: cv.value
  else: 0.0

proc effectiveFontSize*(style: ComputedStyle, parentFontSize: float32,
                         rootFontSize: float32): float32 =
  case style.fontSize.kind
  of cvLength: style.fontSize.value
  of cvEm: parentFontSize * style.fontSize.value
  of cvRem: rootFontSize * style.fontSize.value
  of cvPercent: parentFontSize * style.fontSize.value / 100.0
  else: parentFontSize

proc effectiveLineHeight*(style: ComputedStyle, fontSize: float32): float32 =
  case style.lineHeight.kind
  of cvAuto: fontSize * 1.2
  of cvLength: style.lineHeight.value
  of cvPercent: fontSize * style.lineHeight.value / 100.0
  of cvEm: fontSize * style.lineHeight.value
  else: fontSize * 1.2

proc layoutNode*(ctx: LayoutContext, node: Node, containingWidth: float32,
                 containingHeight: float32, parentFontSize: float32): LayoutBox

proc layoutBlock*(ctx: LayoutContext, node: Node, containingWidth: float32,
                   containingHeight: float32, parentFontSize: float32): LayoutBox =
  let style = node.computedStyle
  let fontSize = effectiveFontSize(style, parentFontSize, ctx.rootFontSize)
  let lineHeight = effectiveLineHeight(style, fontSize)

  proc rv(cv: CssValue, base: float32): float32 =
    resolveLength(cv, base, fontSize, ctx.rootFontSize, ctx.viewportWidth, ctx.viewportHeight)

  let marginLeft = rv(style.marginLeft, containingWidth)
  let marginRight = rv(style.marginRight, containingWidth)
  let marginTop = rv(style.marginTop, containingWidth)
  let marginBottom = rv(style.marginBottom, containingWidth)
  let paddingLeft = rv(style.paddingLeft, containingWidth)
  let paddingRight = rv(style.paddingRight, containingWidth)
  let paddingTop = rv(style.paddingTop, containingWidth)
  let paddingBottom = rv(style.paddingBottom, containingWidth)
  let borderLeft = rv(style.borderLeftWidth, containingWidth)
  let borderRight = rv(style.borderRightWidth, containingWidth)
  let borderTop = rv(style.borderTopWidth, containingWidth)
  let borderBottom = rv(style.borderBottomWidth, containingWidth)

  var contentWidth: float32
  if style.width.kind == cvAuto:
    contentWidth = containingWidth - marginLeft - marginRight - paddingLeft - paddingRight - borderLeft - borderRight
  else:
    contentWidth = rv(style.width, containingWidth)

  if style.minWidth.kind != cvAuto:
    contentWidth = max(contentWidth, rv(style.minWidth, containingWidth))
  if style.maxWidth.kind != cvNone and style.maxWidth.kind != cvAuto:
    contentWidth = min(contentWidth, rv(style.maxWidth, containingWidth))
  contentWidth = max(contentWidth, 0)

  var box = LayoutBox(
    marginLeft: marginLeft,
    marginTop: marginTop,
    marginRight: marginRight,
    marginBottom: marginBottom,
    paddingLeft: paddingLeft,
    paddingTop: paddingTop,
    paddingRight: paddingRight,
    paddingBottom: paddingBottom
  )

  var contentHeight: float32 = 0
  var childY: float32 = paddingTop

  for child in node.children:
    if child.kind == nkText:
      let text = child.textContent
      if text.strip().len == 0: continue
      let textH = lineHeight * ceil(float32(text.len) * fontSize * 0.6 / max(contentWidth, 1))
      childY += max(textH, lineHeight)
      continue
    if child.computedStyle == nil: continue
    let childStyle = child.computedStyle
    if childStyle.display == dkNone: continue
    if childStyle.position in {pkAbsolute, pkFixed}: continue

    let childBox = layoutNode(ctx, child, contentWidth, containingHeight, fontSize)
    child.layoutBox = childBox

    let childMarginTop = childBox.marginTop
    let childMarginBottom = childBox.marginBottom

    if childStyle.display == dkBlock or childStyle.display == dkFlex or
       childStyle.display == dkGrid or childStyle.display == dkTable or
       childStyle.display == dkListItem:
      var effectiveMarginTop = childMarginTop
      if childY == paddingTop and contentHeight == 0:
        effectiveMarginTop = 0
      childBox.y = childY + effectiveMarginTop
      childBox.x = paddingLeft + childBox.marginLeft
      childY = childBox.y + childBox.height + childMarginBottom
    else:
      childBox.y = childY
      childBox.x = paddingLeft
      childY += childBox.height + childMarginTop + childMarginBottom

  contentHeight = childY + paddingBottom

  if style.height.kind != cvAuto:
    contentHeight = rv(style.height, containingHeight)

  if style.minHeight.kind != cvAuto:
    contentHeight = max(contentHeight, rv(style.minHeight, containingHeight))
  if style.maxHeight.kind != cvNone and style.maxHeight.kind != cvAuto:
    contentHeight = min(contentHeight, rv(style.maxHeight, containingHeight))

  box.contentWidth = contentWidth
  box.contentHeight = contentHeight
  box.width = contentWidth + paddingLeft + paddingRight + borderLeft + borderRight
  box.height = contentHeight + paddingTop + paddingBottom + borderTop + borderBottom
  box.contentX = borderLeft + paddingLeft
  box.contentY = borderTop + paddingTop
  box.borderX = 0
  box.borderY = 0
  box.borderWidth = box.width
  box.borderHeight = box.height
  box.clientWidth = contentWidth + paddingLeft + paddingRight
  box.clientHeight = contentHeight + paddingTop + paddingBottom

  for child in node.children:
    if child.computedStyle == nil: continue
    if child.computedStyle.position == pkAbsolute:
      let childBox = layoutNode(ctx, child, contentWidth, contentHeight, fontSize)
      child.layoutBox = childBox
      let left = rv(child.computedStyle.left, contentWidth)
      let top = rv(child.computedStyle.top, contentHeight)
      childBox.x = if child.computedStyle.left.kind != cvAuto: left + paddingLeft
                   else: paddingLeft
      childBox.y = if child.computedStyle.top.kind != cvAuto: top + paddingTop
                   else: paddingTop
  box

type FlexItem = object
  node: Node
  box: LayoutBox
  mainSize, crossSize: float32
  mainStart, crossStart: float32
  flexGrow, flexShrink: float32
  flexBasis: float32
  order: int32
  frozen: bool
  hypotheticalMainSize: float32
  baseSize: float32
  scaledShrinkFactor: float32

proc layoutFlex*(ctx: LayoutContext, node: Node, containingWidth: float32,
                  containingHeight: float32, parentFontSize: float32): LayoutBox =
  let style = node.computedStyle
  let fontSize = effectiveFontSize(style, parentFontSize, ctx.rootFontSize)

  proc rv(cv: CssValue, base: float32): float32 =
    resolveLength(cv, base, fontSize, ctx.rootFontSize, ctx.viewportWidth, ctx.viewportHeight)

  let paddingLeft = rv(style.paddingLeft, containingWidth)
  let paddingRight = rv(style.paddingRight, containingWidth)
  let paddingTop = rv(style.paddingTop, containingWidth)
  let paddingBottom = rv(style.paddingBottom, containingWidth)
  let borderLeft = rv(style.borderLeftWidth, containingWidth)
  let borderRight = rv(style.borderRightWidth, containingWidth)
  let borderTop = rv(style.borderTopWidth, containingWidth)
  let borderBottom = rv(style.borderBottomWidth, containingWidth)
  let marginLeft = rv(style.marginLeft, containingWidth)
  let marginRight = rv(style.marginRight, containingWidth)
  let marginTop = rv(style.marginTop, containingWidth)
  let marginBottom = rv(style.marginBottom, containingWidth)

  var containerWidth = if style.width.kind != cvAuto:
    rv(style.width, containingWidth)
  else:
    containingWidth - marginLeft - marginRight - paddingLeft - paddingRight - borderLeft - borderRight
  containerWidth = max(containerWidth, 0)

  var containerHeight = if style.height.kind != cvAuto:
    rv(style.height, containingHeight)
  else:
    0.0

  let isRow = style.flexDirection in {fdRow, fdRowReverse}
  let isReverse = style.flexDirection in {fdRowReverse, fdColumnReverse}
  let isWrap = style.flexWrap in {fwWrap, fwWrapReverse}
  let mainContainerSize = if isRow: containerWidth else: containerHeight
  let crossContainerSize = if isRow: containerHeight else: containerWidth
  let gap = rv(style.columnGap, containerWidth)
  let rowGap = rv(style.rowGap, containerWidth)

  var items: seq[FlexItem]
  for child in node.children:
    if child.computedStyle == nil: continue
    if child.computedStyle.display == dkNone: continue
    if child.computedStyle.position in {pkAbsolute, pkFixed}: continue
    let cs = child.computedStyle
    let childFontSize = effectiveFontSize(cs, fontSize, ctx.rootFontSize)
    var item = FlexItem(
      node: child,
      flexGrow: cs.flexGrow,
      flexShrink: cs.flexShrink,
      order: cs.order
    )
    item.flexBasis = case cs.flexBasis.kind
      of cvAuto:
        if isRow:
          if cs.width.kind != cvAuto: rv(cs.width, containerWidth)
          else: -1.0
        else:
          if cs.height.kind != cvAuto: rv(cs.height, containerHeight)
          else: -1.0
      of cvLength: cs.flexBasis.value
      of cvPercent:
        if mainContainerSize > 0: mainContainerSize * cs.flexBasis.value / 100.0
        else: -1.0
      else: -1.0
    let tempBox = layoutNode(ctx, child,
      if isRow: (if item.flexBasis >= 0: item.flexBasis else: containerWidth)
      else: containerWidth,
      if isRow: (if containerHeight > 0: containerHeight else: 999999)
      else: (if item.flexBasis >= 0: item.flexBasis else: 999999),
      fontSize)
    child.layoutBox = tempBox
    if item.flexBasis < 0:
      item.flexBasis = if isRow: tempBox.width else: tempBox.height
    item.box = tempBox
    item.hypotheticalMainSize = item.flexBasis
    if isRow:
      item.crossSize = tempBox.height
    else:
      item.crossSize = tempBox.width
    items.add(item)
  items.sort(proc(a, b: FlexItem): int = cmp(a.order, b.order))
  if isReverse: items.reverse()

  type FlexLine = object
    items: seq[int]
    mainSize: float32
    crossSize: float32
    mainStart: float32
    crossStart: float32

  var lines: seq[FlexLine]
  if not isWrap:
    var line = FlexLine()
    for i in 0..<items.len: line.items.add(i)
    for i in line.items:
      line.mainSize += items[i].hypotheticalMainSize
    if line.items.len > 1:
      line.mainSize += gap * float32(line.items.len - 1)
    lines.add(line)
  else:
    var currentLine = FlexLine()
    var currentMainSize: float32 = 0
    for i in 0..<items.len:
      let itemMain = items[i].hypotheticalMainSize
      let addGap = if currentLine.items.len > 0: gap else: 0
      if mainContainerSize > 0 and currentLine.items.len > 0 and
         currentMainSize + addGap + itemMain > mainContainerSize:
        currentLine.mainSize = currentMainSize
        lines.add(currentLine)
        currentLine = FlexLine()
        currentMainSize = 0
      currentLine.items.add(i)
      currentMainSize += addGap + itemMain
    if currentLine.items.len > 0:
      currentLine.mainSize = currentMainSize
      lines.add(currentLine)

  for lineIdx in 0..<lines.len:
    let line = addr lines[lineIdx]
    let lineGap = if line[].items.len > 1: gap * float32(line[].items.len - 1) else: 0
    let freeSpace = mainContainerSize - line[].mainSize
    var totalGrow: float32 = 0
    var totalShrink: float32 = 0
    for i in line[].items:
      totalGrow += items[i].flexGrow
      totalShrink += items[i].flexShrink * items[i].hypotheticalMainSize
    for i in line[].items:
      if freeSpace > 0 and totalGrow > 0:
        items[i].mainSize = items[i].hypotheticalMainSize +
          freeSpace * (items[i].flexGrow / totalGrow)
      elif freeSpace < 0 and totalShrink > 0:
        items[i].mainSize = items[i].hypotheticalMainSize +
          freeSpace * (items[i].flexShrink * items[i].hypotheticalMainSize / totalShrink)
      else:
        items[i].mainSize = items[i].hypotheticalMainSize
      items[i].mainSize = max(items[i].mainSize, 0)
      let tempCW = if isRow: items[i].mainSize else: containerWidth
      let tempCH = if isRow: (if containerHeight > 0: containerHeight else: 999999)
                   else: items[i].mainSize
      let newBox = layoutNode(ctx, items[i].node, tempCW, tempCH, fontSize)
      items[i].node.layoutBox = newBox
      items[i].box = newBox
      items[i].crossSize = if isRow: newBox.height else: newBox.width
    line[].crossSize = 0
    for i in line[].items:
      line[].crossSize = max(line[].crossSize, items[i].crossSize)

  var totalCrossSize: float32 = 0
  for line in lines: totalCrossSize += line.crossSize
  if lines.len > 1: totalCrossSize += rowGap * float32(lines.len - 1)

  if containerHeight == 0: containerHeight = totalCrossSize + paddingTop + paddingBottom

  var crossOffset: float32 = if isRow: paddingTop else: paddingLeft
  for lineIdx in 0..<lines.len:
    let line = addr lines[lineIdx]
    var mainOffset: float32 = if isRow: paddingLeft else: paddingTop
    let lineGap = if line[].items.len > 1: gap * float32(line[].items.len - 1) else: 0
    let usedMain = block:
      var s: float32 = 0
      for i in line[].items: s += items[i].mainSize
      s + lineGap
    let freeMain = (if isRow: containerWidth else: containerHeight) - usedMain -
                   (if isRow: paddingLeft + paddingRight else: paddingTop + paddingBottom)
    case style.justifyContent
    of jcFlexEnd, jcEnd: mainOffset += freeMain
    of jcCenter: mainOffset += freeMain / 2
    of jcSpaceBetween:
      if line[].items.len > 1:
        let extraGap = freeMain / float32(line[].items.len - 1)
        for ki in 0..<line[].items.len:
          let i = line[].items[ki]
          items[i].mainStart = mainOffset
          mainOffset += items[i].mainSize + gap + (if ki < line[].items.len - 1: extraGap else: 0)
        line[].mainStart = crossOffset
        crossOffset += line[].crossSize + rowGap
        continue
    of jcSpaceAround:
      let perItem = freeMain / float32(line[].items.len)
      mainOffset += perItem / 2
    of jcSpaceEvenly:
      let slots = float32(line[].items.len + 1)
      mainOffset += freeMain / slots
    else: discard

    for ki in 0..<line[].items.len:
      let i = line[].items[ki]
      items[i].mainStart = mainOffset
      let alignSelf = items[i].node.computedStyle.alignSelf
      let effectiveAlign = if alignSelf != asAuto: alignSelf
                           else:
                             case style.alignItems
                             of aiFlexStart, aiStart: asFlexStart
                             of aiFlexEnd, aiEnd: asFlexEnd
                             of aiCenter: asCenter
                             of aiBaseline: asBaseline
                             else: asStretch
      let crossFree = line[].crossSize - items[i].crossSize
      items[i].crossStart = crossOffset + case effectiveAlign
        of asFlexEnd, asEnd: crossFree
        of asCenter: crossFree / 2
        else: 0
      mainOffset += items[i].mainSize
      if ki < line[].items.len - 1: mainOffset += gap
      case style.justifyContent
      of jcSpaceAround:
        let perItem = freeMain / float32(line[].items.len)
        mainOffset += perItem
      of jcSpaceEvenly:
        let slots = float32(line[].items.len + 1)
        mainOffset += freeMain / slots
      else: discard
    line[].mainStart = crossOffset
    crossOffset += line[].crossSize + rowGap

  var containerH = containerHeight
  if style.height.kind != cvAuto:
    containerH = rv(style.height, containingHeight)

  for item in items:
    let b = item.box
    if isRow:
      b.x = item.mainStart
      b.y = item.crossStart
    else:
      b.x = item.crossStart
      b.y = item.mainStart

  var box = LayoutBox(
    marginLeft: marginLeft, marginTop: marginTop,
    marginRight: marginRight, marginBottom: marginBottom,
    paddingLeft: paddingLeft, paddingTop: paddingTop,
    paddingRight: paddingRight, paddingBottom: paddingBottom
  )

  let finalH = if style.height.kind != cvAuto: rv(style.height, containingHeight)
               else: totalCrossSize + paddingTop + paddingBottom

  box.contentWidth = containerWidth
  box.contentHeight = finalH - paddingTop - paddingBottom
  box.width = containerWidth + paddingLeft + paddingRight + borderLeft + borderRight
  box.height = finalH + borderTop + borderBottom
  box.contentX = borderLeft + paddingLeft
  box.contentY = borderTop + paddingTop
  box.borderWidth = box.width
  box.borderHeight = box.height
  box.clientWidth = containerWidth + paddingLeft + paddingRight
  box.clientHeight = box.contentHeight + paddingTop + paddingBottom
  box

proc layoutInline*(ctx: LayoutContext, node: Node, containingWidth: float32,
                    containingHeight: float32, parentFontSize: float32): LayoutBox =
  let style = node.computedStyle
  let fontSize = effectiveFontSize(style, parentFontSize, ctx.rootFontSize)

  proc rv(cv: CssValue, base: float32): float32 =
    resolveLength(cv, base, fontSize, ctx.rootFontSize, ctx.viewportWidth, ctx.viewportHeight)

  let paddingLeft = rv(style.paddingLeft, containingWidth)
  let paddingRight = rv(style.paddingRight, containingWidth)
  let paddingTop = rv(style.paddingTop, containingWidth)
  let paddingBottom = rv(style.paddingBottom, containingWidth)
  let borderLeft = rv(style.borderLeftWidth, containingWidth)
  let borderRight = rv(style.borderRightWidth, containingWidth)
  let marginLeft = rv(style.marginLeft, containingWidth)
  let marginRight = rv(style.marginRight, containingWidth)
  let marginTop = rv(style.marginTop, containingWidth)
  let marginBottom = rv(style.marginBottom, containingWidth)

  let lineHeight = effectiveLineHeight(style, fontSize)
  var textWidth: float32 = 0
  for child in node.children:
    if child.kind == nkText:
      textWidth += float32(child.textContent.len) * fontSize * 0.6

  var box = LayoutBox(
    marginLeft: marginLeft, marginTop: marginTop,
    marginRight: marginRight, marginBottom: marginBottom,
    paddingLeft: paddingLeft, paddingTop: paddingTop,
    paddingRight: paddingRight, paddingBottom: paddingBottom
  )
  let w = textWidth + paddingLeft + paddingRight + borderLeft + borderRight
  box.width = min(w, containingWidth)
  box.height = lineHeight + paddingTop + paddingBottom
  box.contentWidth = textWidth
  box.contentHeight = lineHeight
  box.contentX = borderLeft + paddingLeft
  box.contentY = paddingTop
  box

proc layoutNode*(ctx: LayoutContext, node: Node, containingWidth: float32,
                  containingHeight: float32, parentFontSize: float32): LayoutBox =
  if node.computedStyle == nil:
    return LayoutBox(width: 0, height: 0)
  let style = node.computedStyle
  case style.display
  of dkNone:
    return LayoutBox(width: 0, height: 0)
  of dkFlex, dkInlineFlex:
    return layoutFlex(ctx, node, containingWidth, containingHeight, parentFontSize)
  of dkInline:
    return layoutInline(ctx, node, containingWidth, containingHeight, parentFontSize)
  of dkInlineBlock:
    return layoutBlock(ctx, node, containingWidth, containingHeight, parentFontSize)
  else:
    return layoutBlock(ctx, node, containingWidth, containingHeight, parentFontSize)

proc layout*(ctx: LayoutContext, root: Node) =
  let box = layoutNode(ctx, root, ctx.viewportWidth, ctx.viewportHeight, ctx.rootFontSize)
  root.layoutBox = box
  box.x = 0
  box.y = 0

import std/[tables, math, times, strutils, sequtils]
import ../core/dom
import ../css/resolver

type
  EasingFn* = proc(t: float32): float32

  AnimationState* = ref object
    node*: Node
    property*: string
    fromValue*: string
    toValue*: string
    duration*: float32
    delay*: float32
    easing*: EasingFn
    startTime*: float64
    active*: bool
    fillMode*: AnimationFillModeKind
    iterationCount*: float32
    direction*: AnimationDirectionKind
    currentIteration*: float32

  KeyframeAnimation* = ref object
    node*: Node
    name*: string
    keyframes*: seq[tuple[offset: float32, props: Table[string, string]]]
    duration*: float32
    delay*: float32
    easing*: EasingFn
    startTime*: float64
    iterationCount*: float32
    direction*: AnimationDirectionKind
    fillMode*: AnimationFillModeKind
    active*: bool

  AnimationEngine* = ref object
    transitions*: seq[AnimationState]
    animations*: seq[KeyframeAnimation]
    keyframeRegistry*: Table[string, seq[tuple[offset: float32, props: Table[string, string]]]]
    dirty*: bool

proc ease*(t: float32): float32 =
  let t2 = t * t
  let t3 = t2 * t
  6*t3*t*t - 15*t2*t2 + 10*t3

proc easeIn*(t: float32): float32 = t * t * t

proc easeOut*(t: float32): float32 =
  let f = 1.0f - t
  1.0f - f * f * f

proc easeInOut*(t: float32): float32 =
  if t < 0.5f: 4 * t * t * t
  else:
    let f = (2*t - 2)
    0.5f * f * f * f + 1

proc linear*(t: float32): float32 = t

proc cubicBezier*(x1, y1, x2, y2: float32): EasingFn =
  proc solve(t: float32): float32 =
    var lo = 0.0f32
    var hi = 1.0f32
    var x = t
    for _ in 0..<8:
      let sx = 3*(1-x)*(1-x)*x*x1 + 3*(1-x)*x*x*x2 + x*x*x - t
      if abs(sx) < 0.0001f: break
      if sx > 0: hi = x else: lo = x
      x = (lo + hi) / 2
    let u = x
    3*(1-u)*(1-u)*u*y1 + 3*(1-u)*u*u*y2 + u*u*u
  solve

proc getEasing*(kind: EasingKind): EasingFn =
  case kind
  of ekLinear: linear
  of ekEase: ease
  of ekEaseIn: easeIn
  of ekEaseOut: easeOut
  of ekEaseInOut: easeInOut
  else: ease

proc newAnimationEngine*(): AnimationEngine =
  AnimationEngine(
    transitions: @[],
    animations: @[],
    keyframeRegistry: initTable[string, seq[tuple[offset: float32, props: Table[string, string]]]](),
    dirty: false
  )

proc registerKeyframes*(eng: AnimationEngine, name: string,
                         frames: seq[tuple[offset: float32, props: Table[string, string]]]) =
  eng.keyframeRegistry[name] = frames

proc interpolateNum*(a, b, t: float32): float32 =
  a + (b - a) * t

proc extractNum*(s: string): float32 =
  let stripped = s.strip().replace("px","").replace("em","").replace("%","").replace("deg","")
  try: parseFloat(stripped).float32 except: 0.0

proc extractUnit*(s: string): string =
  let v = s.strip()
  if v.endsWith("px"): "px"
  elif v.endsWith("em"): "em"
  elif v.endsWith("%"): "%"
  elif v.endsWith("deg"): "deg"
  elif v.endsWith("rem"): "rem"
  elif v.endsWith("turn"): "turn"
  else: ""

proc interpolateColor*(a, b: string, t: float32): string =
  proc parseRgba(s: string): tuple[r,g,b,a: float32] =
    let v = s.strip().toLowerAscii()
    if v.startsWith("rgb"):
      let inner = v[v.find('(')+1..^2]
      let parts = inner.split(',')
      if parts.len >= 3:
        let r = (try: parseFloat(parts[0].strip()).float32 except: 0.0f32)
        let g = (try: parseFloat(parts[1].strip()).float32 except: 0.0f32)
        let b = (try: parseFloat(parts[2].strip()).float32 except: 0.0f32)
        let a = (if parts.len >= 4: (try: parseFloat(parts[3].strip()).float32 * 255 except: 255.0f32) else: 255.0f32)
        return (r, g, b, a)
    elif v.startsWith("#"):
      let c = parseColor(v)
      return (c.r.float32, c.g.float32, c.b.float32, c.a.float32)
    (0f32, 0f32, 0f32, 255f32)
  let ca = parseRgba(a)
  let cb = parseRgba(b)
  let r = interpolateNum(ca.r, cb.r, t)
  let g = interpolateNum(ca.g, cb.g, t)
  let bl = interpolateNum(ca.b, cb.b, t)
  let al = interpolateNum(ca.a, cb.a, t)
  if al < 255:
    "rgba(" & $int(r) & "," & $int(g) & "," & $int(bl) & "," & $(al/255) & ")"
  else:
    "rgb(" & $int(r) & "," & $int(g) & "," & $int(bl) & ")"

proc interpolateTransform*(a, b: string, t: float32): string =
  if a == "none" or a == "": return b
  if b == "none" or b == "": return a
  "matrix(1,0,0,1,0,0)"

proc interpolateValue*(prop, a, b: string, t: float32): string =
  let lp = prop.toLowerAscii()
  if lp in ["color","background-color","border-color","border-top-color",
             "border-right-color","border-bottom-color","border-left-color",
             "outline-color","text-decoration-color","fill","stroke"]:
    return interpolateColor(a, b, t)
  if lp == "transform":
    return interpolateTransform(a, b, t)
  if lp == "opacity":
    let na = try: parseFloat(a).float32 except: 0
    let nb = try: parseFloat(b).float32 except: 1
    return $(interpolateNum(na, nb, t))
  if lp in ["z-index","order","flex-grow","flex-shrink"]:
    let na = try: parseFloat(a).float32 except: 0
    let nb = try: parseFloat(b).float32 except: 0
    return $int(interpolateNum(na, nb, t))
  let unit = if a.len > 0: extractUnit(a) else: extractUnit(b)
  let na = extractNum(a)
  let nb = extractNum(b)
  if unit.len > 0:
    $interpolateNum(na, nb, t) & unit
  else:
    $interpolateNum(na, nb, t)

proc startTransition*(eng: AnimationEngine, node: Node, prop: string,
                       fromVal, toVal: string, transition: Transition) =
  for i in 0..<eng.transitions.len:
    if eng.transitions[i].node.nodeId == node.nodeId and eng.transitions[i].property == prop:
      eng.transitions[i].active = false
  let now = epochTime()
  eng.transitions.add(AnimationState(
    node: node,
    property: prop,
    fromValue: fromVal,
    toValue: toVal,
    duration: transition.duration,
    delay: transition.delay,
    easing: getEasing(transition.timingFunction),
    startTime: now + transition.delay.float64,
    active: true,
    fillMode: afBoth,
    iterationCount: 1,
    currentIteration: 0
  ))
  eng.dirty = true

proc startAnimation*(eng: AnimationEngine, node: Node, anim: Animation) =
  if anim.name notin eng.keyframeRegistry: return
  let frames = eng.keyframeRegistry[anim.name]
  let now = epochTime()
  eng.animations.add(KeyframeAnimation(
    node: node,
    name: anim.name,
    keyframes: frames,
    duration: anim.duration,
    delay: anim.delay,
    easing: getEasing(anim.timingFunction),
    startTime: now + anim.delay.float64,
    iterationCount: anim.iterationCount,
    direction: anim.direction,
    fillMode: anim.fillMode,
    active: anim.playState == apRunning
  ))
  eng.dirty = true

proc tick*(eng: AnimationEngine): bool =
  let now = epochTime()
  var anyActive = false
  var completed: seq[int]

  for i in 0..<eng.transitions.len:
    let anim = eng.transitions[i]
    if not anim.active or anim.node == nil: continue
    if now < anim.startTime.float64: anyActive = true; continue
    let elapsed = float32(now - anim.startTime)
    let rawT = if anim.duration <= 0: 1.0f32 else: clamp(elapsed / anim.duration, 0, 1)
    let t = anim.easing(rawT)
    let val = interpolateValue(anim.property, anim.fromValue, anim.toValue, t)
    anim.node.inlineStyle[anim.property] = val
    anim.node.paintDirty = true
    if rawT >= 1.0:
      if anim.fillMode in {afBoth, afForwards}:
        anim.node.inlineStyle[anim.property] = anim.toValue
      else:
        anim.node.inlineStyle.del(anim.property)
      anim.active = false
      completed.add(i)
    else:
      anyActive = true

  for i in countdown(completed.len-1, 0):
    eng.transitions.del(completed[i])

  var animCompleted: seq[int]
  for i in 0..<eng.animations.len:
    let anim = eng.animations[i]
    if not anim.active or anim.node == nil: continue
    if now < anim.startTime.float64: anyActive = true; continue
    let elapsed = float32(now - anim.startTime)
    let totalDuration = anim.duration * (if anim.iterationCount <= 0: 1.0f32 else: anim.iterationCount)
    let rawProgress = if totalDuration <= 0: 1.0f32
                       else: clamp(elapsed / totalDuration, 0, 1)
    let iterProgress = if anim.duration <= 0: 1.0f32
                        else: (elapsed mod anim.duration) / anim.duration
    let dirProgress = (case anim.direction
      of adReverse: 1.0f32 - iterProgress
      of adAlternate: (if int(elapsed / anim.duration) mod 2 == 0: iterProgress else: 1 - iterProgress)
      of adAlternateReverse: (if int(elapsed / anim.duration) mod 2 == 0: 1 - iterProgress else: iterProgress)
      else: iterProgress)
    let t = anim.easing(dirProgress)

    var loIdx = 0
    var hiIdx = anim.keyframes.len - 1
    for j in 0..<anim.keyframes.len - 1:
      if anim.keyframes[j].offset <= t and anim.keyframes[j+1].offset >= t:
        loIdx = j
        hiIdx = j + 1
        break
    if anim.keyframes.len >= 2:
      let loFrame = anim.keyframes[loIdx]
      let hiFrame = anim.keyframes[hiIdx]
      let span = hiFrame.offset - loFrame.offset
      let localT = if span <= 0: 0.0f32 else: (t - loFrame.offset) / span
      for prop in loFrame.props.keys:
        if prop in hiFrame.props:
          let fromV = loFrame.props[prop]
          let toV   = hiFrame.props[prop]
          anim.node.inlineStyle[prop] = interpolateValue(prop, fromV, toV, localT)
      anim.node.paintDirty = true

    if rawProgress >= 1.0:
      if anim.fillMode in {afBoth, afForwards} and anim.keyframes.len > 0:
        for prop, val in anim.keyframes[^1].props:
          anim.node.inlineStyle[prop] = val
      elif anim.fillMode notin {afBoth, afForwards}:
        for prop in anim.keyframes[0].props.keys:
          anim.node.inlineStyle.del(prop)
      anim.active = false
      animCompleted.add(i)
    else:
      anyActive = true

  for i in countdown(animCompleted.len-1, 0):
    eng.animations.del(animCompleted[i])

  eng.dirty = anyActive
  anyActive

proc applyAnimations*(eng: AnimationEngine, node: Node) =
  if node.computedStyle == nil: return
  let style = node.computedStyle
  for anim in style.animation:
    eng.startAnimation(node, anim)
  for tr in style.transition:
    if tr.property != "none" and tr.duration > 0:
      discard

proc cancelNodeAnimations*(eng: AnimationEngine, nodeId: uint32) =
  for a in eng.transitions.mitems:
    if a.node != nil and a.node.nodeId == nodeId:
      a.active = false
  for a in eng.animations.mitems:
    if a.node != nil and a.node.nodeId == nodeId:
      a.active = false

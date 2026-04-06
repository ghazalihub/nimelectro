import std/[strutils, tables, sequtils]
import ../core/dom

type
  HtmlParser* = ref object
    source*: string
    pos*: int
    document*: Node

proc newHtmlParser*(html: string): HtmlParser =
  HtmlParser(source: html, pos: 0, document: newDocument())

proc peek(p: HtmlParser): char =
  if p.pos < p.source.len: p.source[p.pos] else: '\0'

proc peekN(p: HtmlParser, n: int): string =
  if p.pos + n <= p.source.len: p.source[p.pos..<p.pos+n] else: ""

proc advance(p: HtmlParser): char =
  result = p.source[p.pos]
  inc p.pos

proc skip(p: HtmlParser) =
  while p.pos < p.source.len and p.source[p.pos] in {' ', '\t', '\n', '\r', '\f'}:
    inc p.pos

proc readUntil(p: HtmlParser, stop: set[char]): string =
  while p.pos < p.source.len and p.source[p.pos] notin stop:
    result.add(p.advance())

proc readTagName(p: HtmlParser): string =
  while p.pos < p.source.len and p.source[p.pos] notin
      {' ', '\t', '\n', '\r', '>', '/', '\0'}:
    result.add(p.advance())
  result = result.toLowerAscii()

proc readAttrName(p: HtmlParser): string =
  while p.pos < p.source.len and p.source[p.pos] notin
      {' ', '\t', '\n', '\r', '>', '/', '=', '\0'}:
    result.add(p.advance())
  result = result.toLowerAscii()

proc readAttrValue(p: HtmlParser): string =
  p.skip()
  if p.peek() != '=': return ""
  discard p.advance()
  p.skip()
  if p.peek() in {'"', '\''}:
    let q = p.advance()
    while p.pos < p.source.len and p.source[p.pos] != q:
      if p.source[p.pos] == '&':
        inc p.pos
        var entity = ""
        while p.pos < p.source.len and p.source[p.pos] notin {';', ' '}:
          entity.add(p.advance())
        if p.peek() == ';': discard p.advance()
        case entity
        of "amp": result.add('&')
        of "lt": result.add('<')
        of "gt": result.add('>')
        of "quot": result.add('"')
        of "apos": result.add('\'')
        of "nbsp": result.add('\xc2'); result.add('\xa0')
        else: result.add('&'); result.add(entity); result.add(';')
      else:
        result.add(p.advance())
    if p.pos < p.source.len: discard p.advance()
  else:
    result = p.readUntil({' ', '\t', '\n', '\r', '>', '/'})

let voidElements = ["area","base","br","col","embed","hr","img","input","link",
                    "meta","param","source","track","wbr"]
let rawElements = ["script","style","textarea","pre"]

proc parseAttrs(p: HtmlParser): Table[string, string] =
  result = initTable[string, string]()
  while p.pos < p.source.len and p.peek() notin {'>', '/'}:
    p.skip()
    if p.peek() in {'>', '/'}: break
    let name = p.readAttrName()
    if name.len == 0: break
    p.skip()
    if p.peek() == '=':
      let val = p.readAttrValue()
      result[name] = val
    else:
      result[name] = ""
    p.skip()

proc decodeEntities(s: string): string =
  var i = 0
  while i < s.len:
    if s[i] == '&' and i + 1 < s.len:
      var j = i + 1
      var entity = ""
      while j < s.len and s[j] != ';' and j - i < 12:
        entity.add(s[j])
        inc j
      if j < s.len and s[j] == ';':
        case entity
        of "amp": result.add('&'); i = j + 1; continue
        of "lt": result.add('<'); i = j + 1; continue
        of "gt": result.add('>'); i = j + 1; continue
        of "quot": result.add('"'); i = j + 1; continue
        of "apos": result.add('\''); i = j + 1; continue
        of "nbsp": result.add(' '); i = j + 1; continue
        of "copy": result.add("©"); i = j + 1; continue
        of "reg": result.add("®"); i = j + 1; continue
        of "trade": result.add("™"); i = j + 1; continue
        of "mdash": result.add("—"); i = j + 1; continue
        of "ndash": result.add("–"); i = j + 1; continue
        of "hellip": result.add("…"); i = j + 1; continue
        of "laquo": result.add("«"); i = j + 1; continue
        of "raquo": result.add("»"); i = j + 1; continue
        else:
          if entity.startsWith("#"):
            try:
              let code = if entity[1] == 'x': parseHexInt(entity[2..^1])
                         else: parseInt(entity[1..^1])
              if code < 128: result.add(chr(code))
              elif code < 0x800:
                result.add(chr(0xC0 or (code shr 6)))
                result.add(chr(0x80 or (code and 0x3F)))
              else:
                result.add(chr(0xE0 or (code shr 12)))
                result.add(chr(0x80 or ((code shr 6) and 0x3F)))
                result.add(chr(0x80 or (code and 0x3F)))
              i = j + 1; continue
            except: discard
    result.add(s[i])
    inc i

proc parseNode(p: HtmlParser, parent: Node) =
  if p.pos >= p.source.len: return
  if p.peek() == '<':
    inc p.pos
    if p.peek() == '!':
      inc p.pos
      if p.peekN(2) == "--":
        p.pos += 2
        while p.pos + 2 < p.source.len:
          if p.source[p.pos..p.pos+2] == "-->":
            p.pos += 3; break
          inc p.pos
        return
      elif p.peekN(7).toLowerAscii() == "doctype":
        discard p.readUntil({'>'})
        if p.peek() == '>': discard p.advance()
        return
      else:
        discard p.readUntil({'>'})
        if p.peek() == '>': discard p.advance()
        return
    if p.peek() == '/':
      inc p.pos
      discard p.readUntil({'>'})
      if p.peek() == '>': discard p.advance()
      return
    if p.peek() == '?':
      discard p.readUntil({'>'})
      if p.peek() == '>': discard p.advance()
      return
    let tag = p.readTagName()
    if tag.len == 0:
      discard p.readUntil({'>'})
      if p.peek() == '>': discard p.advance()
      return
    p.skip()
    let attrs = p.parseAttrs()
    p.skip()
    let selfClose = p.peek() == '/'
    if p.peek() in {'/', '>'}:
      if p.peek() == '/': discard p.advance()
      if p.peek() == '>': discard p.advance()
    let el = newElement(tag)
    for name, val in attrs:
      el.setAttribute(name, val)
    if "style" in attrs:
      from ../css/resolver import parseInlineStyle
      let parsed = parseInlineStyle(attrs["style"])
      for k, v in parsed:
        el.inlineStyle[k] = v
    parent.appendChild(el)
    if tag in voidElements or selfClose: return
    if tag in rawElements:
      let closeTag = "</" & tag
      let start = p.pos
      var i = p.pos
      while i < p.source.len - closeTag.len:
        if p.source[i..i+closeTag.len-1].toLowerAscii() == closeTag:
          break
        inc i
      let content = p.source[start..<i]
      p.pos = i
      if p.pos < p.source.len:
        discard p.readUntil({'>'})
        if p.peek() == '>': discard p.advance()
      if tag == "style" or tag == "script":
        el.textContent = content
      else:
        el.appendChild(newTextNode(decodeEntities(content)))
      return
    while p.pos < p.source.len:
      p.skip()
      if p.peek() == '<' and p.pos + 1 < p.source.len and p.source[p.pos+1] == '/':
        let closeStart = p.pos
        p.pos += 2
        let closeTag = p.readTagName()
        discard p.readUntil({'>'})
        if p.peek() == '>': discard p.advance()
        if closeTag == tag: break
        p.pos = closeStart
        break
      elif p.peek() == '<':
        parseNode(p, el)
      else:
        var text = ""
        while p.pos < p.source.len and p.peek() != '<':
          text.add(p.advance())
        let decoded = decodeEntities(text)
        if decoded.strip().len > 0 or " " in decoded:
          el.appendChild(newTextNode(decoded))
  else:
    var text = ""
    while p.pos < p.source.len and p.peek() != '<':
      text.add(p.advance())
    let decoded = decodeEntities(text)
    if decoded.strip().len > 0 or " " in decoded:
      parent.appendChild(newTextNode(decoded))

proc parse*(p: HtmlParser): Node =
  var html = newElement("html")
  var head = newElement("head")
  var body = newElement("body")
  html.appendChild(head)
  html.appendChild(body)
  p.document.appendChild(html)
  while p.pos < p.source.len:
    let start = p.pos
    parseNode(p, body)
    if p.pos == start: inc p.pos
  result = p.document

proc parseHtml*(html: string): Node =
  let p = newHtmlParser(html)
  result = p.parse()
  var head = result.querySelector("head")
  var body = result.querySelector("body")
  if head == nil:
    head = newElement("head")
    result.firstChild.insertBefore(head, result.firstChild.firstChild)
  if body == nil:
    body = newElement("body")
    result.firstChild.appendChild(body)
  result.ownerDocument = result

proc extractStyles*(doc: Node): string =
  var styles = ""
  proc walk(n: Node) =
    if n.kind == nkElement:
      if n.tag == "style":
        styles.add(n.textContent)
        styles.add("\n")
      for child in n.children: walk(child)
  walk(doc)
  styles

proc extractScripts*(doc: Node): seq[string] =
  proc walk(n: Node) =
    if n.kind == nkElement:
      if n.tag == "script" and not n.hasAttribute("src"):
        result.add(n.textContent)
      for child in n.children: walk(child)
  walk(doc)

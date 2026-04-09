import std/tables
import pixie
import ../dom

type
  FontCache* = ref object
    fonts*: Table[string, Font]
    typefaces*: Table[string, Typeface]
    defaultTypeface*: Typeface

proc newFontCache*(): FontCache =
  FontCache(
    fonts: initTable[string, Font](),
    typefaces: initTable[string, Typeface]()
  )

proc getFont*(fc: FontCache, family: string, size: float32,
               weight: FontWeightKind, style: FontStyleKind, scale: float32 = 1.0): Font =
  let key = family & ":" & $(size * scale) & ":" & $weight & ":" & $style
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
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/Arial.ttf",
        "C:/Windows/Fonts/arial.ttf",
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
  f.size = size * scale
  fc.fonts[key] = f
  result = f

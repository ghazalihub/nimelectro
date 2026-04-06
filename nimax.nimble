# Package
version       = "1.0.0"
author        = "NiMax Engine"
description   = "High-performance embeddable UI engine - Sciter clone in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["nimax"]

# Dependencies
requires "nim >= 2.0.0"
requires "pixie >= 5.0.0"

task build_headless, "Build headless renderer (no GLFW, no QuickJS)":
  exec "nim c --mm:orc -d:release -d:noQuickJs --opt:speed -o:nimax_headless src/nimax.nim"

task build_glfw, "Build with GLFW window (no QuickJS)":
  exec "nim c --mm:orc -d:release -d:nimaxGlfw -d:noQuickJs --opt:speed --passL:\"-lglfw -lGL -lm -ldl\" -o:nimax_glfw src/nimax.nim"

task build_full, "Build full engine with GLFW + QuickJS":
  exec "nim c --mm:orc -d:release -d:nimaxGlfw --opt:speed --passC:\"-I/usr/include\" --passL:\"-lglfw -lGL -lm -ldl -lquickjs\" -o:nimax src/nimax.nim"

task build_debug, "Build debug binary":
  exec "nim c --mm:orc -d:debug -d:noQuickJs --stackTrace:on --lineTrace:on -o:nimax_debug src/nimax.nim"

task demo, "Render demo to PNG":
  exec "nimble build_headless"
  exec "./nimax_headless --out=demo_output.png examples/demo.html"

# Getting Started with NiMax

This guide will help you create your first NiMax application and explain the basic workflow.

## Your First App

Create a file named `hello.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <style>
    body {
      background: #222;
      color: white;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      font-family: sans-serif;
    }
    .greeting {
      font-size: 48px;
      color: #60a5fa;
    }
  </style>
</head>
<body>
  <div class="greeting">Hello from NiMax!</div>
</body>
</html>
```

## Running from Nim

You can embed NiMax directly into your Nim project.

```nim
import nimax

let eng = newNimaxEngine(800, 600)
eng.loadHtmlFile("hello.html")
eng.enableJs() # Enable QuickJS

# Open an interactive GLFW window
eng.openWindow(defaultConfig(800, 600, "My App"))
```

## Command Line Usage

NiMax also comes with a CLI tool for quick previews and headless rendering.

### Interactive Preview
```bash
nimax --window --js hello.html
```

### Render to Image
```bash
nimax --out=preview.png hello.html
```

## Integrating Native Procs

You can call Nim procedures from JavaScript:

```nim
# Nim side
eng.registerNativeProc("sayHello", proc(args: seq[string]): string =
  echo "Nim says: Hello, ", args[0]
  return "Success"
)
```

```javascript
// JS side
const result = window.sayHello("World");
console.log(result); // "Success"
```

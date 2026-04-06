# NiMax Engine

NiMax is a high-performance, embeddable UI engine for the Nim programming language. It is designed as a Sciter-like tool for rapid GUI development, combining the power of Nim with the flexibility of web technologies (HTML/CSS/JS).

## Key Features

- **Nim Core**: Written entirely in Nim with ORC memory management.
- **Pixie Rendering**: Utilizing the [Pixie](https://github.com/treeform/pixie) library for high-speed, SIMD-accelerated vector graphics.
- **QuickJS Scripting**: Embedded [QuickJS](https://bellard.org/quickjs/) for a full ES2020 JavaScript environment.
- **Modern Layouts**: Support for Flexbox and basic CSS Grid.
- **Standard CSS**: Implements CSS Variables, Media Queries, and complex selectors.
- **Persistent Storage**: Integrated `localStorage` with automatic file-based persistence.
- **Multi-platform**: Designed to run on any platform supported by Nim, Pixie, and GLFW.

## Quick Start

1. **Install Dependencies**:
   ```bash
   nimble install pixie opengl
   ```

2. **Build the Engine**:
   ```bash
   nimble build_headless # Headless PNG renderer
   # OR
   nimble build_full     # Full interactive engine (requires GLFW)
   ```

3. **Run a Demo**:
   ```bash
   ./nimax_headless --out=output.png demo.html
   ```

## Documentation

- [Getting Started](docs/getting_started.md)
- [CSS Support](docs/css_support.md)
- [JavaScript API](docs/js_api.md)

## Architecture

NiMax is modularized into several key components:

- **Core**: DOM implementation, HTML parser, and Animation engine.
- **CSS**: A selector matching and style resolution engine.
- **Layout**: A multi-pass engine handling Block, Flex, and Grid layouts.
- **Render**: The Pixie-based painter that converts the DOM into pixels.
- **Script**: The QuickJS bridge providing a web-compatible DOM API.
- **Platform**: Window management and event handling via GLFW.

## License

NiMax is licensed under the MIT License.

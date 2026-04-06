# CSS Support in NiMax

NiMax aims for high compatibility with modern CSS standards.

## Supported Layouts

- **Block**: Standard vertical stacking.
- **Inline/Inline-Block**: Side-by-side elements with line wrapping.
- **Flexbox**: Multi-line wrapping, justify-content, align-items, gap, grow/shrink factors.
- **Grid (Basic)**: Support for `grid-template-columns` with `fr` and fixed units, and `gap`.

## New & Advanced Features

### CSS Variables (Custom Properties)
Define variables in `:root` or any element and resolve them with `var()`.
```css
:root {
  --primary-color: #3b82f6;
}
.button {
  background-color: var(--primary-color);
}
```

### Media Queries
Responsive layouts based on viewport width.
```css
@media (min-width: 600px) {
  .sidebar { display: block; }
}
@media (max-width: 599px) {
  .sidebar { display: none; }
}
```

### Box Model
Support for `box-sizing: border-box` to simplify layout math.

### Z-Index
Respects `z-index` property for controlling the stacking order of elements.

### Enhanced Backgrounds
- `background-image`: Supports `url("...")` for PNG/JPG/SVG.
- `background-size`: `cover` and `contain` supported.
- `background-repeat`: `no-repeat` and standard tiling.
- `gradients`: Linear and radial gradients supported.

## Selector Support
- Type, ID, and Class selectors.
- Attribute selectors (e.g., `[type="text"]`).
- Pseudo-classes: `:hover`, `:active`, `:focus`, `:first-child`, `:last-child`, `:nth-child()`, `:not()`.
- Sibling combinators: `+` (adjacent) and `~` (general).
- Descendant and Child combinators.

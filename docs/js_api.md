# JavaScript & DOM API

NiMax provides a familiar web-like environment powered by QuickJS.

## The Global `window` Object

The global scope includes standard Web APIs:

- `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`
- `requestAnimationFrame`, `cancelAnimationFrame`
- `console.log`, `info`, `warn`, `error`, `table`, `assert`
- `alert`, `confirm`, `prompt`
- `fetch` (Basic implementation)
- `localStorage` & `sessionStorage` (Persistent across restarts)

## DOM Support

You can manipulate the document using standard methods:

### Document Methods
- `document.getElementById(id)`
- `document.querySelector(selector)`
- `document.querySelectorAll(selector)`
- `document.createElement(tagName)`
- `document.createTextNode(text)`
- `document.addEventListener(type, listener)`

### Element Properties & Methods
- `element.innerHTML`, `element.textContent`, `element.value`
- `element.classList` (`add`, `remove`, `toggle`, `contains`)
- `element.setAttribute(name, value)`, `element.getAttribute(name)`
- `element.style.propertyName` (e.g., `element.style.color = 'red'`)
- `element.appendChild(node)`, `element.removeChild(node)`
- `element.scroll()`, `element.scrollTo()`, `element.scrollBy()`
- `element.getBoundingClientRect()`

### Style Resolution
- `window.getComputedStyle(element)`: Returns an object containing the resolved styles of an element.

## NiMax Specifics

### The `nimax` Object
Access engine-specific information:
```javascript
console.log(window.nimax.version);  // e.g., "1.0.0"
console.log(window.nimax.platform); // "Nim"
```

### Persistence
`localStorage` data is automatically saved to `.nimax_localstorage.json` in the application directory, allowing your app to maintain state between launches.

### Debugging
The NiMax console has been enhanced to handle complex objects and circular references (like DOM nodes), making it easy to inspect your app's state.

import std/[tables, strutils, sequtils, times, math, options, hashes]
import ../core/dom
import ../css/resolver

{.push raises: [].}

type
  NativeCallback* = proc(args: seq[string]): string {.closure.}

  TimerEntry* = object
    id*: int
    fireAt*: float64
    intervalMs*: float64
    repeating*: bool
    cancelled*: bool
    src*: string

  JsBridge* = ref object
    dom*: Node
    timers*: seq[TimerEntry]
    timerCounter*: int
    nativeProcs*: Table[string, NativeCallback]
    pendingEvals*: seq[string]
    renderPending*: bool
    onRenderRequest*: proc() {.closure.}
    onNavigate*: proc(url: string) {.closure.}
    onTitleChange*: proc(title: string) {.closure.}
    scriptLog*: seq[string]

proc newJsBridge*(dom: Node): JsBridge =
  JsBridge(
    dom: dom,
    timers: @[],
    timerCounter: 1000,
    nativeProcs: initTable[string, NativeCallback](),
    pendingEvals: @[],
    scriptLog: @[]
  )

proc registerNative*(b: JsBridge, name: string, cb: NativeCallback) =
  b.nativeProcs[name] = cb

proc scheduleTimer*(b: JsBridge, src: string, delayMs: float64, repeat: bool): int =
  inc b.timerCounter
  b.timers.add(TimerEntry(
    id: b.timerCounter,
    fireAt: epochTime() * 1000 + delayMs,
    intervalMs: delayMs,
    repeating: repeat,
    cancelled: false,
    src: src
  ))
  b.timerCounter

proc cancelTimer*(b: JsBridge, id: int) =
  for i in 0..<b.timers.len:
    if b.timers[i].id == id:
      b.timers[i].cancelled = true

proc collectFiredTimers*(b: JsBridge): seq[TimerEntry] =
  let now = epochTime() * 1000
  var keep: seq[TimerEntry]
  for t in b.timers:
    if t.cancelled: continue
    if now >= t.fireAt:
      result.add(t)
      if t.repeating:
        keep.add(TimerEntry(
          id: t.id, fireAt: t.fireAt + t.intervalMs,
          intervalMs: t.intervalMs, repeating: true,
          cancelled: false, src: t.src
        ))
    else:
      keep.add(t)
  b.timers = keep

proc buildDomAccessorJs*(): string =
  """
(function() {
  var _nimNodeMap = {};

  function _wrap(nimId) {
    if (!nimId) return null;
    if (_nimNodeMap[nimId]) return _nimNodeMap[nimId];
    var proxy = { __nimId: nimId };
    _nimNodeMap[nimId] = proxy;
    return proxy;
  }

  function _unwrap(obj) {
    if (!obj) return 0;
    return obj.__nimId || 0;
  }

  window.__wrapNode = _wrap;
  window.__unwrapNode = _unwrap;
})();
"""

proc buildEventDispatcherJs*(): string =
  """
window.__dispatchDomEvent = function(nimNodeId, eventType, eventData) {
  var node = window.__wrapNode ? window.__wrapNode(nimNodeId) : null;
  if (!node) return;
  var listeners = node.__listeners || {};
  var arr = listeners[eventType] || [];
  for (var i = 0; i < arr.length; i++) {
    try { arr[i](eventData); } catch(e) { console.error(e); }
  }
};
"""

proc synthesizeRuntimeJs*(bridge: JsBridge): string =
  var sb = newStringOfCap(8192)

  sb.add """
'use strict';
(function(global) {

var __nimTimerSerial = 1;
var __timers = {};

global.setTimeout = function(fn, ms) {
  var id = __nimTimerSerial++;
  var delay = (ms || 0);
  __timers[id] = fn;
  __nim_scheduleTimer(String(id), String(delay), "0");
  return id;
};
global.clearTimeout = function(id) {
  delete __timers[id];
  __nim_cancelTimer(String(id));
};
global.setInterval = function(fn, ms) {
  var id = __nimTimerSerial++;
  var delay = (ms || 16);
  __timers[id] = fn;
  __nim_scheduleTimer(String(id), String(delay), "1");
  return id;
};
global.clearInterval = function(id) {
  delete __timers[id];
  __nim_cancelTimer(String(id));
};
global.requestAnimationFrame = function(fn) {
  return global.setTimeout(fn, 16);
};
global.cancelAnimationFrame = global.clearTimeout;
global.__fireTimer = function(id) {
  var fn = __timers[id];
  if (fn) { try { fn(performance.now()); } catch(e) { console.error('timer err', e); } }
};

var __perfStart = Date.now();
global.performance = { now: function() { return Date.now() - __perfStart; } };

global.console = {
  _log: function(level, args) {
    var msg = args.map(function(a) {
      if (typeof a === 'object') { try { return JSON.stringify(a); } catch(e) { return String(a); } }
      return String(a);
    }).join(' ');
    __nim_log(level, msg);
  },
  log:   function() { this._log('log',   Array.prototype.slice.call(arguments)); },
  error: function() { this._log('error', Array.prototype.slice.call(arguments)); },
  warn:  function() { this._log('warn',  Array.prototype.slice.call(arguments)); },
  info:  function() { this._log('info',  Array.prototype.slice.call(arguments)); },
  debug: function() { this._log('debug', Array.prototype.slice.call(arguments)); },
  assert: function(cond) {
    if (!cond) this._log('error', ['Assertion failed'].concat(Array.prototype.slice.call(arguments, 1)));
  },
  group: function(){}, groupEnd: function(){},
  time: function(){}, timeEnd: function(){}
};

global.alert   = function(msg) { __nim_log('alert', String(msg)); };
global.confirm = function(msg) { __nim_log('confirm', String(msg)); return true; };
global.prompt  = function(msg, def) { return def || null; };

global.window  = global;
global.self    = global;
global.globalThis = global;

global.navigator = {
  userAgent: 'NiMax/1.0',
  language: 'en-US',
  languages: ['en-US','en'],
  platform: 'NimOS',
  onLine: true,
  cookieEnabled: false,
  hardwareConcurrency: 4,
  vendor: 'NiMax Team',
  appName: 'NiMax',
  appVersion: '1.0'
};

global.screen = {
  width: 1280, height: 720,
  availWidth: 1280, availHeight: 720,
  colorDepth: 24, pixelDepth: 24
};

global.location = {
  href: 'about:blank', origin: 'null',
  protocol: 'about:', host: '', hostname: '',
  port: '', pathname: '/', search: '', hash: '',
  reload: function() {},
  assign: function(u) { __nim_navigate(u); },
  replace: function(u) { __nim_navigate(u); }
};

global.history = {
  length: 1,
  pushState: function(s,t,u) { if(u) __nim_navigate(u); },
  replaceState: function(s,t,u) { if(u) __nim_navigate(u); },
  back: function(){}, forward: function(){}, go: function(){}
};

var __nodeListeners = {};

function __getListeners(nimId, type) {
  var key = nimId + ':' + type;
  if (!__nodeListeners[key]) __nodeListeners[key] = [];
  return __nodeListeners[key];
}

global.__dispatchNativeEvent = function(nimId, type, data) {
  var arr = __getListeners(nimId, type);
  var arr2 = __getListeners(nimId, '*');
  var all = arr.concat(arr2);
  for (var i = 0; i < all.length; i++) {
    try { all[i](data); } catch(e) { console.error('event handler err:', e); }
  }
};

function __makeNode(nimId) {
  if (!nimId) return null;
  var info = JSON.parse(__nim_nodeInfo(String(nimId)));
  if (!info) return null;

  var node = {
    __nimId: nimId,
    nodeType: info.nodeType,
    tagName: info.tagName,
    nodeName: info.tagName || '#text',
    id: info.id || '',
    className: info.className || '',
    textContent: info.textContent || '',
    innerText: info.textContent || '',
    value: info.value || '',
    checked: info.checked || false,
    disabled: info.disabled || false,
    tabIndex: info.tabIndex || 0,
    href: info.href || '',
    src: info.src || '',
    type: info.inputType || '',

    get innerHTML() {
      return __nim_getInnerHTML(String(this.__nimId));
    },
    set innerHTML(v) {
      __nim_setInnerHTML(String(this.__nimId), String(v));
    },
    get outerHTML() {
      return __nim_getOuterHTML(String(this.__nimId));
    },
    get offsetLeft()   { var r = this.getBoundingClientRect(); return r.left; },
    get offsetTop()    { var r = this.getBoundingClientRect(); return r.top; },
    get offsetWidth()  { var r = this.getBoundingClientRect(); return r.width; },
    get offsetHeight() { var r = this.getBoundingClientRect(); return r.height; },
    get clientWidth()  { return JSON.parse(__nim_getLayout(String(this.__nimId))).clientWidth || 0; },
    get clientHeight() { return JSON.parse(__nim_getLayout(String(this.__nimId))).clientHeight || 0; },
    get scrollLeft() { return JSON.parse(__nim_getLayout(String(this.__nimId))).scrollX || 0; },
    set scrollLeft(v) { __nim_setScroll(String(this.__nimId), String(v), null); },
    get scrollTop()  { return JSON.parse(__nim_getLayout(String(this.__nimId))).scrollY || 0; },
    set scrollTop(v) { __nim_setScroll(String(this.__nimId), null, String(v)); },
    get scrollWidth()  { return JSON.parse(__nim_getLayout(String(this.__nimId))).scrollWidth || 0; },
    get scrollHeight() { return JSON.parse(__nim_getLayout(String(this.__nimId))).scrollHeight || 0; },

    get parentNode() {
      var pid = __nim_getParent(String(this.__nimId));
      return pid ? __makeNode(parseInt(pid)) : null;
    },
    get parentElement() { return this.parentNode; },
    get children() {
      var ids = JSON.parse(__nim_getChildren(String(this.__nimId)));
      return ids.map(function(id) { return __makeNode(id); });
    },
    get childNodes() { return this.children; },
    get firstChild() {
      var c = this.children; return c.length ? c[0] : null;
    },
    get lastChild() {
      var c = this.children; return c.length ? c[c.length-1] : null;
    },
    get nextSibling() {
      var id = __nim_getNextSibling(String(this.__nimId));
      return id ? __makeNode(parseInt(id)) : null;
    },
    get previousSibling() {
      var id = __nim_getPrevSibling(String(this.__nimId));
      return id ? __makeNode(parseInt(id)) : null;
    },
    get nextElementSibling() { return this.nextSibling; },
    get previousElementSibling() { return this.previousSibling; },

    style: (function(nimId) {
      var styleProxy = {};
      var props = ['display','width','height','color','backgroundColor','fontSize',
                   'fontFamily','fontWeight','fontStyle','margin','padding','border',
                   'borderRadius','opacity','transform','transition','visibility',
                   'overflow','position','top','left','right','bottom','zIndex',
                   'flexDirection','justifyContent','alignItems','flex','gap',
                   'lineHeight','textAlign','cursor','boxShadow','filter',
                   'backgroundImage','borderColor','borderWidth','borderStyle',
                   'maxWidth','maxHeight','minWidth','minHeight','gridTemplateColumns',
                   'gridTemplateRows','objectFit','pointerEvents','userSelect'];
      props.forEach(function(p) {
        Object.defineProperty(styleProxy, p, {
          get: function() {
            return __nim_getStyle(String(nimId), p);
          },
          set: function(v) {
            __nim_setStyle(String(nimId), p, String(v));
          },
          enumerable: true, configurable: true
        });
      });
      styleProxy.setProperty = function(name, val) {
        __nim_setStyle(String(nimId), name, String(val));
      };
      styleProxy.getPropertyValue = function(name) {
        return __nim_getStyle(String(nimId), name);
      };
      styleProxy.removeProperty = function(name) {
        __nim_setStyle(String(nimId), name, '');
      };
      styleProxy.cssText = '';
      return styleProxy;
    })(nimId),

    classList: (function(nimId) {
      return {
        add:     function() { Array.prototype.forEach.call(arguments, function(c) { __nim_classOp(String(nimId),'add',c); }); },
        remove:  function() { Array.prototype.forEach.call(arguments, function(c) { __nim_classOp(String(nimId),'remove',c); }); },
        toggle:  function(c,f) {
          if (f === undefined) return __nim_classOp(String(nimId),'toggle',c) === 'true';
          if (f) { __nim_classOp(String(nimId),'add',c); return true; }
          else   { __nim_classOp(String(nimId),'remove',c); return false; }
        },
        contains: function(c) { return __nim_classOp(String(nimId),'contains',c) === 'true'; },
        replace:  function(o,n) { __nim_classOp(String(nimId),'replace',o+' '+n); },
        get value() { return __nim_classOp(String(nimId),'value',''); },
        item: function(i) {
          var v = __nim_classOp(String(nimId),'value','');
          return v.split(' ')[i] || null;
        }
      };
    })(nimId),

    dataset: (function(nimId) {
      return new Proxy({}, {
        get: function(t,p) { return __nim_getDataset(String(nimId), String(p)); },
        set: function(t,p,v) { __nim_setDataset(String(nimId), String(p), String(v)); return true; }
      });
    })(nimId),

    getAttribute: function(n) {
      var v = __nim_getAttr(String(this.__nimId), n);
      return v === '\x00' ? null : v;
    },
    setAttribute: function(n,v) { __nim_setAttr(String(this.__nimId),n,String(v)); },
    hasAttribute: function(n) { return __nim_hasAttr(String(this.__nimId),n) === 'true'; },
    removeAttribute: function(n) { __nim_removeAttr(String(this.__nimId),n); },
    hasAttributes: function() {
      return JSON.parse(__nim_getAttrNames(String(this.__nimId))).length > 0;
    },
    getAttributeNames: function() {
      return JSON.parse(__nim_getAttrNames(String(this.__nimId)));
    },

    matches: function(sel) {
      return __nim_matches(String(this.__nimId), sel) === 'true';
    },
    closest: function(sel) {
      var id = __nim_closest(String(this.__nimId), sel);
      return id ? __makeNode(parseInt(id)) : null;
    },
    contains: function(other) {
      if (!other) return false;
      return __nim_contains(String(this.__nimId), String(other.__nimId)) === 'true';
    },

    querySelector: function(sel) {
      var id = __nim_querySelector(String(this.__nimId), sel);
      return id ? __makeNode(parseInt(id)) : null;
    },
    querySelectorAll: function(sel) {
      var ids = JSON.parse(__nim_querySelectorAll(String(this.__nimId), sel));
      return ids.map(function(id) { return __makeNode(id); });
    },
    getElementsByTagName: function(tag) {
      return this.querySelectorAll(tag);
    },
    getElementsByClassName: function(cls) {
      return this.querySelectorAll('.' + cls);
    },

    appendChild: function(child) {
      if (!child || !child.__nimId) return child;
      __nim_appendChild(String(this.__nimId), String(child.__nimId));
      return child;
    },
    removeChild: function(child) {
      if (!child || !child.__nimId) return child;
      __nim_removeChild(String(this.__nimId), String(child.__nimId));
      return child;
    },
    insertBefore: function(newNode, refNode) {
      if (!newNode) return newNode;
      __nim_insertBefore(String(this.__nimId),
        String(newNode.__nimId),
        refNode ? String(refNode.__nimId) : '0');
      return newNode;
    },
    replaceChild: function(newChild, oldChild) {
      if (!newChild || !oldChild) return oldChild;
      __nim_replaceChild(String(this.__nimId), String(newChild.__nimId), String(oldChild.__nimId));
      return oldChild;
    },
    insertAdjacentElement: function(pos, el) {
      __nim_insertAdjacent(String(this.__nimId), pos, String(el.__nimId));
      return el;
    },
    insertAdjacentHTML: function(pos, html) {
      __nim_insertAdjacentHTML(String(this.__nimId), pos, html);
    },
    insertAdjacentText: function(pos, text) {
      __nim_insertAdjacentHTML(String(this.__nimId), pos, text);
    },
    cloneNode: function(deep) {
      var id = __nim_cloneNode(String(this.__nimId), deep ? '1' : '0');
      return id ? __makeNode(parseInt(id)) : null;
    },
    remove: function() {
      var pid = __nim_getParent(String(this.__nimId));
      if (pid) __nim_removeChild(pid, String(this.__nimId));
    },
    before: function() {
      var self = this;
      Array.prototype.forEach.call(arguments, function(n) {
        if (typeof n === 'string') __nim_insertAdjacentHTML(String(self.__nimId), 'beforebegin', n);
        else if (n && n.__nimId) __nim_insertAdjacent(String(self.__nimId), 'beforebegin', String(n.__nimId));
      });
    },
    after: function() {
      var self = this;
      Array.prototype.forEach.call(arguments, function(n) {
        if (typeof n === 'string') __nim_insertAdjacentHTML(String(self.__nimId), 'afterend', n);
        else if (n && n.__nimId) __nim_insertAdjacent(String(self.__nimId), 'afterend', String(n.__nimId));
      });
    },
    prepend: function() {
      var self = this;
      var first = self.firstChild;
      Array.prototype.forEach.call(arguments, function(n) {
        if (typeof n === 'string') {
          var t = document.createTextNode(n);
          if (first) self.insertBefore(t, first); else self.appendChild(t);
        } else if (n && n.__nimId) {
          if (first) self.insertBefore(n, first); else self.appendChild(n);
        }
      });
    },
    append: function() {
      var self = this;
      Array.prototype.forEach.call(arguments, function(n) {
        if (typeof n === 'string') {
          self.appendChild(document.createTextNode(n));
        } else if (n && n.__nimId) {
          self.appendChild(n);
        }
      });
    },
    replaceWith: function(n) {
      var pid = __nim_getParent(String(this.__nimId));
      if (!pid) return;
      var parent = __makeNode(parseInt(pid));
      if (n && n.__nimId) parent.replaceChild(n, this);
    },

    addEventListener: function(type, fn, opts) {
      var arr = __getListeners(this.__nimId, type);
      if (arr.indexOf(fn) < 0) arr.push(fn);
      __nim_addListener(String(this.__nimId), type);
    },
    removeEventListener: function(type, fn) {
      var key = this.__nimId + ':' + type;
      var arr = __nodeListeners[key] || [];
      var idx = arr.indexOf(fn);
      if (idx >= 0) arr.splice(idx, 1);
    },
    dispatchEvent: function(ev) {
      __nim_dispatchEvent(String(this.__nimId), ev.type || '');
      return true;
    },

    focus: function() { __nim_focus(String(this.__nimId)); },
    blur:  function() { __nim_blur(String(this.__nimId)); },
    click: function() {
      __dispatchNativeEvent(this.__nimId, 'click', {type:'click', target:this, bubbles:true, cancelable:true, clientX:0, clientY:0});
    },
    scrollIntoView: function(opts) { __nim_scrollIntoView(String(this.__nimId)); },
    getBoundingClientRect: function() {
      return JSON.parse(__nim_getBCR(String(this.__nimId)));
    },
    getClientRects: function() {
      return [this.getBoundingClientRect()];
    },
    animate: function(keyframes, opts) {
      var duration = typeof opts === 'number' ? opts : (opts && opts.duration || 300);
      var fill = opts && opts.fill || 'none';
      var easing = opts && opts.easing || 'ease';
      __nim_animate(String(this.__nimId), JSON.stringify(keyframes), String(duration), easing, fill);
      return {
        finished: Promise.resolve(),
        cancel: function(){},
        pause: function(){},
        play: function(){}
      };
    },
    requestPointerLock: function() {},
    releasePointerCapture: function() {},
    setPointerCapture: function() {}
  };
  return node;
}

global.__makeNode = __makeNode;

var __docId = parseInt(__nim_getDocumentId());

global.document = {
  nodeType: 9,
  nodeName: '#document',
  __nimId: __docId,

  get documentElement() { return __makeNode(parseInt(__nim_querySelector(String(__docId), 'html'))); },
  get head()   { return __makeNode(parseInt(__nim_querySelector(String(__docId), 'head'))); },
  get body()   { return __makeNode(parseInt(__nim_querySelector(String(__docId), 'body'))); },
  get title()  {
    var t = this.querySelector('title');
    return t ? t.textContent : '';
  },
  set title(v) {
    var t = this.querySelector('title');
    if (!t) {
      t = this.createElement('title');
      this.head.appendChild(t);
    }
    __nim_setTextContent(String(t.__nimId), String(v));
    __nim_titleChange(String(v));
  },
  get readyState() { return 'complete'; },
  get URL() { return 'about:blank'; },
  get documentURI() { return 'about:blank'; },
  get characterSet() { return 'UTF-8'; },
  get charset() { return 'UTF-8'; },
  get compatMode() { return 'CSS1Compat'; },
  get doctype() { return null; },
  get defaultView() { return global; },
  get activeElement() {
    var id = __nim_getActiveElement();
    return id ? __makeNode(parseInt(id)) : null;
  },
  hasFocus: function() { return true; },

  getElementById: function(id) {
    var nid = __nim_querySelector(String(__docId), '#'+id);
    return nid ? __makeNode(parseInt(nid)) : null;
  },
  getElementsByTagName: function(tag) {
    var ids = JSON.parse(__nim_querySelectorAll(String(__docId), tag));
    return ids.map(function(id) { return __makeNode(id); });
  },
  getElementsByClassName: function(cls) {
    var ids = JSON.parse(__nim_querySelectorAll(String(__docId), '.'+cls));
    return ids.map(function(id) { return __makeNode(id); });
  },
  getElementsByName: function(name) {
    var ids = JSON.parse(__nim_querySelectorAll(String(__docId), '[name="'+name+'"]'));
    return ids.map(function(id) { return __makeNode(id); });
  },
  querySelector: function(sel) {
    var id = __nim_querySelector(String(__docId), sel);
    return id ? __makeNode(parseInt(id)) : null;
  },
  querySelectorAll: function(sel) {
    var ids = JSON.parse(__nim_querySelectorAll(String(__docId), sel));
    return ids.map(function(id) { return __makeNode(id); });
  },

  createElement: function(tag) {
    var id = parseInt(__nim_createElement(tag));
    return id ? __makeNode(id) : null;
  },
  createElementNS: function(ns, tag) { return this.createElement(tag); },
  createTextNode: function(text) {
    var id = parseInt(__nim_createTextNode(String(text)));
    return id ? __makeNode(id) : null;
  },
  createDocumentFragment: function() {
    var id = parseInt(__nim_createFragment());
    return id ? __makeNode(id) : null;
  },
  createComment: function(text) {
    return this.createTextNode(text);
  },
  createEvent: function(type) {
    return {
      type: '',
      bubbles: false,
      cancelable: false,
      target: null,
      currentTarget: null,
      defaultPrevented: false,
      initEvent: function(t,b,c) { this.type=t; this.bubbles=b; this.cancelable=c; },
      initMouseEvent: function(t,b,c,v,d,sx,sy,cx,cy,ctrl,alt,shift,meta,btn,rel) {
        this.type=t; this.bubbles=b; this.cancelable=c;
        this.clientX=cx; this.clientY=cy; this.ctrlKey=ctrl;
        this.altKey=alt; this.shiftKey=shift; this.metaKey=meta; this.button=btn;
      },
      preventDefault: function() { this.defaultPrevented = true; },
      stopPropagation: function() { this.propagationStopped = true; },
      stopImmediatePropagation: function() { this.propagationStopped = true; }
    };
  },
  createRange: function() {
    return {
      setStart: function(){}, setEnd: function(){},
      selectNodeContents: function(){},
      getBoundingClientRect: function() { return {x:0,y:0,width:0,height:0,top:0,left:0,right:0,bottom:0}; },
      collapse: function(){}, cloneContents: function() { return null; }
    };
  },
  importNode: function(node, deep) { return node; },
  adoptNode: function(node) { return node; },

  addEventListener: function(type, fn, opts) {
    var arr = __getListeners(__docId, type);
    if (arr.indexOf(fn) < 0) arr.push(fn);
    __nim_addListener(String(__docId), type);
  },
  removeEventListener: function(type, fn) {
    var key = __docId + ':' + type;
    var arr = __nodeListeners[key] || [];
    var idx = arr.indexOf(fn);
    if (idx >= 0) arr.splice(idx, 1);
  },
  dispatchEvent: function(ev) {
    __nim_dispatchEvent(String(__docId), ev.type || '');
    return true;
  }
};

global.Node = { ELEMENT_NODE:1, TEXT_NODE:3, COMMENT_NODE:8, DOCUMENT_NODE:9 };
global.Element = {};
global.HTMLElement = {};
global.Event = function(type, opts) {
  this.type = type;
  this.bubbles = opts && opts.bubbles || false;
  this.cancelable = opts && opts.cancelable || false;
  this.defaultPrevented = false;
  this.propagationStopped = false;
  this.target = null;
  this.currentTarget = null;
  this.timeStamp = performance.now();
  this.preventDefault = function() { this.defaultPrevented = true; };
  this.stopPropagation = function() { this.propagationStopped = true; };
  this.stopImmediatePropagation = function() { this.propagationStopped = true; };
};
global.MouseEvent = function(type, opts) {
  Event.call(this, type, opts);
  this.clientX = opts && opts.clientX || 0;
  this.clientY = opts && opts.clientY || 0;
  this.pageX = this.clientX; this.pageY = this.clientY;
  this.button = opts && opts.button || 0;
  this.buttons = opts && opts.buttons || 0;
  this.ctrlKey = opts && opts.ctrlKey || false;
  this.shiftKey = opts && opts.shiftKey || false;
  this.altKey = opts && opts.altKey || false;
  this.metaKey = opts && opts.metaKey || false;
};
global.KeyboardEvent = function(type, opts) {
  Event.call(this, type, opts);
  this.key = opts && opts.key || '';
  this.code = opts && opts.code || '';
  this.keyCode = opts && opts.keyCode || 0;
  this.charCode = opts && opts.charCode || 0;
  this.which = this.keyCode;
  this.ctrlKey = opts && opts.ctrlKey || false;
  this.shiftKey = opts && opts.shiftKey || false;
  this.altKey = opts && opts.altKey || false;
  this.metaKey = opts && opts.metaKey || false;
  this.repeat = opts && opts.repeat || false;
};
global.InputEvent = function(type, opts) {
  Event.call(this, type, opts);
  this.data = opts && opts.data || '';
  this.inputType = opts && opts.inputType || '';
};
global.CustomEvent = function(type, opts) {
  Event.call(this, type, opts);
  this.detail = opts && opts.detail || null;
};

global.Promise = (function() {
  function Promise(executor) {
    this._state = 'pending';
    this._value = undefined;
    this._handlers = [];
    var self = this;
    function resolve(val) {
      if (self._state !== 'pending') return;
      self._state = 'fulfilled'; self._value = val;
      self._handlers.forEach(function(h) { if(h.onFulfilled) setTimeout(function(){h.onFulfilled(val);},0); });
    }
    function reject(reason) {
      if (self._state !== 'pending') return;
      self._state = 'rejected'; self._value = reason;
      self._handlers.forEach(function(h) { if(h.onRejected) setTimeout(function(){h.onRejected(reason);},0); });
    }
    try { executor(resolve, reject); }
    catch(e) { reject(e); }
  }
  Promise.prototype.then = function(onFulfilled, onRejected) {
    var self = this;
    return new Promise(function(resolve, reject) {
      function handle(fn, val, fallback) {
        if (typeof fn !== 'function') { fallback(val); return; }
        try { resolve(fn(val)); } catch(e) { reject(e); }
      }
      if (self._state === 'fulfilled') setTimeout(function(){ handle(onFulfilled, self._value, resolve); }, 0);
      else if (self._state === 'rejected') setTimeout(function(){ handle(onRejected, self._value, reject); }, 0);
      else self._handlers.push({onFulfilled: function(v){ handle(onFulfilled,v,resolve); }, onRejected: function(r){ handle(onRejected,r,reject); }});
    });
  };
  Promise.prototype.catch = function(fn) { return this.then(null, fn); };
  Promise.prototype.finally = function(fn) {
    return this.then(function(v){ fn(); return v; }, function(r){ fn(); throw r; });
  };
  Promise.resolve = function(v) { return new Promise(function(res){ res(v); }); };
  Promise.reject  = function(r) { return new Promise(function(_,rej){ rej(r); }); };
  Promise.all = function(arr) {
    return new Promise(function(resolve, reject) {
      var results = []; var count = arr.length;
      if (!count) { resolve(results); return; }
      arr.forEach(function(p,i) {
        Promise.resolve(p).then(function(v){ results[i]=v; if(--count===0) resolve(results); }, reject);
      });
    });
  };
  Promise.race = function(arr) {
    return new Promise(function(resolve, reject) {
      arr.forEach(function(p){ Promise.resolve(p).then(resolve, reject); });
    });
  };
  Promise.allSettled = function(arr) {
    return Promise.all(arr.map(function(p) {
      return Promise.resolve(p).then(
        function(v){ return {status:'fulfilled', value:v}; },
        function(r){ return {status:'rejected', reason:r}; }
      );
    }));
  };
  return Promise;
})();

global.fetch = function(url, opts) {
  var result = __nim_fetch(String(url), JSON.stringify(opts||{}));
  try {
    var r = JSON.parse(result);
    return Promise.resolve({
      ok: r.ok !== false,
      status: r.status || 200,
      statusText: r.statusText || 'OK',
      headers: { get: function(h) { return (r.headers||{})[h]||null; } },
      json:   function() { return Promise.resolve(JSON.parse(r.body||'{}')); },
      text:   function() { return Promise.resolve(r.body||''); },
      blob:   function() { return Promise.resolve(null); }
    });
  } catch(e) {
    return Promise.reject(new Error('fetch error: ' + e));
  }
};

global.XMLHttpRequest = function() {
  this.readyState = 0;
  this.status = 0;
  this.statusText = '';
  this.responseText = '';
  this.response = null;
  this.responseType = '';
  this.onreadystatechange = null;
  this.onload = null;
  this.onerror = null;
  this._method = '';
  this._url = '';
  this._headers = {};
  this.open = function(method, url) { this._method = method; this._url = url; this.readyState = 1; };
  this.setRequestHeader = function(name, val) { this._headers[name] = val; };
  this.getResponseHeader = function(name) { return null; };
  this.send = function(body) {
    var self = this;
    setTimeout(function() {
      var result = __nim_fetch(self._url, JSON.stringify({method: self._method, body: body, headers: self._headers}));
      try {
        var r = JSON.parse(result);
        self.status = r.status || 200;
        self.statusText = r.statusText || 'OK';
        self.responseText = r.body || '';
        self.response = self.responseType === 'json' ? JSON.parse(r.body||'null') : self.responseText;
        self.readyState = 4;
        if (self.onreadystatechange) self.onreadystatechange();
        if (self.onload) self.onload({target: self});
      } catch(e) {
        if (self.onerror) self.onerror(e);
      }
    }, 0);
  };
  this.abort = function() { this.readyState = 0; };
};

global.URL = function(url, base) {
  this.href = url;
  this.pathname = url.replace(/^[^:]+:\/\/[^\/]*/, '') || '/';
  this.search = '';
  this.hash = '';
  this.host = '';
  this.hostname = '';
  this.origin = 'null';
  this.protocol = url.split(':')[0] + ':';
  this.toString = function() { return this.href; };
};
global.URL.createObjectURL = function() { return 'blob:nimax/' + Math.random(); };
global.URL.revokeObjectURL = function() {};

global.MutationObserver = function(callback) {
  this._cb = callback;
  this.observe = function(target, opts) {};
  this.disconnect = function() {};
  this.takeRecords = function() { return []; };
};

global.ResizeObserver = function(callback) {
  this._cb = callback;
  this.observe = function(target, opts) {
    __nim_observeResize(String(target.__nimId));
  };
  this.unobserve = function(target) {};
  this.disconnect = function() {};
};

global.IntersectionObserver = function(callback, opts) {
  this._cb = callback;
  this.observe = function() {};
  this.unobserve = function() {};
  this.disconnect = function() {};
};

global.getComputedStyle = function(el) {
  var nimId = el.__nimId;
  return {
    getPropertyValue: function(prop) {
      return __nim_getComputedStyle(String(nimId), prop);
    },
    get display()          { return __nim_getComputedStyle(String(nimId),'display'); },
    get width()            { return __nim_getComputedStyle(String(nimId),'width'); },
    get height()           { return __nim_getComputedStyle(String(nimId),'height'); },
    get color()            { return __nim_getComputedStyle(String(nimId),'color'); },
    get backgroundColor()  { return __nim_getComputedStyle(String(nimId),'background-color'); },
    get fontSize()         { return __nim_getComputedStyle(String(nimId),'font-size'); },
    get fontFamily()       { return __nim_getComputedStyle(String(nimId),'font-family'); },
    get fontWeight()       { return __nim_getComputedStyle(String(nimId),'font-weight'); },
    get margin()           { return __nim_getComputedStyle(String(nimId),'margin'); },
    get padding()          { return __nim_getComputedStyle(String(nimId),'padding'); },
    get position()         { return __nim_getComputedStyle(String(nimId),'position'); },
    get opacity()          { return __nim_getComputedStyle(String(nimId),'opacity'); },
    get transform()        { return __nim_getComputedStyle(String(nimId),'transform'); },
    get visibility()       { return __nim_getComputedStyle(String(nimId),'visibility'); },
    get overflow()         { return __nim_getComputedStyle(String(nimId),'overflow'); },
    get zIndex()           { return __nim_getComputedStyle(String(nimId),'z-index'); },
    get flex()             { return __nim_getComputedStyle(String(nimId),'flex'); },
    get flexDirection()    { return __nim_getComputedStyle(String(nimId),'flex-direction'); },
    get justifyContent()   { return __nim_getComputedStyle(String(nimId),'justify-content'); },
    get alignItems()       { return __nim_getComputedStyle(String(nimId),'align-items'); },
    get lineHeight()       { return __nim_getComputedStyle(String(nimId),'line-height'); },
    get cursor()           { return __nim_getComputedStyle(String(nimId),'cursor'); },
    get borderRadius()     { return __nim_getComputedStyle(String(nimId),'border-radius'); }
  };
};

global.__nim_native = function(name) {
  return function() {
    var args = Array.prototype.slice.call(arguments).map(String);
    return __nim_callNative(name, JSON.stringify(args));
  };
};

global.localStorage = (function() {
  var store = {};
  return {
    getItem: function(k) { return store[k] !== undefined ? store[k] : null; },
    setItem: function(k,v) { store[k] = String(v); },
    removeItem: function(k) { delete store[k]; },
    clear: function() { store = {}; },
    key: function(i) { return Object.keys(store)[i] || null; },
    get length() { return Object.keys(store).length; }
  };
})();
global.sessionStorage = global.localStorage;

global.queueMicrotask = function(fn) { setTimeout(fn, 0); };

global.structuredClone = function(obj) {
  try { return JSON.parse(JSON.stringify(obj)); } catch(e) { return obj; }
};

global.crypto = {
  getRandomValues: function(arr) {
    for (var i = 0; i < arr.length; i++) arr[i] = Math.floor(Math.random() * 256);
    return arr;
  },
  randomUUID: function() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r = Math.random() * 16 | 0;
      return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
  }
};

})(typeof globalThis !== 'undefined' ? globalThis : this);
"""

  for name in bridge.nativeProcs.keys:
    sb.add("window['" & name & "'] = window.__nim_native('" & name & "');\n")

  sb

{.pop.}

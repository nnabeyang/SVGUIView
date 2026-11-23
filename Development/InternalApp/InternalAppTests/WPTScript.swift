import Foundation
import JavaScriptCore
import SVGUIView

/// The scripts of a file of web-platform-tests, which a reftest runs before it's rendered: the `<script>` elements
/// without a URL, and the `onload` attributes of the root element and of the `<image>` elements.
///
/// The scripts that a file reads by a URL are the ones of WPT that ``WPTScriptRunner`` provides the functions of:
/// `/common/reftest-wait.js` and `/common/rendering-utils.js`.
struct WPTScripts: Sendable {
  /// The text of the `<script>` elements, in document order.
  var scripts = [String]()
  /// The `onload` attribute of the root element.
  var rootOnload: String?
  /// The `onload` attributes of the `<image>` elements, by the index of the element among the `<image>` elements in
  /// document order.
  var imageOnloads = [Int: String]()
  /// Whether the root element waits with the class `reftest-wait`.
  var waits = false

  /// Whether the file runs scripts, or waits to be rendered.
  var isEmpty: Bool {
    scripts.isEmpty && rootOnload == nil && imageOnloads.isEmpty && !waits
  }

  /// The scripts of a file, or `nil` if it can't be read.
  init?(url: URL) {
    guard let parser = XMLParser(contentsOf: url) else { return nil }
    let reader = ScriptReader()
    parser.delegate = reader
    parser.shouldProcessNamespaces = true
    guard parser.parse() else { return nil }
    self = reader.scripts
  }

  init() {}
}

private final class ScriptReader: NSObject, XMLParserDelegate {
  var scripts = WPTScripts()
  private var depth = 0
  private var images = 0
  /// The text of the `<script>` element being read, if it has no URL.
  private var script: String?

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
    attributes: [String: String] = [:]
  ) {
    depth += 1
    if depth == 1 {
      scripts.rootOnload = attributes["onload"]
      scripts.waits = (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).contains("reftest-wait")
    }
    switch name {
    case "script" where attributes["href"] == nil && attributes["src"] == nil && attributes["xlink:href"] == nil:
      script = ""
    case "image" where namespaceURI == "http://www.w3.org/2000/svg":
      if let onload = attributes["onload"] {
        scripts.imageOnloads[images] = onload
      }
      images += 1
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    script?.append(string)
  }

  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    script?.append(String(decoding: CDATABlock, as: UTF8.self))
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    depth -= 1
    if name == "script", let text = script {
      scripts.scripts.append(text)
      script = nil
    }
  }
}

/// Runs the scripts of a file of web-platform-tests with JavaScriptCore, on the ``SVGDocument`` of a view, before
/// the view renders the file for a reftest.
///
/// JavaScriptCore parses and runs the scripts. The runner gives them the small part of the DOM that the tests use,
/// over the API of ``SVGDocument``: finding elements, their attributes, classes and inline styles, adding and
/// removing elements, the SMIL time of the document, the `load` events of the document and of `<image>` elements,
/// `requestAnimationFrame()`, `setTimeout()`, and the functions of `/common/reftest-wait.js` and
/// `/common/rendering-utils.js`.
///
/// The scripts run after the document is read, instead of while it's parsed, and the time advances by frames of
/// 16 ms, with a rendering after each frame, until the root element no longer has the class `reftest-wait`.
@MainActor
final class WPTScriptRunner {
  /// The number of frames that a file can wait for before it fails.
  static let maximumFrames = 300

  private let view: SVGUIView
  private let context: JSContext
  /// The elements that the scripts have, by their handles, which start at 1. The handle 0 is the document.
  private var elements = [SVGDocument.Element]()
  private var handles = [SVGDocument.Element: Int]()
  /// The errors of the scripts, and the other reasons why they didn't finish.
  private(set) var errors = [String]()

  init(view: SVGUIView, url: URL) {
    self.view = view
    context = JSContext()!
    context.name = url.lastPathComponent
    context.exceptionHandler = { [weak self] _, exception in
      let message = exception?.toString() ?? "unknown"
      let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "?"
      MainActor.assumeIsolated {
        self?.errors.append("line \(line): \(message)")
      }
    }
    installNative()
    context.evaluateScript(Self.prelude, withSourceURL: URL(string: "wpt-dom.js"))
  }

  /// Runs the scripts of a file, and its frames until it no longer waits, or records why it didn't finish.
  func run(_ scripts: WPTScripts, url: URL) async {
    for script in scripts.scripts {
      context.evaluateScript(script, withSourceURL: url)
    }
    let wpt = context.objectForKeyedSubscript("__wpt")!
    let imageOnloads = scripts.imageOnloads.map { [$0.key, $0.value] as [Any] }
    wpt.invokeMethod("load", withArguments: [imageOnloads, scripts.rootOnload ?? NSNull()])
    for frame in 0..<Self.maximumFrames {
      wpt.invokeMethod("frame", withArguments: [frame * 16])
      // Each frame is rendered, as a page renders its frames, so that the changes of the next frames change a
      // rendering.
      _ = try? await view.takeSnapshot(at: view.currentTime, scale: 1)
      if wpt.invokeMethod("isDone", withArguments: [])?.toBool() == true {
        return
      }
    }
    errors.append("The root element still has the class reftest-wait after \(Self.maximumFrames) frames")
  }

  private func handle(of element: SVGDocument.Element?) -> Any {
    guard let element else { return NSNull() }
    if let handle = handles[element] { return handle }
    elements.append(element)
    handles[element] = elements.count
    return elements.count
  }

  private func element(_ handle: Int) -> SVGDocument.Element? {
    handle >= 1 && handle <= elements.count ? elements[handle - 1] : nil
  }

  /// Throws an error in the script that calls a native function.
  private func throwError(_ message: String) {
    JSContext.current()?.exception = JSValue(newErrorFromMessage: message, in: JSContext.current())
  }

  private func define(_ name: String, _ block: Any) {
    context.objectForKeyedSubscript("__native").setObject(block, forKeyedSubscript: name as NSString)
  }

  private func installNative() {
    context.setObject(JSValue(newObjectIn: context), forKeyedSubscript: "__native" as NSString)
    let document = { [unowned self] in self.view.document }
    let root: @convention(block) () -> Any = { [unowned self] in handle(of: document().rootElement) }
    define("root", root)
    let byID: @convention(block) (String) -> Any = { [unowned self] id in handle(of: document().element(id: id)) }
    define("byId", byID)
    let query: @convention(block) (Int, String) -> Any = { [unowned self] scope, selector in
      do {
        let found =
          if scope == 0 {
            try document().querySelectorAll(selector)
          } else {
            try element(scope)?.querySelectorAll(selector) ?? []
          }
        return found.map { handle(of: $0) }
      } catch {
        throwError("SyntaxError: '\(selector)' isn't a valid selector")
        return [Any]()
      }
    }
    define("query", query)
    let localName: @convention(block) (Int) -> Any = { [unowned self] h in (element(h)?.localName).map { $0 as Any } ?? NSNull() }
    define("localName", localName)
    let getAttribute: @convention(block) (Int, String) -> Any = { [unowned self] h, name in
      (element(h)?.attribute(name)).map { $0 as Any } ?? NSNull()
    }
    define("getAttr", getAttribute)
    let setAttribute: @convention(block) (Int, String, String) -> Void = { [unowned self] h, name, value in
      element(h)?.setAttribute(name, to: value)
    }
    define("setAttr", setAttribute)
    let removeAttribute: @convention(block) (Int, String) -> Void = { [unowned self] h, name in
      element(h)?.removeAttribute(name)
    }
    define("removeAttr", removeAttribute)
    let classAdd: @convention(block) (Int, [String]) -> Void = { [unowned self] h, names in
      for name in names { element(h)?.classList.add(name) }
    }
    define("classAdd", classAdd)
    let classRemove: @convention(block) (Int, [String]) -> Void = { [unowned self] h, names in
      for name in names { element(h)?.classList.remove(name) }
    }
    define("classRemove", classRemove)
    let classToggle: @convention(block) (Int, String, JSValue) -> Bool = { [unowned self] h, name, force in
      element(h)?.classList.toggle(name, force: force.isBoolean ? force.toBool() : nil) ?? false
    }
    define("classToggle", classToggle)
    let classContains: @convention(block) (Int, String) -> Bool = { [unowned self] h, name in
      element(h)?.classList.contains(name) ?? false
    }
    define("classContains", classContains)
    let styleGet: @convention(block) (Int, String) -> String = { [unowned self] h, name in
      element(h)?.style.property(name) ?? ""
    }
    define("styleGet", styleGet)
    let computed: @convention(block) (Int, String) -> String = { [unowned self] h, name in
      element(h)?.computedStyle.property(name) ?? ""
    }
    define("computed", computed)
    let styleSet: @convention(block) (Int, String, String, String) -> Void = { [unowned self] h, name, value, priority in
      element(h)?.style.setProperty(name, to: value, priority: priority == "important" ? .important : .normal)
    }
    define("styleSet", styleSet)
    let styleRemove: @convention(block) (Int, String) -> Void = { [unowned self] h, name in
      element(h)?.style.removeProperty(name)
    }
    define("styleRemove", styleRemove)
    let parent: @convention(block) (Int) -> Any = { [unowned self] h in handle(of: element(h)?.parent) }
    define("parent", parent)
    let children: @convention(block) (Int) -> Any = { [unowned self] h in
      (element(h)?.children ?? []).map { handle(of: $0) }
    }
    define("children", children)
    let begin: @convention(block) (Int) -> Void = { [unowned self] h in element(h)?.beginElement() }
    define("begin", begin)
    let end: @convention(block) (Int) -> Void = { [unowned self] h in element(h)?.endElement() }
    define("end", end)
    let create: @convention(block) (String) -> Any = { [unowned self] name in
      handle(of: document().createElement(name))
    }
    define("create", create)
    let insert: @convention(block) (Int, Int, Int) -> Void = { [unowned self] parent, child, reference in
      guard let parent = element(parent), let child = element(child) else { return }
      do {
        if let reference = element(reference) {
          try parent.insert(child, before: reference)
        } else {
          try parent.append(child)
        }
      } catch {
        throwError("HierarchyRequestError: \(error)")
      }
    }
    define("insert", insert)
    let remove: @convention(block) (Int) -> Void = { [unowned self] h in element(h)?.remove() }
    define("remove", remove)
    let setCurrentTime: @convention(block) (Double) -> Void = { [unowned self] seconds in
      view.seek(to: .milliseconds(Int64((seconds * 1000).rounded())))
    }
    define("setCurrentTime", setCurrentTime)
    let currentTime: @convention(block) () -> Double = { [unowned self] in
      let (seconds, attoseconds) = view.currentTime.components
      return Double(seconds) + Double(attoseconds) / 1e18
    }
    define("currentTime", currentTime)
  }

  /// The part of the DOM that the scripts use, over the native functions of `__native`, and the frames, timers and
  /// events of a page.
  private static let prelude = #"""
    (function (global) {
      "use strict";
      const N = global.__native;
      const XLINK = "http://www.w3.org/1999/xlink";
      const XML = "http://www.w3.org/XML/1998/namespace";
      const wrappers = new Map();
      // The tasks, the timers and the callbacks of the next frame.
      let tasks = [], timers = [], frameCallbacks = [];
      let timerID = 0, now = 0, loaded = false;
      const windowListeners = [];

      function wrap(handle) {
        if (handle === null || handle === undefined) return null;
        let element = wrappers.get(handle);
        if (!element) {
          element = new Element(handle);
          wrappers.set(handle, element);
        }
        return element;
      }

      // The name of an attribute in a namespace, as the API of SVGDocument names it.
      function qualified(namespace, name) {
        const local = name.includes(":") ? name.slice(name.indexOf(":") + 1) : name;
        if (namespace === XLINK) return "xlink:" + local;
        if (namespace === XML) return "xml:" + local;
        return local;
      }

      function kebab(name) {
        return name.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
      }

      function style(handle) {
        const declaration = {
          setProperty(name, value, priority) { N.styleSet(handle, name, String(value), priority || ""); },
          getPropertyValue(name) { return N.styleGet(handle, name); },
          removeProperty(name) {
            const old = N.styleGet(handle, name);
            N.styleRemove(handle, name);
            return old;
          },
        };
        return new Proxy(declaration, {
          get(target, key) {
            if (key in target) return target[key];
            return typeof key === "string" ? N.styleGet(handle, kebab(key)) : undefined;
          },
          set(target, key, value) {
            if (typeof key !== "string") return false;
            if (value === null || value === "") N.styleRemove(handle, kebab(key));
            else N.styleSet(handle, kebab(key), String(value), "");
            return true;
          },
        });
      }

      // The style that getComputedStyle() gives, which reads the computed values and changes nothing.
      function computedStyle(handle) {
        return new Proxy({ getPropertyValue(name) { return N.computed(handle, name); } }, {
          get(target, key) {
            if (key in target) return target[key];
            return typeof key === "string" ? N.computed(handle, kebab(key)) : undefined;
          },
          set() { return false; },
        });
      }

      class ClassList {
        constructor(handle) { this.handle = handle; }
        add(...names) { N.classAdd(this.handle, names.map(String)); }
        remove(...names) { N.classRemove(this.handle, names.map(String)); }
        toggle(name, force) { return N.classToggle(this.handle, String(name), force === undefined ? null : !!force); }
        contains(name) { return N.classContains(this.handle, String(name)); }
      }

      function dispatch(target, type) {
        const event = { type, target, currentTarget: target, preventDefault() {}, stopPropagation() {} };
        if (typeof target["on" + type] === "function") target["on" + type].call(target, event);
        for (const listener of (target.listeners[type] || []).slice()) listener.call(target, event);
      }

      // A changed URL of an image is loaded, and fires a load event in a task.
      function changedImage(element, name) {
        if (element.localName !== "image" || !/^(xlink:)?href$/.test(name)) return;
        if (element.getAttribute("href") !== null || element.getAttribute("xlink:href") !== null) {
          tasks.push(() => dispatch(element, "load"));
        }
      }

      class Element {
        constructor(handle) {
          this.handle = handle;
          this.classList = new ClassList(handle);
          this.style = style(handle);
          this.listeners = {};
        }
        get localName() { return N.localName(this.handle); }
        get tagName() { return this.localName; }
        get nodeName() { return this.localName; }
        get namespaceURI() { return "http://www.w3.org/2000/svg"; }
        get id() { return N.getAttr(this.handle, "id") || ""; }
        set id(value) { N.setAttr(this.handle, "id", String(value)); }
        getAttribute(name) { return N.getAttr(this.handle, String(name)); }
        getAttributeNS(namespace, name) { return N.getAttr(this.handle, qualified(namespace, String(name))); }
        hasAttribute(name) { return this.getAttribute(name) !== null; }
        setAttribute(name, value) {
          N.setAttr(this.handle, String(name), String(value));
          changedImage(this, String(name));
        }
        setAttributeNS(namespace, name, value) {
          const qualifiedName = qualified(namespace, String(name));
          N.setAttr(this.handle, qualifiedName, String(value));
          changedImage(this, qualifiedName);
        }
        removeAttribute(name) {
          N.removeAttr(this.handle, String(name));
          changedImage(this, String(name));
        }
        removeAttributeNS(namespace, name) {
          const qualifiedName = qualified(namespace, String(name));
          N.removeAttr(this.handle, qualifiedName);
          changedImage(this, qualifiedName);
        }
        get parentNode() { return wrap(N.parent(this.handle)); }
        get parentElement() { return this.parentNode; }
        get children() { return N.children(this.handle).map(wrap); }
        appendChild(child) {
          N.insert(this.handle, child.handle, 0);
          return child;
        }
        insertBefore(child, reference) {
          N.insert(this.handle, child.handle, reference ? reference.handle : 0);
          return child;
        }
        removeChild(child) {
          if (child.parentNode !== this) throw new Error("NotFoundError: not a child");
          N.remove(child.handle);
          return child;
        }
        remove() { N.remove(this.handle); }
        querySelector(selector) { return wrap(N.query(this.handle, String(selector))[0]); }
        querySelectorAll(selector) { return N.query(this.handle, String(selector)).map(wrap); }
        getElementsByTagName(name) { return this.querySelectorAll(name); }
        getBoundingClientRect() {
          return { x: 0, y: 0, width: 0, height: 0, top: 0, left: 0, right: 0, bottom: 0 };
        }
        beginElement() { N.begin(this.handle); }
        endElement() { N.end(this.handle); }
        pauseAnimations() {}
        unpauseAnimations() {}
        setCurrentTime(seconds) { N.setCurrentTime(Number(seconds)); }
        getCurrentTime() { return N.currentTime(); }
        addEventListener(type, listener) { (this.listeners[type] = this.listeners[type] || []).push(listener); }
        removeEventListener(type, listener) {
          const listeners = this.listeners[type] || [];
          const index = listeners.indexOf(listener);
          if (index >= 0) listeners.splice(index, 1);
        }
      }

      const document = {
        get documentElement() { return wrap(N.root()); },
        getElementById(id) { return wrap(N.byId(String(id))); },
        querySelector(selector) { return wrap(N.query(0, String(selector))[0]); },
        querySelectorAll(selector) { return N.query(0, String(selector)).map(wrap); },
        getElementsByTagName(name) { return this.querySelectorAll(name); },
        createElementNS(namespace, name) {
          if (namespace !== "http://www.w3.org/2000/svg") {
            throw new Error("NotSupportedError: only SVG elements can be created");
          }
          name = String(name);
          return wrap(N.create(name.includes(":") ? name.slice(name.indexOf(":") + 1) : name));
        },
        fonts: { get ready() { return Promise.resolve(document.fonts); } },
        readyState: "complete",
        addEventListener() {},
      };

      global.window = global;
      global.document = document;
      global.requestAnimationFrame = (callback) => {
        frameCallbacks.push(callback);
        return frameCallbacks.length;
      };
      global.setTimeout = (callback, delay, ...args) => {
        timers.push({ id: ++timerID, due: now + (Number(delay) || 0), callback, args });
        return timerID;
      };
      global.clearTimeout = (id) => { timers = timers.filter((timer) => timer.id !== id); };
      global.getComputedStyle = (element) => computedStyle(element.handle);
      global.addEventListener = (type, listener) => { if (type === "load") windowListeners.push(listener); };
      // The functions of /common/reftest-wait.js and /common/rendering-utils.js.
      global.takeScreenshot = () => document.documentElement.classList.remove("reftest-wait");
      global.takeScreenshotDelayed = (delay) => setTimeout(global.takeScreenshot, delay);
      global.waitForAtLeastOneFrame = () =>
        new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));

      global.__wpt = {
        // The load events, in a task: of the images that have URLs, then of the document.
        load(imageOnloads, rootOnload) {
          const images = document.querySelectorAll("image");
          for (const [index, code] of imageOnloads) {
            if (images[index]) images[index].onload = new Function("evt", code);
          }
          const root = document.documentElement;
          if (rootOnload !== null && root) root.onload = new Function("evt", rootOnload);
          tasks.push(() => {
            for (const image of images) {
              if (image.getAttribute("href") !== null || image.getAttribute("xlink:href") !== null) {
                dispatch(image, "load");
              }
            }
            if (root) dispatch(root, "load");
            for (const listener of windowListeners) listener.call(global, { type: "load", target: document });
            loaded = true;
          });
        },
        // A frame at a time in milliseconds: the tasks, the timers that are due, and the callbacks of the frame.
        frame(time) {
          now = time;
          const current = tasks;
          tasks = [];
          for (const task of current) task();
          const due = timers.filter((timer) => timer.due <= now).sort((a, b) => a.due - b.due || a.id - b.id);
          timers = timers.filter((timer) => timer.due > now);
          for (const timer of due) timer.callback(...timer.args);
          const callbacks = frameCallbacks;
          frameCallbacks = [];
          for (const callback of callbacks) callback(now);
        },
        // Whether the document is loaded, and its root element no longer waits.
        isDone() {
          const root = document.documentElement;
          return loaded && !(root && root.classList.contains("reftest-wait"));
        },
      };
    })(this);
    """#
}

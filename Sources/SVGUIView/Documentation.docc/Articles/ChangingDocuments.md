# Changing a Document

Find the elements of the document that a view displays, and change their attributes, classes and styles from Swift.

## Overview

SVGUIView doesn't run the scripts of a document. Instead, an app reads and
changes the document of a view through ``SVGUIView/SVGUIView/document``, an
``SVGDocument``. The API follows the DOM where it fits Swift.

```swift
let document = svgView.document
if let button = document.element(id: "play") {
  button.classList.add("active")
  button.setAttribute("fill", to: "red")
  button.style.setProperty("opacity", to: "0.5")
}
```

### Finding elements

``SVGDocument/element(id:)`` finds the first element with an ID, and
``SVGDocument/querySelector(_:)`` and ``SVGDocument/querySelectorAll(_:)``
find the elements that CSS selectors match, in document order. An element has
``SVGDocument/Element/querySelector(_:)`` and
``SVGDocument/Element/querySelectorAll(_:)`` too, which find its descendants.
The searches include elements that SVGUIView doesn't render, such as `<style>`
elements and animation elements.

```swift
let squares = try document.querySelectorAll("g.squares > rect")
```

Selectors match type, class and ID selectors, attribute selectors, combinators,
the pseudo-classes of the structure of the tree, such as `:first-child` and
`:nth-child()`, and `:not()`, `:is()` and `:where()`. A selector with a
pseudo-class that depends on user actions or on the language, such as `:hover`
or `:lang()`, matches no element. Selectors that can't be parsed throw an
``SVGDocument/SelectorError``.

### Changing elements

An ``SVGDocument/Element`` reads and changes its attributes as they're written:

- ``SVGDocument/Element/attribute(_:)``,
  ``SVGDocument/Element/setAttribute(_:to:)`` and
  ``SVGDocument/Element/removeAttribute(_:)`` read, set and remove an
  attribute. Attributes are named without a namespace, and the `href` of the
  XLink namespace can also be named `xlink:href`.
- ``SVGDocument/Element/classList`` adds, removes and toggles the classes of
  the `class` attribute.
- ``SVGDocument/Element/style`` declares and removes the properties of the
  `style` attribute.

A change is visible at once to the methods that read the document. Values
aren't checked: a value that SVGUIView can't parse is ignored when the
document is rendered, as it is when the document is written with it. Elements
can't be inserted or removed.

### Showing the changes

The view shows the changes of its document at its next rendering, and the
changes made in one turn of the run loop are rendered together.
``SVGUIView/SVGUIView/takeSnapshot(rect:at:)`` includes the changes that the
view hasn't rendered yet.

Assigning new ``SVGUIView/SVGUIView/data`` to the view replaces its document.
The document that it replaces can still be read and changed, but the view no
longer shows it.

A change can start CSS animations, such as ones that a new class sets. They
play on the timeline of the document, so they run as if they started when the
document was loaded.

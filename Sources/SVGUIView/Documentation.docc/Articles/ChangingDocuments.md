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
start at the time of the change, as in a browser, while the animations that
the elements keep running play on. Removing an animation and adding it again
starts it again.

### Controlling animations

``SVGDocument/animations`` and ``SVGDocument/Element/animations`` list the CSS
animations that the elements run, as ``SVGDocument/Animation`` values. An
animation follows the Web Animations API: it plays from the time that it
starts, and ``SVGDocument/Animation/pause()``,
``SVGDocument/Animation/play()``, ``SVGDocument/Animation/currentTime`` and
``SVGDocument/Animation/playbackRate`` change how it plays from then on.
``SVGDocument/Animation/finished()`` waits until it reaches its end.

```swift
for animation in svgView.document.animations {
  animation.pause()
}
if let spin = svgView.document.element(id: "wheel")?.animations.first {
  spin.playbackRate = 2
  spin.play()
  await spin.finished()
}
```

The animations play on the timeline of the view, so they advance only while
the view plays: ``SVGUIView/SVGUIView/pause()`` holds all of them. A view
whose ``SVGUIViewConfiguration/animation`` is
``SVGUIViewConfiguration/AnimationMode/none`` displays time zero, where the
animations don't advance, but setting an animation's
``SVGDocument/Animation/currentTime`` shows it at that time.

The list doesn't include SMIL animations, which play on the timeline of the
document.

### Beginning and ending SMIL animations

A SMIL animation whose `begin` is `indefinite`, or an event that SVGUIView
doesn't have, such as `click`, never begins by itself. The element of an
animation, such as `<animate>`, begins it at the current time with
``SVGDocument/Element/beginElement()``, and ends it with
``SVGDocument/Element/endElement()``, as the DOM methods of the same names do.

```swift
svgView.document.element(id: "fade-in")?.beginElement()
```

A begin follows the animation's `restart` attribute: an animation with
`restart="whenNotActive"` doesn't begin again while it plays. The animations
whose `begin` or `end` refer to the animation, such as `fade-in.end`, follow
its new times. Elements that aren't animations do nothing. A view whose
``SVGUIViewConfiguration/animation`` is
``SVGUIViewConfiguration/AnimationMode/none`` displays time zero, so an
animation that it begins begins at time zero.

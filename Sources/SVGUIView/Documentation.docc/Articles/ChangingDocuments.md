# Changing a Document

Find the elements of the document that a view displays, change their attributes, classes and styles, and insert and remove elements from Swift.

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
document is rendered, as it is when the document is written with it.

### Changing the tree

``SVGDocument/createElement(_:)`` creates an element of the SVG namespace, and
``SVGDocument/Element/append(_:)`` and
``SVGDocument/Element/insert(_:before:)`` insert it among the children of
another element. ``SVGDocument/Element/remove()`` removes an element from its
parent, with its descendants.

```swift
let circle = document.createElement("circle")
circle.setAttribute("cx", to: "50")
circle.setAttribute("cy", to: "50")
circle.setAttribute("r", to: "10")
try document.rootElement?.append(circle)

// Later, take the circle out of the document.
circle.remove()
```

``SVGDocument/Element/parent`` and ``SVGDocument/Element/children`` walk the
tree. Inserting an element that has a parent moves it, and since an element is
painted over the siblings before it, moving an element among its siblings
changes what covers what:

```swift
// Bring the shape to the front, or send it to the back.
try shape.parent?.append(shape)
try shape.parent?.insert(shape, before: shape.parent?.children.first)
```

An element that isn't in the tree, because it was created and not inserted
yet or because it was removed, is read and changed as any other element, with
its descendants, so a group can be made with its children before it's
inserted. ``SVGDocument/Element/isConnected`` tells whether an element is in
the tree. The view shows only the elements of the tree, and the searches of
the document find only them.

The document keeps the elements that are removed, so that an element can be
inserted again as the same element, such as to undo its removal. They take
memory until the document is released.

Inserting an element where it can't be throws an
``SVGDocument/HierarchyError``: in itself or in one of its descendants, in an
element of another document, or before an element that isn't a child of the
parent. The root element stays where it is.

An inserted element starts the CSS animations that its styles give it at the
time that it's inserted, and starts no transitions, also when it was removed
and is inserted again. SMIL animation elements can be inserted and removed as
other elements, and play on the timeline of the document.

### Changing text and style sheets

``SVGDocument/Element/textContent`` reads the character data of an element and
its descendants, such as the text of a `<text>` element. Setting it replaces
the children of the element with the text, as the DOM does, and the document
keeps the removed children as it keeps other removed elements.

```swift
score.textContent = "Score: \(points)"
```

The style sheets of the document come from its `<style>` elements in the tree.
Inserting or removing a `<style>` element, or changing its text or its `type`,
makes the style sheets again, as a browser does. A change of the style sheets
cascades every element of the document again, which takes as long as giving
the view new data, so change attributes or classes to change a few elements.
The change starts the transitions of the values that it changes, and the
animations that it starts start at the time of the change. A style sheet that
reads files with `@import` reads them again at the next rendering.

### Showing the changes

The view shows the changes of its document at its next rendering, and the
changes made in one turn of the run loop are rendered together.
``SVGUIView/SVGUIView/takeSnapshot(rect:at:scale:)`` includes the changes that the
view hasn't rendered yet.

A change doesn't stop the rendering in progress: the view shows it, and then
renders the latest document. So an app that changes the document at every frame,
such as while a finger drags a shape, sees renderings even when rendering the
document takes longer than a frame.

Changes that follow one another within a short time are continuous changes.
While they last, the view shows the document in layers, as it shows playing
animations: an element whose `transform` attribute changes moves its layer, and
only the layers of the elements whose painting changes are painted again. When
the document stops changing, the view shows one image again, as a snapshot
renders it. So dragging a shape doesn't paint the rest of the document again,
while the pixels of a still view stay those of a snapshot.

Assigning new ``SVGUIView/SVGUIView/data`` to the view, or giving it to
``SVGUIView/SVGUIView/setData(_:)``, replaces its document.
The document that it replaces can still be read and changed, but the view no
longer shows it.

A change can start CSS animations, such as ones that a new class sets. They
start at the time of the change, as in a browser, while the animations that
the elements keep running play on. Removing an animation and adding it again
starts it again.

### Starting transitions

A change starts CSS transitions of the properties whose values it changes, as
the `transition` properties of the elements give. The transitions start at the
time of the change, from the values that the elements show then, and the
changes made in one turn of the run loop start them together.

```swift
// With `#box { transition: transform 1s }` and a `.moved` class that sets the
// transform, the box moves to its new place in one second.
svgView.document.element(id: "box")?.classList.add("moved")
```

Changing a value back while its transition runs reverses the transition from
where it is, and changing it to another value starts a new transition from
there, as in a browser. A change of a value that an animation changes starts
no transition.

An element that isn't rendered, because its `display` or that of an ancestor
is `none`, has no transitions: a change that hides it cancels them, and a
change that shows it again shows the new values at once. A transition of
`display` with `transition-behavior: allow-discrete` keeps the element rendered
until it ends, so that its other transitions, such as one of `opacity`, can
play before it disappears.

A view whose ``SVGUIViewConfiguration/animation`` is
``SVGUIViewConfiguration/AnimationMode/none``, or that holds its animations
because Reduce Motion is on, shows the new values at once and starts no
transitions. The transitions play on the timeline of the view, so they advance
only while the view plays. ``SVGDocument/animations`` doesn't list them.

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

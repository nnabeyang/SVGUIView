# Changing a Document

Find the elements of the document that a view displays, change their attributes, classes and styles, insert and remove elements, read their shapes, and find the elements at a point from Swift.

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
  attribute. Attributes are named without a namespace, except the `href` of
  the XLink namespace, which is named `xlink:href`. It's a separate attribute
  from `href`, as in SVG 2: an element that has both uses `href`, and uses
  `xlink:href` once `href` is removed. An attribute that the document can't
  write as XML isn't set, as a parsed document doesn't have one: a name with
  another prefix, such as `foo:bar`, `xmlns` and the names with its prefix,
  and a name that isn't a name of XML.
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
parent, with its descendants. An element with a name that isn't a name of XML,
such as `foo:bar` or `has space`, is created, but it isn't rendered, and the
document isn't written with it or its descendants, so that the written SVG can
be read again. A `use` element that references one of its descendants shows
nothing in the document that is read from it.

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

### Reading computed values

An inspector of an editing app shows the values that a selected element is
drawn with, such as its fill and the width of its stroke, wherever they come
from. ``SVGDocument/Element/computedStyle`` reads them, as the DOM's
`getComputedStyle()` does: the values after the style sheets, the
presentation attributes, the `style` attribute and inheritance are applied.

```swift
let fill = rect.computedStyle.property("fill")  // "rgb(255, 0, 0)"
let width = rect.computedStyle.property("stroke-width")  // "2px"
```

The values are written as browsers write them, so an app can show them as it
shows the values of a browser:

- Colors are `rgb()` or `rgba()`, with `currentcolor` resolved to the color
  that it is.
- Absolute lengths and lengths in `em` are in pixels. A percentage stays a
  percentage, since it's resolved where it's used, such as against the
  viewport of a `width`.
- Numbers have at most six significant digits, such as `0.707107`.
- A `transform` is the `matrix()` of its functions.

The values are the ones at the time that the view displays, with its
animations then, and a change of the document is visible at once. Style
sheets in other files apply once the view has read them, which it does when
it renders the document. An element that isn't in the document's tree, and a
property that SVGUIView doesn't support, such as `line-height`, have no value.

### Reading the shapes of elements

An app that edits a document draws over the view, such as the frame and the
handles of the shape that a finger selected. Three methods read what it needs,
as the DOM's `getBBox()` and `getScreenCTM()` do:

- ``SVGDocument/Element/boundingBox(includingStroke:)`` reads the bounding box
  of an element in its user space, with or without its stroke.
- ``SVGDocument/Element/path()`` reads its shape, such as the path of a
  `<path>` element or the rounded rectangle of a `<rect>`, in the same
  coordinates.
- ``SVGDocument/Element/transformToView()`` reads the transform from those
  coordinates to the coordinates of the view, with the transforms of the
  element and its ancestors, the view boxes, and how the view places the
  document with its `contentMode`.

A `<tspan>` element has the box of the cells of its glyphs and the outlines of
its glyphs, as a `<text>` element does, in the coordinates of its `<text>`
element.

```swift
guard let box = await shape.boundingBox(includingStroke: true),
  let transform = await shape.transformToView()
else { return }
// A layer over the view outlines the shape.
selectionLayer.path = CGPath(rect: box, transform: [transform])
```

The methods read the document with every change made so far, at the time that
the view displays, without waiting for a rendering, so they read a shape
that was moved just before. They find the geometry off the main actor, as a
rendering does, and return `nil` for an element that the view doesn't show,
such as one that was removed, and for an element that isn't a graphics
element, such as a `<mask>`. As SVG 2 has it, an element that isn't rendered,
such as one in a `<defs>` element or with `display: none`, has the geometry
that it would have if it were rendered. The geometry depends on the size and
the content mode of the view, so read it again when they change.

### Editing text

An app that edits text, such as text that a person adds to a picture, puts a
caret between its characters and selects them. ``SVGDocument/Element/textLayout()``
reads where the characters of a `<text>` element, or of a `<tspan>` in it, are,
as the DOM's `getStartPositionOfChar()`, `getExtentOfChar()` and
`getCharNumAtPosition()` find them:

```swift
// Puts the caret where a finger tapped the text.
if let layout = await text.textLayout(),
  var transform = await text.transformToView() {
  let point = touch.location(in: svgView).applying(transform.inverted())
  caret = layout.insertionIndex(closestTo: point)
  caretLayer.path = layout.caretPath(at: caret)?.copy(using: &transform)
}
```

The layout has the characters that the text renders and, for each of them,
where it starts and ends on the baseline, the box of its cell and its angle, in
the user space of the text. ``SVGDocument/TextLayout/characterIndex(at:)``
finds the character at a point, and
``SVGDocument/TextLayout/insertionIndex(closestTo:)`` the position between
characters that's closest to it, which can be between the characters of a
ligature.

The characters are the ones after the white space is processed, and each
`Character` of Swift is one, so an emoji is one character. With
`white-space: pre`, or `xml:space="preserve"`, the white space stays as it is,
so the characters of a `<text>` element without spans are the ones of its
``SVGDocument/Element/textContent``, and the positions between them are the
ones of the string that the app changes. The layout is found off the main
actor, as a rendering is, so read it again after changing the text.

### Typing text

A person types into a `<text>` element of the document as into a text field:
``SVGUIView/SVGUIView/beginTextEditing(of:selecting:)`` makes the view the first
responder, shows the keyboard, and shows the caret, the selection with its
handles, the loupe and the edit menu over the text. Text that the keyboard
composes, such as Japanese before it's converted, is shown in the text,
underlined, until it's committed.

```swift
// Adds a text where a finger tapped, and lets the person type into it.
let text = svgView.document.createElement("text")
text.setAttribute("x", to: "\(point.x)")
text.setAttribute("y", to: "\(point.y)")
text.setAttribute("font-size", to: "32")
try svgView.document.rootElement?.append(text)
svgView.textEditingDelegate = self
await svgView.beginTextEditing(of: text)
```

A tap outside the text, ``SVGUIView/SVGUIView/endTextEditing()`` and new data
end the editing. The ``SVGUIView/SVGUIView/textEditingDelegate`` hears when the
editing begins and ends, and each change of the text with the styled text before
it, which an app registers to undo:

```swift
func svgView(
  _ view: SVGUIView, didChangeTextOf element: SVGDocument.Element,
  fromStyledText oldText: SVGStyledText
) {
  undoManager?.registerUndo(withTarget: element) { $0.setStyledText(oldText) }
}

func svgViewDidEndTextEditing(_ view: SVGUIView, element: SVGDocument.Element) {
  // A text that the person left empty is removed.
  if element.textContent.isEmpty { element.remove() }
}
```

The text is a `<text>` element with character data and `<tspan>` elements of
runs, or with `<tspan>` elements that are its lines of them, each line with an
`x` attribute, or a `y` attribute in vertical text. The `<tspan>` of a run has
no position attributes, such as `dx`, and no child elements. Other text, such
as text with spans that move their characters, isn't edited. The editing sets
`xml:space="preserve"`, so that the spaces that the person types are kept, and
writes a text of more than one line as `<tspan>` elements, each `1.2em` after
the one before it, as other editors write it. The style of the whole text, such
as its fill, font and `text-anchor`, is changed with its attributes and its
style, as the style of any element is.

### Formatting ranges of text

A range of the text that a person types into can have attributes of its own,
such as bold or another color.
``SVGUIView/SVGUIView/setTextAttribute(_:to:in:)`` sets an attribute of the
selection, and the characters are written as a `<tspan>` element with the
attribute. Without a selection, the attribute is for the characters that are
typed next. Typed characters take the attributes of the character before them.
``SVGUIView/SVGUIView/textAttributes(in:)`` gives the attributes that the
selection has, which an app shows in its controls:

```swift
@objc func bold() {
  let isBold = svgView.textAttributes()["font-weight"] == "bold"
  svgView.setTextAttribute("font-weight", to: isBold ? nil : "bold")
}
// <text x="10" y="50">Hello, <tspan font-weight="bold">world</tspan></text>
```

With ``SVGUIView/SVGUIView/allowsEditingTextAttributes``, a person also toggles
bold, italic and underline with the edit menu and with ⌘B, ⌘I and ⌘U of a
keyboard. ``SVGDocument/Element/styledText`` reads the text with the
attributes of its runs as an ``SVGStyledText``, and
``SVGDocument/Element/setStyledText(_:)`` writes it, which undoes a change. `SVGView` doesn't edit text: a SwiftUI app that
edits text wraps an ``SVGUIView/SVGUIView`` in a `UIViewRepresentable` of its
own.

### Measuring shapes

An app places things along a shape, or lets a finger slide along it, with
two methods that measure a `<path>` element or a basic shape, such as a
`<circle>`, as the DOM's `getTotalLength()` and `getPointAtLength()` do:

- ``SVGDocument/Element/totalLength()`` reads the length of the shape.
- ``SVGDocument/Element/point(atLength:)`` reads the point at a length along
  the shape from its start, and the angle of the direction that the shape
  goes in there.

```swift
// Places a mark at the middle of a path, turned along it.
if let length = path.totalLength(),
  let point = path.point(atLength: length / 2) {
  mark.setAttribute(
    "transform",
    to: "translate(\(point.location.x) \(point.location.y)) rotate(\(point.angle * 180 / .pi))")
}
```

The points are in the user space of the shape, as the shapes that
``SVGDocument/Element/path()`` reads are. The `pathLength` attribute of the
shape doesn't change the lengths, as it doesn't in the DOM. A basic shape
starts and goes as SVG 2 specifies its path: a `<circle>` starts at the right
of its center and goes clockwise. The curves are measured as text on a path
and motion along a path measure them, as many short lines, so the length of
a curve differs a little from its exact length.

Unlike the methods that read the geometry, the two methods return at once.
They measure the shape on the main actor, with every change made so far, at
the time that the view displays. Its percentages are resolved with the size
of the view, so they return `nil` for an element that the view doesn't show,
and for an element that isn't a `<path>` element or a basic shape.

### Finding the element at a point

``SVGDocument/element(at:tolerance:)`` finds the frontmost element at a point
of the view, as the DOM's `elementFromPoint()` does, and
``SVGDocument/elements(at:tolerance:)`` finds every element there from the
front, such as to pick the shape under the one that a finger selected. A
tolerance in points of the view lets a finger pick a thin line or a small
shape near the point.

```swift
let point = touch.location(in: svgView)
guard let shape = await svgView.document.element(at: point, tolerance: 8)
else { return }
// Outline the shape that the finger picked.
if let box = await shape.boundingBox(includingStroke: true),
  let transform = await shape.transformToView() {
  selectionLayer.path = CGPath(rect: box, transform: [transform])
}
```

As SVG 2 hit-tests the targets of pointer events, an element is hit where its
fill and its stroke paint, while it's visible, and its `pointer-events`
property chooses other areas: `all` hits a shape over its fill and its stroke
whatever they paint, and `none` makes an element, such as a decoration over
the shapes, never hit, so that the shapes under it are. Text is hit over the
cells of its glyphs, as the `text` or the `tspan` element of the glyph, and
the content of a `<use>` element as the `<use>` element. Clip paths limit where
an element is hit, while its opacity, its filter and its mask don't, and the
markers of a shape aren't hit, as in browsers.

```swift
// Selection handles drawn in the document don't hide the shapes under them.
handles.style.setProperty("pointer-events", to: "none")
```

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
only the layers of the elements whose painting changes are painted again.
Inserting, removing or moving an element, or changing the character data of a
text, likewise paints again only the layers of the elements that it changes.
When the document stops changing, the view shows one image again, as a snapshot
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

### Dragging an element

The view renders a change off the main thread and shows it a frame or more
after the app makes it, so a shape that follows a finger through the document
trails behind it. An app that edits shapes moves a stand-in layer instead,
which follows the finger in the same frame, and lets the document catch up.

``SVGDocument/Element/takeSnapshot(scale:)`` renders an element and its
descendants into an image for the stand-in, with the frame in the coordinates
of the view where the view shows it. Hide the element while the stand-in is
shown, and change the document as the finger moves:

```swift
// When the drag begins.
guard let snapshot = try await shape.takeSnapshot() else { return }
standIn.contents = snapshot.image
standIn.frame = snapshot.frame
svgView.layer.addSublayer(standIn)
shape.setAttribute("visibility", to: "hidden")

// As the finger moves.
standIn.position = position
shape.setAttribute("transform", to: "translate(\(x) \(y))")
```

The image has the element's own transform, clip path, mask, opacity and filter,
and the transforms of its ancestors, but not the opacities, clip paths, masks
and filters of its ancestors, or the other elements, so that the stand-in is
the element alone.

When the drag ends, show the element again, and remove the stand-in when
``SVGUIView/SVGUIView/waitUntilDisplayed()`` returns. It returns when the view
has put a rendering of the changes made until then into its layer, so the
stand-in goes in the same Core Animation transaction as the element comes,
and neither a gap nor both of them show:

```swift
shape.removeAttribute("visibility")
await svgView.waitUntilDisplayed()
standIn.removeFromSuperlayer()
```

### Saving a document

``SVGDocument/svgData()`` writes the document with every change made so far
as SVG, which an app saves to a file or shares, and which a view shows again as
it shows the document now.

```swift
// Shares the drawing as an SVG file, such as to the Files app.
ShareLink(
  item: Drawing(data: view.document.svgData()),
  preview: SharePreview("Drawing.svg"))
```

It writes the elements of the document with their attributes as written,
the style sheets of `<style>` elements, and the text of `<text>`, `<title>` and
`<desc>` elements. An element of another namespace, such as the content of a
`<foreignObject>`, keeps its namespace. What parsing left out isn't written:
comments, the document type declaration, and the attributes of other
namespaces, such as the ones that an editor adds. The values that SMIL
animations give attributes aren't written, while the animation elements are.
A reference to another file, such as the `href` of an `<image>`, is written as
it is, so a relative one refers to a file next to where the document is saved.

### Copying and pasting elements

``SVGDocument/Element/svgData()`` writes an element and its descendants as an
SVG document that renders them alone, which an app puts on the pasteboard.
``SVGDocument/Element/append(svgData:)`` and
``SVGDocument/Element/insert(svgData:before:)`` insert the elements of SVG
data into a document, which an app takes from the pasteboard:

```swift
// Copies the selected shape.
UIPasteboard.general.setData(shape.svgData(), forPasteboardType: UTType.svg.identifier)

// Pastes it into a layer, in this document or in another one.
if let data = UIPasteboard.general.data(forPasteboardType: UTType.svg.identifier) {
  let pasted = try layer.append(svgData: data)
  select(pasted)
}
```

The written document has the elements that the element references, such as
the gradient of its `fill`, its clip path or the element that a `<use>` shows,
in a `<defs>` element, so that it renders the same in another document or in
another app. Its root has the size and the view box of the root element. The
element is in the user space of its parent: the transforms of its ancestors
aren't written, nor the rules of the style sheets, which apply only where the
same rules do.

Pasting the data inserts the `<defs>` element and the element. The data can
also be SVG elements written one after another, without namespace
declarations, such as `<rect width="10" height="10"/><circle r="5"/>`. The
identifiers of the inserted elements are kept as they are, also where the
document already has them, as the DOM keeps them: a reference finds the first
element with the identifier in document order, so pasting the same element
twice renders the same, and an app that wants the copies apart changes their
`id` attributes. A `<style>` element that the data has applies its rules to the
whole document. Data that isn't well-formed XML throws
``SVGDocument/SVGDataError`` and changes nothing.

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

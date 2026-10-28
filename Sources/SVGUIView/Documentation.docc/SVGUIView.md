# ``SVGUIView``

Display an SVG image in a UIKit view.

## Overview

``SVGUIView/SVGUIView`` parses SVG data and draws it into its layer. Rendering runs
in a background task, so parsing and drawing a large document does not block
the main thread.

```swift
let url = Bundle.main.url(forResource: "example", withExtension: "svg")!
let svgView = SVGUIView(contentsOf: url)!
view.addSubview(svgView)
```

The view sizes itself to the SVG document's `width` and `height` when you create
it with ``SVGUIView/SVGUIView/init(data:)`` or
``SVGUIView/SVGUIView/init(contentsOf:)``, and reports the same size as its
intrinsic content size. The view's `contentMode` decides how the document's
viewport is fitted into the view's bounds.

To show a different image, assign new data to ``SVGUIView/SVGUIView/data``. The
view parses it and redraws asynchronously.

```swift
svgView.data = try Data(contentsOf: anotherURL)
```

### Controlling rendering

``SVGUIViewConfiguration`` sets the priority of the background rendering task
and how long a single rendering may take before it is cancelled, which is 10
seconds by default.

```swift
svgView.configuration = SVGUIViewConfiguration(
  taskPriority: .high,
  timeoutDuration: .seconds(2)
)
```

When a rendering takes longer than the timeout, or the memory for its image
couldn't be allocated, the view keeps the image that it shows.

### Taking a snapshot

``SVGUIView/SVGUIView/takeSnapshot(rect:at:)`` renders the current document into a
`UIImage` without changing what the view displays. It throws an
``SVGRenderingError`` when the document has no root `svg` element, the rectangle
to render into has no width or no height, rendering times out, the task that
waits for the snapshot is cancelled, or the memory for the image couldn't be
allocated.

```swift
do {
  let image = try await svgView.takeSnapshot()
} catch .timedOut {
  // Rendering took longer than the configuration's timeout.
} catch .cancelled {
  // The task that waited for the snapshot was cancelled.
} catch .allocationFailed {
  // The memory for the image couldn't be allocated, such as for a rectangle
  // that is too large.
} catch {
  // There is nothing to render: the document has no root `svg` element, or the
  // rectangle has no width or no height.
}
```

A snapshot can show a document at a time of its animations: CSS animations,
which are the `@keyframes` rules and the `animation-*` properties, and the SMIL
animation elements `<animate>`, `<set>`, `<animateTransform>` and
`<animateMotion>`. The time starts at zero when the document is loaded, and a
view that doesn't play its animations displays the document at time zero. A
document without animations looks the same at any time. SMIL begin and end
times that depend on user events, access keys or the wall clock never come, and
`<animateColor>` is ignored.

```swift
let image = try await svgView.takeSnapshot(at: .seconds(1.5))
```

### Playing animations

A view plays the animations of its document when its configuration's
``SVGUIViewConfiguration/animation`` is
``SVGUIViewConfiguration/AnimationMode/play``. With
``SVGUIViewConfiguration/AnimationMode/paused``, it holds them at their current
time until ``SVGUIView/SVGUIView/play()`` is called. The default,
``SVGUIViewConfiguration/AnimationMode/none``, displays time zero, so updating
the package doesn't start the animations in an app.

```swift
svgView.configuration = SVGUIViewConfiguration(animation: .play)
svgView.pause()
svgView.seek(to: .seconds(1.5))
svgView.play()
print(svgView.currentTime)
```

The animations don't advance while the view isn't in a window, is hidden or
has no size, or while the app is in the background, and they stop after the
time at which the document doesn't change any more. While Reduce Motion is on,
the view displays time zero, unless
``SVGUIViewConfiguration/playsWithReduceMotion`` is `true` for animations that
are essential to the content.

While it can play animations, the view shows its document in layers of its
layer, so that a change of the transform or the opacity of an element only
moves or fades its layer. Snapshots are still rendered into one image.

### Changing the document

``SVGUIView/SVGUIView/document`` finds the elements of the document, and
changes their attributes, classes and styles. The view shows the changes at its
next rendering. See <doc:ChangingDocuments>.

```swift
svgView.document.element(id: "play")?.classList.add("active")
```

## Topics

### Displaying SVG

- ``SVGUIView/SVGUIView``

### Changing the document

- <doc:ChangingDocuments>
- ``SVGDocument``

### Configuring rendering

- ``SVGUIViewConfiguration``
- ``SVGRenderingError``

### Design

- <doc:AnimationArchitecture>

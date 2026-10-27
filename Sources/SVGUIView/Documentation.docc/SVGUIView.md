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
`<animateMotion>`. The time starts at zero when the document is loaded, and the
view displays the document at time zero. A document without animations looks
the same at any time. SMIL begin and end times that depend on user events,
access keys or the wall clock never come, and `<animateColor>` is ignored.

```swift
let image = try await svgView.takeSnapshot(at: .seconds(1.5))
```

## Topics

### Displaying SVG

- ``SVGUIView/SVGUIView``

### Configuring rendering

- ``SVGUIViewConfiguration``
- ``SVGRenderingError``

### Design

- <doc:AnimationArchitecture>

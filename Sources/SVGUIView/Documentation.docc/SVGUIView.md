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
and how long a single rendering may take before it is cancelled.

```swift
svgView.configuration = SVGUIViewConfiguration(
  taskPriority: .high,
  timeoutDuration: .seconds(2)
)
```

When a rendering takes longer than the timeout, the view keeps the image that it
shows.

### Taking a snapshot

``SVGUIView/SVGUIView/takeSnapshot(rect:)`` renders the current document into a
`UIImage` without changing what the view displays. It throws an
``SVGRenderingError`` when the document has no root `svg` element, the rectangle
to render into has no width or no height, rendering times out, or the task that
waits for the snapshot is cancelled.

```swift
do {
  let image = try await svgView.takeSnapshot()
} catch .timedOut {
  // Rendering took longer than the configuration's timeout.
} catch .cancelled {
  // The task that waited for the snapshot was cancelled.
} catch {
  // There is nothing to render: the document has no root `svg` element, or the
  // rectangle has no width or no height.
}
```

## Topics

### Displaying SVG

- ``SVGUIView/SVGUIView``

### Configuring rendering

- ``SVGUIViewConfiguration``
- ``SVGRenderingError``

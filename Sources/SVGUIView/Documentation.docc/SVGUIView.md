# ``SVGUIView``

Display an SVG image in a UIKit view.

## Overview

``SVGUIView/SVGUIView`` parses SVG data and draws it into its layer. Rendering runs
in a background task, so drawing a large document does not block the main
thread. ``SVGUIView/SVGUIView/setData(_:)`` parses the data in the background
too.

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
view parses it at once and redraws asynchronously.

```swift
svgView.data = try Data(contentsOf: anotherURL)
```

Parsing a larger document takes longer, and assigning ``SVGUIView/SVGUIView/data``
parses it on the main actor. ``SVGUIView/SVGUIView/setData(_:)`` parses the data
off the main actor instead, and shows it when it's parsed, unless newer data is
given meanwhile:

```swift
Task {
  await svgView.setData(try Data(contentsOf: anotherURL))
}
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

### Reading other files

A document can show the image files that it refers to by relative URLs, such
as `<image href="images/photo.png">` and the `<feImage>` of a filter, and the
elements of other SVG files that `<use>` elements show, such as
`<use href="icons.svg#star"/>`. It also reads the style sheets that its
`@import` rules and `xml-stylesheet` processing instructions refer to, and the
fonts of its `@font-face` rules, such as WOFF files, before its first
rendering. The fonts are used only by the document. An image file is a bitmap or an SVG image,
which, as in a browser, reads no other files itself. The URLs are relative to the view's
``SVGUIView/SVGUIView/baseURL``: the URL that
``SVGUIView/SVGUIView/init(contentsOf:)`` reads the document from, or the one
given with the data:

```swift
let view = SVGUIView(data: data, baseURL: url)
await view.setData(otherData, baseURL: otherURL)
```

Data that's set as ``SVGUIView/SVGUIView/data`` has no base URL, and reads no
other files. By default, a view reads only the files in the folder of the
document and in the folders inside it, so a URL such as `../image.png` isn't
read, and a symbolic link doesn't lead outside the folder either. The
configuration's ``SVGUIViewConfiguration/externalResources`` reads the files
in another folder, or none:

```swift
svgView.configuration = SVGUIViewConfiguration(externalResources: .none)
```

A view doesn't read the network. Reading the files takes part of the time of a
rendering, which the configuration's timeout limits. It reads each file once
for a document, until it's given other data.

### Taking a snapshot

``SVGUIView/SVGUIView/takeSnapshot(rect:at:scale:)`` renders the current document into a
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
times that depend on user events, access keys or the wall clock never come by
themselves, and `<animateColor>` is ignored.

```swift
let image = try await svgView.takeSnapshot(at: .seconds(1.5))
```

A snapshot is rendered at the scale of the view's screen by default, or of the
main screen for a view that isn't on one, and at another scale for an image of
a given size in pixels.
``SVGUIView/SVGUIView/takeCGImageSnapshot(rect:at:scale:)`` renders the same
image as a `CGImage`, such as for the frames of a video. A view renders without
being on the screen, into the rectangle that it's given.
``SVGDocument/animationEnd`` is the time after which the document looks the
same, which ends the frames:

```swift
let view = SVGUIView(data: data)
let rect = CGRect(x: 0, y: 0, width: 320, height: 320)
if let end = view.document.animationEnd {
  var time = Duration.zero
  while time <= end {
    let frame = try await view.takeCGImageSnapshot(rect: rect, at: time, scale: 2)
    // Append the frame of 640 by 640 pixels to the video.
    time += .milliseconds(40)
  }
}
```

### Playing animations

A view plays the animations of its document by default, when its
configuration's ``SVGUIViewConfiguration/animation`` is
``SVGUIViewConfiguration/AnimationMode/play``, except while Reduce Motion is on.
With ``SVGUIViewConfiguration/AnimationMode/paused``, it holds them at their
current time until ``SVGUIView/SVGUIView/play()`` is called. With
``SVGUIViewConfiguration/AnimationMode/none``, it displays time zero, as a still
image.

```swift
svgView.configuration = SVGUIViewConfiguration(animation: .none)
```

The view controls the animations that it plays:

```swift
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

While its animations play, the view shows its document in layers of its layer,
so that a change of the transform or the opacity of an element only moves or
fades its layer. While they don't, such as when they're paused or have ended,
the view shows the image that a snapshot of the time shows.

### Changing the document

``SVGUIView/SVGUIView/document`` finds the elements of the document, and
changes their attributes, classes and styles. The view shows the changes at its
next rendering, and a change starts the CSS transitions of the values that it
changes. The document also controls the CSS animations, and begins and ends
the SMIL animations, such as the ones that would begin with a click in a
browser. See <doc:ChangingDocuments>.

```swift
svgView.document.element(id: "play")?.classList.add("active")
```

### Following the specifications

SVGUIView renders documents as SVG 2 and the CSS specifications describe them,
and decides what they leave open by the text of the specifications, the tests,
and the behavior of browsers. See <doc:FollowingSpecifications> for the order
of those rules and for the features that SVGUIView doesn't support.

## Topics

### Displaying SVG

- ``SVGUIView/SVGUIView``

### Changing the document

- <doc:ChangingDocuments>
- ``SVGDocument``
- ``SVGDocument/Element``
- ``SVGDocument/Animation``

### Configuring rendering

- ``SVGUIViewConfiguration``
- ``ExternalResources``
- ``SVGRenderingError``

### Rendering

- <doc:FollowingSpecifications>

### Design

- <doc:AnimationArchitecture>

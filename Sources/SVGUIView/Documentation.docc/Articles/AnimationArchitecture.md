# Animation Architecture

How SVGUIView plays CSS Animations, CSS Transitions and SMIL animations in SVG documents.

## Overview

SVGUIView draws an SVG document as a still image, and plays the animations in
it. This article describes how the package is built for both: the stages that a
document goes through to be rendered, how animations change its values over
time, and how a view shows the frames. Each section also notes the reasons for
its design.

### Scope

SVGUIView follows [SVG 2](https://www.w3.org/TR/SVG2/). For animation, that
means it supports:

- **CSS Animations:** `@keyframes` rules and the `animation-*` properties.
- **CSS Transitions:** the `transition-*` properties.
- **SMIL animation:** the `<animate>`, `<set>`, `<animateTransform>` and
  `<animateMotion>` elements.

JavaScript is out of scope. `<script>` elements and event handler attributes,
such as `onclick`, are ignored. Instead, a Swift API lets an app read and change
the document: it can change attributes, styles and classes, and control
animations. Changing the document through this API starts CSS Transitions, which
otherwise would have nothing to trigger them.

The public views are ``SVGUIView/SVGUIView`` and `SVGView`. An app turns
playback on through the view's configuration, and a view that doesn't play
animations draws a still image.

## Module structure

The code is split into targets, so that computing what to draw is separate from
the two ways of drawing it.

```
            _CSSParser   _SelectorParser
                 \            /
                  \          /
                   SVGCore
                  /        \
                 /          \
        SVGRenderCG      SVGRenderLayer
                 \          /
                  \        /
                  SVGUIView
                      |
                   SVGView
```

| Target | Role |
|---|---|
| `SVGCore` | Parsing, the document tree, the cascade and computed values, the timeline, timing and interpolation, and the render tree. It uses Core Graphics and Core Text for geometry and text layout, but not UIKit. |
| `SVGRenderCG` | Paints a render tree into a `CGContext`. It produces still images, and the contents of individual layers for `SVGRenderLayer`. Filters are implemented with Core Graphics and vImage. |
| `SVGRenderLayer` | Plans the layers that show a render tree and the bounds that their contents cover, paints their contents with `SVGRenderCG`, and updates a tree of `CALayer` objects with them. It runs the filters of the layers that paint only an element with a filter on Metal. |
| `SVGUIView` | The public `UIView`. It draws still images with `SVGRenderCG`, and plays animations with `SVGRenderLayer`. It owns the document and the clock of its animations. |
| `SVGView` | The SwiftUI wrapper of ``SVGUIView/SVGUIView``. |

Design notes:

- The targets other than `SVGUIView` and `SVGView` aren't products, and
  `SVGUIView` doesn't re-export `SVGCore`. The targets use each other's
  declarations with `package` access, and the types that apps use, such as the
  document API, are declared in `SVGUIView`, so `import SVGUIView` is enough. A
  separate `SVGCore` product can be added if someone needs it without UIKit.
- The fonts of text styles, such as `UICTFontTextStyleBody`, come from UIKit,
  so `SVGUIView` passes them to `SVGCore` before it parses a document.
- The private interfaces in `_SPI`, `_ICU` and `_CShims` are used by the code
  that needs them, which is mostly text layout in `SVGCore`.
- There is one view for both still images and playback, and the renderer is
  chosen inside it.

## Rendering pipeline

Rendering is split into four stages. Each stage produces a value that the next
stage reads, so a change only has to redo the stages it affects.

```
document tree ──▶ styles ──▶ render tree ──▶ painting
  (DOM)         cascaded →     geometry,       Core Graphics
                computed →     transforms,     or layers
                animated       paint
```

### Document tree

The document tree holds the parsed elements, their attributes as written, the
style sheets and an index from IDs to elements.

It's a persistent tree: nodes are immutable values, and a change copies only the
path from the changed node to the root. A snapshot of the document is therefore
a reference to its current root. It's `Sendable`, costs nothing to take, and
stays valid while the document keeps changing. Background work always reads a
snapshot, never the live document.

Elements that the renderer doesn't support stay in the tree, so that selectors
such as `:nth-child()` and sibling combinators see the same structure as in a
browser.

### Styles

Style resolution produces three sets of values for each element:

- **Cascaded values:** the winning declaration for each property, chosen
  from presentation attributes, style sheets and the `style` attribute. As in
  SVG 2, presentation attributes take part in the cascade as author declarations
  with a specificity of zero.
- **Computed values:** cascaded values with inheritance and initial values
  applied, and units resolved as far as they can be without layout.
- **Animated values:** computed values with the animations that are active
  at the current time applied on top. See <doc:#Combining-animations>.

Every property is described once in a property registry: its parser, its
initial value, whether it's inherited, and how it's animated. Adding a property
to the cascade is adding an entry to the registry. The cascade covers every
property that SVGUIView supports, and inheritance is resolved with the styles,
not while drawing.

Selector matching supports type, class and ID selectors, combinators, attribute
selectors, the pseudo-classes of the structure of the tree, such as `:root` and
`:nth-child()`, and `:not()`, `:is()` and `:where()`. A selector with a
pseudo-class that depends on user actions or the language, such as `:hover` or
`:lang()`, matches no element. Of the at-rules, only `@keyframes` rules are
read, and they're kept with the document.

### Render tree

The render tree holds what painting needs and nothing more: the geometry of each
shape as a path, transforms, resolved paint servers, and the clip paths, masks
and filters, resolved for the elements that use them. Text is laid out here, and
its glyphs become a path. Each `<use>` element is expanded into its own copy of
the referenced content, so that the copy can be styled and animated separately.

Render tree nodes are immutable `Sendable` values. Each node keeps the identity
of the element it came from, which lets a renderer match a new render tree with
the previous one. Since rendering builds an immutable render tree and paints
it, no drawing state is shared between renderings.

### Painting

Painting is done by one of the two renderers. See <doc:#Rendering-strategies>.

### Invalidation

A new animation frame redoes only part of the work of the frame before it:

- **Styles:** Only the elements that animations can change, which are the
  ones that run CSS animations, that SMIL animations change or that have
  transitions, and their descendants, get their computed values computed again.
  Every other subtree is the same as in the frame before. A document whose SMIL
  animations change attributes that aren't properties makes every element again
  from the cascade. When the values are the same as in the frame before, nothing
  else is done for the frame.
- **Render tree and layers:** The render tree and the plan of its layers are
  made again for every frame.
- **Painting:** Only the layers that contain an element whose painting changes
  are painted again. An element whose `transform` or `opacity` is the only thing
  that changes keeps its contents, and only the properties of its layer change.
  An animation inside a clip path, a mask, a pattern, a gradient or a filter
  changes the elements that use it, directly or through other resources, so
  only their layers are painted again. A moving element with a filter keeps its
  contents while the filter doesn't change.

A change made through the document API makes again only the elements whose
computed values it can change: the changed elements and their descendants, plus
their following siblings and theirs when the style sheets use sibling
combinators. Their ancestors are copied with the new children, and every other
element is shared with the document before the change.
The view then renders the whole document again, and paints every layer again,
as it does for a new size. The animations and transitions that the change
starts play in the frames after it like any other animation.

Finer invalidation is added only when measurements show the need, such as an
index of the classes and attributes that selectors use, or painting again only
the layers whose painting a change affects, and only updating the properties
of a layer whose `transform` or `opacity` is the only thing that changes.

## Animation model

CSS Animations and CSS Transitions are both defined on top of the
[Web Animations](https://www.w3.org/TR/web-animations-1/) model, and SMIL
animation fits the same model well. SVGUIView implements that model once, and
each kind of animation translates into it.

### Parsing

- **CSS:** The CSS parser parses `@keyframes` rules, the `animation` and
  `transition` shorthands, and their longhand properties. Keyframes keep their
  per-keyframe `animation-timing-function`.
- **SMIL:** The parser builds animation elements for `<animate>`, `<set>`,
  `<animateTransform>` and `<animateMotion>` (with `<mpath>`). It reads the
  target (`href` or the parent element), `attributeName`, `from`, `to`, `by`,
  `values`, `keyTimes`, `keySplines`, `keyPoints`, `calcMode`, `additive`,
  `accumulate`, `begin`, `end`, `dur`, `repeatCount`, `repeatDur`, `min`, `max`,
  `restart` and `fill`. `<animateColor>`, which SVG 2 removed, is ignored, and
  `<animate>` animates colors instead.

### Timing model

All animations in a document share one timeline. Its time starts at zero when
the document is loaded and advances only while the document plays. Seeking sets
the time directly.

Each animation has timing values in Web Animations terms: a start delay, an
iteration duration, an iteration count and start, a direction, a fill mode and
an easing function. From the timeline's time, the timing model computes the
animation's phase (before, active or after), the current iteration and the
progress within it.

The two kinds of CSS animation map to these values directly. SMIL needs one more
step, because an element's timing can depend on other elements:

- A scheduler resolves `begin` and `end` lists, including references to other
  animations such as `other.end+1s`, into a sequence of intervals. Each interval
  is then played with the shared timing model, so easing and fill work the same
  way as in CSS.
- `fill="freeze"` maps to a forwards fill. `repeatCount` maps to the iteration
  count, and `repeatDur`, `min` and `max` limit the active duration.
- Begin and end values that depend on what SVGUIView doesn't have never
  resolve, the same as `indefinite`: user events such as `click`, because there
  are no user events without JavaScript, `accessKey()`, `wallclock()`, and the
  repeats of other animations, such as `a.repeat(2)`. The app can begin and end
  an animation through the Swift API instead, with
  ``SVGDocument/Element/beginElement()`` and
  ``SVGDocument/Element/endElement()``, which add the times of the view to the
  begin and end lists as the DOM methods do.

Easing functions include `linear`, the `ease` keywords, `cubic-bezier()`,
`steps()` and `linear()`. SMIL's `calcMode="spline"` uses the same Bézier curve
code, `calcMode="discrete"` uses the discrete step, and `calcMode="paced"` uses
the distance function of the animated type.

### Combining animations

More than one animation can affect the same property of an element. The values
are combined in this order, from lowest to highest priority:

1. Values from the cascade (presentation attributes, then style sheets and the
   `style` attribute)
2. SMIL animations
3. CSS Animations
4. Important declarations (`!important`)
5. CSS Transitions

Within SMIL, animations are combined as described by the SMIL "sandwich" model:
an animation that began later wins, and document order breaks ties. `additive`
and `accumulate` add to the value underneath. Within CSS Animations, an
animation that comes later in `animation-name` wins.

SMIL animations of attributes that aren't properties, such as `x` on `<text>` or
`viewBox`, change the attribute's value before style resolution.

### Interpolation

Every animatable type conforms to one protocol:

```swift
protocol Animatable: Sendable {
  /// The value at `progress` between `self` and `other`, or `nil` when the two
  /// values can't be interpolated and the animation falls back to a discrete
  /// step.
  func interpolated(to other: Self, progress: Double) -> Self?
  /// The sum used by additive and accumulating animations.
  func adding(_ other: Self) -> Self?
  /// The distance used by `calcMode="paced"`.
  func pacedDistance(to other: Self) -> Double?
}
```

| Type | Interpolation |
|---|---|
| Numbers, opacity | Linear |
| Lengths and percentages | Linear. Mixed units are kept as a length and a percentage until layout. |
| Colors | In premultiplied sRGB, as CSS Color 4 specifies for legacy color syntax |
| Paint (`fill`, `stroke`) | Colors are interpolated. A change to or from a paint server is discrete. |
| Transform lists | Function by function when the lists match. Otherwise, by decomposing the matrices. |
| `transform-origin` | As two lengths |
| `d` and `points` | Command by command when the paths have the same structure. Otherwise, discrete. `points` isn't a property yet, so it isn't animated. |
| `stroke-dasharray` | Element by element, after repeating both lists to a common length |
| `visibility`, `display` and other keywords | Discrete, with the CSS rules for `visibility` |

Design notes:

- One timing model is shared by all three kinds of animation.
- SMIL animations are below CSS Animations in the priority order, as in WebKit,
  Chrome and Firefox, which were checked with test documents.

## Document API

Without JavaScript, an app changes the document through a Swift API. Its design
follows the DOM and Web Animations APIs where they fit Swift, so that people who
know the web find their way around.

```swift
let document = svgView.document
if let button = document.element(id: "play") {
  button.classList.add("active")           // can start CSS Transitions
  button.setAttribute("fill", to: "red")
}
for animation in document.animations {
  animation.pause()
}
```

The surface is:

- **Finding elements:** ``SVGDocument/element(id:)``,
  ``SVGDocument/querySelector(_:)`` and ``SVGDocument/querySelectorAll(_:)``
  on the document and on elements. See <doc:ChangingDocuments>.
- **Changing elements:** reading, setting and removing attributes,
  changing the `style` attribute's declarations, and adding, removing and
  toggling classes. A change starts the CSS Transitions of the values that it
  changes. Elements can't be inserted or removed yet.
- **Controlling animations:** the CSS animations of the document or of one
  element, each with ``SVGDocument/Animation/play()``,
  ``SVGDocument/Animation/pause()``, ``SVGDocument/Animation/currentTime``,
  ``SVGDocument/Animation/playbackRate`` and
  ``SVGDocument/Animation/finished()``. A CSS animation that a change starts
  starts at the time of the change. SMIL animations are begun and ended from
  their elements with ``SVGDocument/Element/beginElement()`` and
  ``SVGDocument/Element/endElement()``, which replaces event-based begin values.

Design notes:

- The document and its elements are isolated to the main actor, like the view.
  Rendering reads snapshots, so it never waits for the main actor.
- Changes are rendered at the next frame, not immediately, while reading the
  document sees them at once. Several changes made in one turn of the run loop
  produce one restyle, and transitions start from the values that were current
  before the first change.
- New animations can't be created from Swift, like `Element.animate()` in Web
  Animations.
- The element type is nested in the document type, such as `SVGDocument.Element`,
  so that it doesn't clash with the names used inside the package.

## Public API

```swift
svgView.configuration = SVGUIViewConfiguration(animation: .play)
svgView.pause()
svgView.seek(to: .seconds(1.5))
let frame = try await svgView.takeSnapshot(at: .seconds(2))
```

- **Animation mode:** ``SVGUIViewConfiguration/animation`` has three cases.
  ``SVGUIViewConfiguration/AnimationMode/none`` draws a still image.
  ``SVGUIViewConfiguration/AnimationMode/play`` plays animations with the layer
  renderer. ``SVGUIViewConfiguration/AnimationMode/paused`` uses the layer
  renderer but holds the timeline at its current time.
- **Controlling the timeline:** ``SVGUIView/SVGUIView/play()``,
  ``SVGUIView/SVGUIView/pause()``, ``SVGUIView/SVGUIView/seek(to:)`` and
  ``SVGUIView/SVGUIView/currentTime``. Times are `Duration` values, like
  ``SVGUIViewConfiguration/timeoutDuration``.
- **Reduce Motion:** ``SVGUIViewConfiguration/playsWithReduceMotion`` lets an
  app play animations that are essential to its content while Reduce Motion is
  on. See <doc:#Pausing-playback>.
- **Rendering a given time:** ``SVGUIView/SVGUIView/takeSnapshot(rect:at:)``
  takes a time, so that any frame can be rendered as an image with the same
  method as other snapshots.
- **Reaching the document:** ``SVGUIView/SVGUIView/document`` is the
  document API. Assigning new ``SVGUIView/SVGUIView/data`` replaces the
  document.
- **SwiftUI:** `SVGView` reads the animation mode from the same
  configuration in the environment.

Design notes:

- `.none` is the default, so that a document with animations doesn't start
  moving in an app that doesn't ask for it.
- With `.none`, a document that contains animations is drawn as it looks at time
  zero, so an animation that sets a different value at its start changes the
  still image too.

## Rendering strategies

### Still images

`.none` and snapshots render the whole render tree into one bitmap with
`SVGRenderCG`. A still image doesn't need layers, and a rendering that
doesn't play animations does no work for them.

### Playback with layers

`.play` and `.paused` render into a tree of `CALayer` objects under the view's
layer. The tree is built so that the common animations don't repaint anything:

- An element gets its own layer when its `transform` or `opacity` is
  animated. The layer has the transform and the opacity, and its contents are
  the element painted without them.
- The elements around such an element that contain it, such as groups, viewports
  and `<use>` elements, become layers too, with their transforms and opacities,
  so that the layers are composited as the elements are.
- An element with a clip path, a mask or a filter composites what it paints as
  one image, so the elements in it are painted with it into one layer, and none
  of them gets a layer of its own, even when it's animated. A layer of its own
  would only clip, mask or filter what's in it, which painting it whole does as
  well.
- An element whose filter paints differently over time is painted into a layer
  of its own. This happens when the values of the filter's primitives are
  animated, or when the elements that it filters change. Only that layer is
  painted again in each frame, and not the content around the element, and its
  filter runs on the GPU. See <doc:#Filters-on-Metal>. An element whose filter
  doesn't change is painted with the content around it.
- Neighboring content that doesn't need a layer is painted together into one
  layer by `SVGRenderCG`. A document without animations becomes a single layer.
- A change of `transform` or `opacity` only sets the layer's property. Nothing
  is repainted, the same way browsers run such animations on the compositor.
- Any other change paints again only the layers that contain the changed
  elements. See <doc:#Invalidation>.
- The pixels of the contents of a layer lie on the pixels of the screen as the
  layer is without the transforms that animations change. A layer that doesn't
  move shows the same pixels as a still image. Where an animation rotates a
  layer, or moves it between the pixels of the screen, the screen resamples its
  contents, which changes the antialiased edges.

The clock is a `CADisplayLink`. Each frame advances the timeline to the link's
target timestamp, and the layers of that time are set inside a `CATransaction`
with actions disabled, so that Core Animation's implicit animations don't
interfere. The clock stops after the frame that passes the time after which the
document doesn't change, so a view whose animations have ended does no work.
The animations aren't converted to `CAKeyframeAnimation` objects: those can't
express every timing function, SMIL timing or animations that depend on other
animations, and they would make the visible frame hard to reproduce in a
snapshot.

A frame whose animated values are the same as those of the frame that the view
shows isn't rendered: after the computed values at its time, it compares them
and the attributes that SMIL animations change with the frame before, and keeps
the layers that the view shows. So while only discrete animations are running,
such as `steps()` or `<set>`, or an animation waits for its delay, a view
renders only the frames where a value changes. The display link still runs at
the frame rate of the display, which isn't lowered.

## Concurrency

- **Main actor:** the document, the document API, the timeline and the
  display link. Each frame advances the timeline on the main actor and starts
  the background work for its time.
- **Background tasks:** the computed values at the time, the render tree, the
  plan of the layers and the painting of their contents. They read a document
  snapshot and the time, which are `Sendable` values.
- **Back on the main actor:** new layer contents and changes to the layer
  tree are applied together in one transaction.

Painting has no state of its own to share. The painter reads the render tree,
which is `Sendable`, and draws into a bitmap that its task creates. Values that
rendering reads from the main actor, such as the screen scale, are passed in
when rendering starts.

## Frame budget and timeouts

``SVGUIViewConfiguration/timeoutDuration`` applies to still images and
snapshots: a rendering that takes longer is cancelled. It also limits the first
rendering when playback starts.

During playback, nothing is cancelled. When the background work for a frame
isn't finished by the next frame, the view keeps showing the previous frame and
starts the next work from the latest time, skipping the frames in between.
`transform` and `opacity` changes are computed with the rest of a frame, in the
background.

## Pausing playback

Playback stops in these cases, and the timeline doesn't advance while it's
stopped:

- **Reduce Motion:** When `UIAccessibility.isReduceMotionEnabled` is on, a
  view that plays animations shows the frame at time zero and doesn't start. An
  app can opt out with ``SVGUIViewConfiguration/playsWithReduceMotion`` for
  animations that are essential to its content. The view observes the setting
  and reacts when it changes.
- **Background:** When the app moves to the background, the display link
  is stopped. Playback resumes where it stopped when the app returns.
- **Not visible:** When the view isn't in a window, is hidden, or has a
  zero size, the display link is stopped.

Stopping the timeline, instead of letting it run, keeps the animation from
jumping when it resumes, and keeps a view that nobody can see from doing work.
The clock also stops when the animations have ended, and runs again when the
view seeks back before their end.

## Filters on Metal

A view that plays animations runs on the GPU the filters of the layers that
paint only an element with a filter. Such a layer is the layer of an element
whose filter paints differently over time, or the layer of a moving element
with a filter. Still images, snapshots and the frames rendered while the app is
in the background run the filters on the CPU with Core Graphics and vImage.

- `MetalFilterRenderer` in `SVGRenderLayer` runs the same steps as the CPU for
  each primitive, so that the results are the same up to the rounding. Each
  primitive draws into a cleared image of the filter region with the opacity of
  the element, clipped to its subregion, and converts the color spaces where
  the CPU does. The color conversions and the opacity are looked up in tables
  that Core Graphics and vImage make, so that they round as on the CPU.
- A Gaussian blur uses a Gaussian kernel where its standard deviation is
  smaller than 7 pixels, and the three box blurs of the specification from 7
  pixels, both on the CPU and on the GPU, with the same kernels. Where the size
  of the boxes is even, the two boxes that are offset by half a pixel are blurred
  as one centered tent. The boxes and the tents on the GPU are those of Metal
  Performance Shaders, and the Gaussian kernels are compute shaders. Outside the
  filter region, a blur takes transparent black.
- The GPU doesn't run the filters whose results it can't make the same, which
  run on the CPU instead:
  - A filter region or a subregion whose edges, or a `feOffset` whose distance,
    aren't on the pixels. The CPU resamples the image of the filter for them.
  - A `feBlend` or a `feMerge` whose subregion isn't the filter region, whose
    inputs the CPU scales into the subregion.
  - The blend modes that Core Graphics computes differently from the formulas
    of the specification.
  - A blur whose standard deviations differ, and that blurs a direction with
    three boxes.
  - A filter region too large for a texture.
- The element is painted with Core Graphics into memory that the GPU reads, and
  the result is read from memory that the GPU writes, so the pixels aren't
  copied on the CPU. The result is drawn into the contents of the layer as the
  CPU draws it.
- The layers of a frame whose filters run on the GPU are painted at the same
  time, as each other and as the other layers, so that the waits for the GPU
  overlap. Each wait is longer than the work of the GPU for a small filter, so
  waiting for one layer after another would take longer than running the
  filters on the CPU.
- The kernels are compiled from their source when the renderer is made, in the
  first frame that runs a filter on the GPU, so building the package doesn't
  need the Metal toolchain.
- No GPU work is submitted while the app is in the background, because iOS
  doesn't allow it. A frame whose GPU work fails runs its filters on the CPU.
- In the benchmark document with filters, whose blurs change, running them on
  the GPU makes the frames shorter, and takes about half the time of the CPU.

Design notes:

- The GPU runs a filter only where its result is the same as on the CPU, so
  that a view that plays animations shows what a snapshot shows. Still images
  run the filters on the CPU, since they're rendered in the background as well.
- Only the filters of the layers of their own elements run on the GPU. A filter
  that doesn't change is painted with the content around it once, so running it
  on the GPU would only add a layer.
- The renderer isn't prepared before the first frame that needs it. Making it
  takes only about as long as two frames, so preparing it in the background and
  running the filters on the CPU until it's ready would make the first frames
  longer in total.
- Every device that runs iOS 18 supports Metal. Without a GPU, such as in some
  virtual machines, the filters run on the CPU.

## Testing and evaluation

Animations are evaluated in two ways: whether the values are right, and whether
playback is smooth.

### Correct values

- **Unit tests of the model:** Timing, easing, interpolation and the
  combination order are functions from a time to a value. They're tested
  without rendering, using parameterized tests in Swift Testing, with extra
  cases at the edges: just before and after a delay, at iteration boundaries,
  for each fill mode, and at each step of `steps()`.
- **Snapshots at given times:** Because a time fully decides the output,
  ``SVGUIView/SVGUIView/takeSnapshot(rect:at:)`` with a time gives stable
  snapshots. Each test document is captured at a few times, such as 0, 0.5 and
  1 second.
- **Checking against a browser:** Reference images are recorded from
  SVGUIView, after its renderings are compared with WebKit holding the same
  document at the same time. The viewer of the test app holds CSS animations
  with `document.getAnimations()` and their `currentTime`, and SMIL animations
  with `pauseAnimations()` and `setCurrentTime()`. The times are chosen away
  from the times where a value changes, because `setCurrentTime()` can land a
  little before or after them. WebKit is a reference, not a target: a
  difference is decided by the specifications. The script runs only in the test
  app, never in the package.
- **Agreement between renderers:** For the same time, the image from
  `SVGRenderCG` and the image of the layer tree from `SVGRenderLayer` must
  match. This keeps playback from looking different from snapshots. Layers that
  don't move show the same pixels as the image, also under a transform that
  scales the axes differently, since their contents have the pixels of the
  screen along each axis. The edges of a viewport's clip and of the cells of a
  pattern that fall between pixels still differ slightly. Moving layers differ
  only at their antialiased edges, where the screen resamples them. Layers that
  frames reuse show the same pixels as layers painted again.
- **Filters on the GPU against the CPU:** The tests of the package run the
  filters of test documents on the GPU and on the CPU, and compare their
  results. The test app renders the layers of the documents of the test suite
  with filters twice, with the filters on the GPU and on the CPU, after giving
  every element with a filter a layer of its own so that its filter can run on
  the GPU, and compares them. The snapshot tests can't check the GPU, since
  still images run the filters on the CPU.
- **Playback with a test clock:** The renderer takes its clock as a
  dependency. Tests replace the display link with a clock they advance by hand,
  then check layer properties. Playing, pausing, seeking and the conditions in
  <doc:#Pausing-playback> are tested this way without depending on real time.

The W3C SVG 1.1 test suite contains SMIL tests (`animate-elem-*`). The ones
that SVGUIView renders correctly are part of the snapshot tests, each captured
at times chosen for that document. The others are left out until what they
also depend on, such as text or `<animateColor>`, renders correctly. The official
tests for CSS Animations and CSS Transitions in web-platform-tests mostly check
results with JavaScript, so they're used as a guide for writing new test
documents instead.

### Smooth playback

- A set of benchmark documents covers different kinds of work: transforms only,
  changing path shapes, many elements, and filters.
- The time of each rendering is recorded as a "Render" signpost interval, with
  its stages as "Style", "Build", "Plan" and "Paint" intervals in it, and a frame
  that a slower rendering skips is a "Skipped frame" event. Running a filter on
  the GPU is a "Filter on GPU" interval in "Paint", with the size of the filter
  region, and making the renderer is a "Prepare GPU filters" interval. The
  benchmarks of the test app measure the renderings and the time of the CPU
  with XCTest metrics, only when `TEST_RUNNER_RUN_BENCHMARKS` is `1`. They run
  in the Release configuration, as apps are built, since the Debug
  configuration takes many times longer.
- Performance is measured on devices. Simulators and Xcode Cloud, which only
  runs simulators, don't reflect device performance, so performance isn't a
  pass-or-fail check in CI. Instruments' animation hitches template is used to
  find dropped frames.
- The benchmarks also render still images, so that a change for playback
  doesn't make still images slower.

### Visual review

The viewer of the snapshot test app plays a document in SVGUIView and in a
`WKWebView` from the start, side by side or in the same place, to catch stutter
and flicker that numbers and snapshots miss. Its animation controls make the
same changes of classes and the same operations on CSS animations in both
views, so that the animations and transitions that changes start can be
compared too.

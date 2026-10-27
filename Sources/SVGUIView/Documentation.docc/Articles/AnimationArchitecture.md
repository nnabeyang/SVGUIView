# Animation Architecture

The planned design for playing CSS Animations, CSS Transitions and SMIL animations in SVG documents.

## Overview

> Important: This article describes work that is partly planned. Phase 0,
> which splits the code into `SVGCore` and `SVGRenderCG` and into the stages of
> the rendering pipeline, is done. Phase 1 is done too: CSS Animations are
> parsed and applied to the computed values at a time, and
> ``SVGUIView/SVGUIView/takeSnapshot(rect:at:)`` renders that time. Phase 1.5
> is done as well: the `<animate>`, `<set>`, `<animateTransform>` and
> `<animateMotion>` elements apply to properties and attributes at the same
> times. Phase 2 is done too: a view plays animations in a tree of layers that
> `SVGRenderLayer` makes. The document API, CSS Transitions and filters on Metal
> are planned: the types, properties and methods proposed for them don't exist
> yet, and their names may change while the work goes on.

SVGUIView draws an SVG document as a still image. This article describes how it
will be extended to play animations, and records the decisions made for the
work. Each section ends with the decisions it makes, and <doc:#Open-questions>
lists what is still undecided. <doc:#Implementation-phases> shows which phases
are done.

### Scope

SVGUIView follows [SVG 2](https://www.w3.org/TR/SVG2/). For animation, that
means all of the following are in scope:

- **CSS Animations:** `@keyframes` rules and the `animation-*` properties.
- **CSS Transitions:** the `transition-*` properties.
- **SMIL animation:** the `<animate>`, `<set>`, `<animateTransform>` and
  `<animateMotion>` elements.

JavaScript is out of scope. `<script>` elements and event handler attributes,
such as `onclick`, are ignored. Instead, a Swift API lets an app read and change
the document: it can change attributes, styles and classes, and control
animations. Changing the document through this API starts CSS Transitions, which
otherwise would have nothing to trigger them.

The public views stay ``SVGUIView/SVGUIView`` and `SVGView`. An app turns
playback on through the view's configuration, and a view that doesn't play
animations behaves as it does today.

## Current design and its limits

Before phase 0, the design assumed that a document never changes after it's
parsed. This section records its limits, and which of them phase 0 removed.

- **Styles were fixed when the document was parsed.** The parser built a tree
  of immutable element objects. The cascade picked one declaration per property
  for each element and built a new element object with the result. Nothing
  recorded which declarations an element's values came from, so a value couldn't
  change over time. Phase 0 removed this limit: the document tree is persistent,
  and each element keeps its cascaded values, from which its computed values are
  resolved.
- **Only a few properties took part in the cascade.** Style sheets and the
  `style` attribute could set 13 properties: `fill`, `fill-opacity`, `stroke`,
  `stroke-width`, `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit`,
  `transform`, `clip-path`, `x`, `y`, `width` and `height`. Every other property,
  such as `opacity`, `display` or `filter`, could only be set as a presentation
  attribute. Inherited values were resolved while drawing, through stacks in
  `SVGContext`. Phase 0 removed this limit: the cascade covers every property
  that SVGUIView supports, and inherited values are computed with the styles.
- **Drawing state was shared through an unchecked type.** `SVGContext` was
  marked `@unchecked Sendable` and held reference-type stacks. Code was correct
  only because a rendering used its context from one task at a time. Phase 0
  removed this limit: rendering builds an immutable render tree and paints it,
  so no drawing state is shared, and `SVGContext` is gone.
- **At-rules are dropped.** The CSS parser doesn't parse any at-rule, so
  `@keyframes` rules are lost. Selector matching supports type, class and ID
  selectors and combinators, but not pseudo-classes. Phase 1 removed this limit
  for `@keyframes`: the rules are parsed and kept with the document. Other
  at-rules are still dropped, and pseudo-classes still aren't supported.
- **Every update redraws the whole document.** Drawing renders the entire
  tree into one bitmap, which becomes the contents of the view's layer. Nothing
  is cached between renderings, and a rendering that takes longer than
  ``SVGUIViewConfiguration/timeoutDuration`` (10 seconds by default) is
  cancelled. A frame of an animation has to be ready in about 16 milliseconds,
  or 8 milliseconds at 120 Hz. Phase 2 removed this limit for playback: a view
  that plays animations shows them in layers, and paints again only the layers
  that change. Still images and snapshots are still rendered into one bitmap.
- **Filters run on the CPU.** Filter primitives are implemented with Core
  Graphics and vImage. This remains until phase 3.

Animation needs the opposite assumptions: values that depend on time and on
changes made through the API, and redrawing only what changed.

## Module structure

The work stays in this package. Its code is split into new targets, so that
computing what to draw is separate from the two ways of drawing it.

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
| `SVGCore` | Parsing, the document tree, the cascade and computed values, and the render tree. From phase 1, also the timeline, timing and interpolation. It uses Core Graphics and Core Text for geometry and text layout, but not UIKit. |
| `SVGRenderCG` | Paints a render tree into a `CGContext`. It produces still images, and the contents of individual layers for `SVGRenderLayer`. Filters keep their Core Graphics and vImage implementations. |
| `SVGRenderLayer` | Plans the layers that show a render tree and the bounds that their contents cover, paints their contents with `SVGRenderCG`, and updates a tree of `CALayer` objects with them. From phase 3, filters that run on Metal live here. |
| `SVGUIView` | The public `UIView`. It draws still images with `SVGRenderCG`, and plays animations with `SVGRenderLayer`. It owns the document and the clock of its animations. |
| `SVGView` | The SwiftUI wrapper of ``SVGUIView/SVGUIView``. |

Phase 0 added `SVGCore` and `SVGRenderCG`, and phase 2 added `SVGRenderLayer`.

Decisions:

- The new targets aren't products, and `SVGUIView` doesn't re-export
  `SVGCore`. The targets use each other's declarations with `package` access,
  and the types that apps use, such as the document API, are declared in
  `SVGUIView`, so `import SVGUIView` stays enough. A separate `SVGCore` product
  can be added if someone needs it without UIKit.
- The fonts of text styles, such as `UICTFontTextStyleBody`, come from UIKit,
  so `SVGUIView` passes them to `SVGCore` before it parses a document.
- The private interfaces in `_SPI`, `_ICU` and `_CShims` are used by the code
  that needs them, which is mostly text layout in `SVGCore`.
- The existing branch that adds separate Metal-backed views isn't continued.
  There is one view, and the renderer is chosen inside it.

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
  at the current time applied on top. They come with phase 1. See
  <doc:#Combining-animations>.

Every property is described once in a property registry: its parser, its
initial value and whether it's inherited. Adding a property to the cascade is
adding an entry to the registry. From phase 1, the registry also says how a
property is animated.

Inheritance is resolved with the styles, not while drawing.

### Render tree

The render tree holds what painting needs and nothing more: the geometry of each
shape as a path, transforms, resolved paint servers, and the clip paths, masks
and filters, resolved for the elements that use them. Text is laid out here, and
its glyphs become a path. Each `<use>` element is expanded into its own copy of
the referenced content, so that the copy can be styled and animated separately.

Render tree nodes are immutable `Sendable` values. Each node keeps the identity
of the element it came from, which lets a renderer match a new render tree with
the previous one.

### Painting

Painting is done by one of the two renderers. See <doc:#Rendering-strategies>.

### Invalidation

A new animation frame redoes only part of the work of the frame before it:

- **Styles:** Only the elements that animations can change, which are the
  ones that run CSS animations or that SMIL animations change, and their
  descendants, get their computed values computed again. Every other subtree is
  the same as in the frame before. A document whose SMIL animations change
  attributes that aren't properties makes every element again from the cascade.
- **Render tree and layers:** The render tree and the plan of its layers are
  made again for every frame.
- **Painting:** Only the layers that contain an element whose painting changes
  are painted again. An element whose `transform` or `opacity` is the only thing
  that changes keeps its contents, and only the properties of its layer change.
  An animation inside a clip path, a mask, a pattern, a gradient or a filter
  changes the elements that use it, which can't be told, so every layer is
  painted again then.

Phase 2.5 adds changes made through the document API. Such a change marks what
has to be recomputed, and the amount of work depends on what changed:

| What changed | Recomputed |
|---|---|
| A class, ID or attribute that a selector depends on | Styles of the affected elements and their descendants |
| A property that affects geometry, such as `d`, `x` or `font-size` | The render tree nodes of the affected elements |
| A paint property, such as `fill` or `stroke` | Painting of the affected layers only |
| `transform` or `opacity` | Nothing is repainted. The layer's property is updated. |

The first version restyles the changed element's subtree, plus its following
siblings when the style sheets use sibling combinators. Finer invalidation, such
as an index of the classes and attributes that selectors use, is added only when
measurements show the need.

## Animation model

CSS Animations and CSS Transitions are both defined on top of the
[Web Animations](https://www.w3.org/TR/web-animations-1/) model, and SMIL
animation fits the same model well. SVGUIView implements that model once, and
each kind of animation translates into it.

### Parsing

- **CSS:** The CSS parser learns to parse `@keyframes` rules, the `animation`
  and `transition` shorthands, and their longhand properties. Keyframes keep
  their per-keyframe `animation-timing-function`.
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
  repeats of other animations, such as `a.repeat(2)`. From phase 2.5, the app
  can begin and end an animation through the Swift API instead.

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

Decisions:

- One timing model is shared by all three kinds of animation.
- The priority order above applies. SMIL animations are below CSS Animations,
  as in WebKit, Chrome and Firefox, which were checked with test documents.

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

The planned surface is:

- **Finding elements:** `element(id:)`, `querySelector(_:)` and
  `querySelectorAll(_:)` on the document and on elements.
- **Changing elements:** reading, setting and removing attributes,
  changing the `style` attribute's declarations, and adding, removing and
  toggling classes. Inserting and removing elements comes later.
- **Controlling animations:** the animations of the document or of one
  element, each with `play()`, `pause()`, `currentTime`, `playbackRate` and a way
  to wait until it finishes. SMIL animations can also be begun and ended, which
  replaces event-based begin values.

Decisions:

- The document and its elements are isolated to the main actor, like the view.
  Rendering reads snapshots, so it never waits for the main actor.
- Changes are applied at the next frame, not immediately. Several changes made in
  one turn of the run loop produce one restyle, and transitions start from the
  values that were current before the first change.
- Creating new animations from Swift, like `Element.animate()` in Web
  Animations, isn't part of the first version.
- The element type is nested in the document type, such as `SVGDocument.Element`,
  so that it doesn't clash with the names used inside the package.

## Public API

The existing API stays source compatible. New API is added next to it:

```swift
svgView.configuration = SVGUIViewConfiguration(animation: .play)
svgView.pause()
svgView.seek(to: .seconds(1.5))
let frame = try await svgView.takeSnapshot(at: .seconds(2))
```

- **Animation mode:** ``SVGUIViewConfiguration/animation`` has three cases.
  ``SVGUIViewConfiguration/AnimationMode/none`` draws a still image with the
  existing renderer. ``SVGUIViewConfiguration/AnimationMode/play`` plays
  animations with the layer renderer.
  ``SVGUIViewConfiguration/AnimationMode/paused`` uses the layer renderer but
  holds the timeline at its current time.
- **Controlling the timeline:** ``SVGUIView/SVGUIView/play()``,
  ``SVGUIView/SVGUIView/pause()``, ``SVGUIView/SVGUIView/seek(to:)`` and
  ``SVGUIView/SVGUIView/currentTime``. Times are `Duration` values, like
  ``SVGUIViewConfiguration/timeoutDuration``.
- **Reduce Motion:** ``SVGUIViewConfiguration/playsWithReduceMotion`` lets an
  app play animations that are essential to its content while Reduce Motion is
  on. See <doc:#Pausing-playback>.
- **Rendering a given time:** ``SVGUIView/SVGUIView/takeSnapshot(rect:at:)``
  takes a time, so that any frame can be rendered as an image. This is what the
  planned `render(at:)` API became, because it keeps one method for snapshots.
- **Reaching the document:** In phase 2.5, ``SVGUIView/SVGUIView`` gains a
  `document` property for the document API. Assigning new
  ``SVGUIView/SVGUIView/data`` replaces the document.
- **SwiftUI:** `SVGView` reads the animation mode from the same
  configuration in the environment.

Decisions:

- `.none` stays the default while animation support is new, so updating the
  package doesn't start animations in existing apps.
- With `.none`, a document that contains animations is drawn as it looks at time
  zero. Today animation elements are ignored, so this changes the output of
  those documents, for example when an animation sets a different value at its
  start. Documents without animations are drawn exactly as before.

## Rendering strategies

### Still images

`.none` and snapshots render the whole render tree into one bitmap with
`SVGRenderCG`, as today. A still image doesn't need layers, and keeping this path
means apps that don't play animations see no change in output or performance.

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
  of them gets a layer of its own, even when it's animated. The design first
  gave such an element a layer of its own whether or not it's animated, but a
  layer would only clip, mask or filter what's in it, which painting it whole
  does as well.
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
Converting animations to `CAKeyframeAnimation` objects was considered and
rejected: it can't express every timing function, SMIL timing or animations
that depend on other animations, and it would make the visible frame hard to
reproduce in a snapshot.

When only discrete animations are running, such as `steps()` or `<set>`, the
display link's preferred frame rate is to be lowered to what the animations
need. This isn't done yet: such a view renders every frame.

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

``SVGUIViewConfiguration/timeoutDuration`` keeps its meaning for still images and
snapshots: a rendering that takes longer is cancelled. It also limits the first
rendering when playback starts.

During playback, nothing is cancelled. When the background work for a frame
isn't finished by the next frame, the view keeps showing the previous frame and
starts the next work from the latest time, skipping the frames in between.

Two parts of the design aren't done yet. `transform` and `opacity` changes are
to be applied without waiting for background work, so that they keep moving even
when repainting falls behind. Today they're computed with the rest of a frame,
in the background. And when frames are skipped repeatedly, the display link's
frame rate is to be lowered.

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

Filters move to Metal in the layer renderer, while still images keep the vImage
implementation until the Metal one produces the same results.

- The minimum is `MTLGPUFamily.apple3`. Every device that runs iOS 16 belongs to
  this family or a later one, so there's no fallback for missing Metal support.
- Gaussian blur uses Metal Performance Shaders, as in the earlier
  `feature/metal-filter-acceleration` work. The other primitives use compute
  shaders.
- No GPU work is submitted while the app is in the background, because iOS
  doesn't allow it. A snapshot requested in the background uses the vImage
  implementation.
- Each filtered layer caches its result. The cache key is the version of the
  filter's input content, the filter's parameters and the scale, so a filter is
  run again only when one of them changes.

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
  don't move show the same pixels as the image. Moving layers differ only at
  their antialiased edges, where the screen resamples them. Layers that frames
  reuse show the same pixels as layers painted again.
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
  that a slower rendering skips is a "Skipped frame" event. The benchmarks of
  the test app measure them with XCTest metrics, only when
  `TEST_RUNNER_RUN_BENCHMARKS` is `1`. They run in the Release configuration,
  as apps are built, since the Debug configuration takes many times longer.
- Performance is measured on devices. Simulators and Xcode Cloud, which only
  runs simulators, don't reflect device performance, so performance isn't a
  pass-or-fail check in CI. Instruments' animation hitches template is used to
  find dropped frames.
- Still image rendering is measured before the restructuring starts, and again
  after each phase, so that it doesn't get slower.

### Visual review

The viewer of the snapshot test app plays a document in SVGUIView and in a
`WKWebView` from the start, side by side or in the same place, to catch stutter
and flicker that numbers and snapshots miss.

## Implementation phases

Each phase leaves the package releasable, and a phase only starts when the one
before it is merged.

| Phase | Work | Status |
|---|---|---|
| 0 | Split the code into `SVGCore` and `SVGRenderCG` and into the four pipeline stages, without changing any output. The document tree becomes persistent, so it can change later. The snapshot tests move to Swift Testing first. | Done in 0.25.0 |
| 1 | Parse CSS Animations, implement the timing model and interpolation, and render any time with snapshots. | Done in 0.26.0 |
| 1.5 | SMIL animation, on the timing model and interpolation from phase 1. | Done in 0.27.0 |
| 2 | Play animations with `SVGRenderLayer`: the layer tree, the display link, the animation modes, and pausing. | Done in 0.28.0 |
| 2.5 | The document API and CSS Transitions, which need the document API to start. | Planned |
| 3 | Filters on Metal. | Planned |

Phase 0 kept the output of every test document the same while it moved the
code. The bugs it found on the way were fixed after the move, so 0.25.0 also
changes the output of the documents that those bugs affected.

## Open questions

- Whether still images should use the Metal filters once they produce the same
  results as the vImage implementation.
- Whether filters should move to Metal before phase 3. Until then, playback runs
  filters with vImage. A filtered element that only moves by `transform` or
  `opacity` isn't filtered again, but a filter whose parameters or input content
  change is run again on the CPU in every frame, and a slow one skips frames in
  that layer. In the benchmark document with filters, whose blurs change, running
  the filters takes most of each frame in a simulator. Devices haven't been
  measured yet. If such animations don't fit the frame budget on devices and are
  common in the documents to support, phase 3 moves ahead of phase 2.5. The
  cache of filter results is keyed by layer, so it can be used with vImage as
  well.
- Whether `.play` should become the default animation mode once animation
  support is stable.
- Whether the timeline should keep running while playback is stopped for being
  off screen, for apps that expect wall-clock behavior.
- How much of the render tree and the plan of the layers to make again for a
  frame. Styles are computed again only for the elements that animations
  change, but the render tree and the plan are made again for the whole
  document, which takes most of a frame of a document with many elements that
  don't move.

# How SVGUIView Follows the Specifications

Learn which specifications SVGUIView renders documents by, how it decides what they leave open, and what it doesn't support.

## Overview

SVGUIView renders SVG documents as the specifications describe them, so that a
document looks the way it does in a browser. It follows:

- SVG 2, and SVG 1.1 where SVG 2 doesn't describe a feature.
- The CSS specifications that SVG uses, such as CSS Values and Units 4, CSS
  Color 4 and 5, CSS Transforms, CSS Masking, CSS Animations and Transitions,
  and CSS Custom Properties.
- Filter Effects 1.
- The SMIL animation elements of SVG: `<animate>`, `<set>`,
  `<animateTransform>` and `<animateMotion>`.

### Deciding what the specifications leave open

Some behaviors aren't described by the specifications, are left to the user
agent, or are described in a way that the specifications and browsers disagree
about. SVGUIView decides each of them by the first of these rules that
applies:

1. **The text of the specifications.** When a normative statement, a
   definition or a grammar decides the behavior, SVGUIView follows it, even
   where some browsers differ.
2. **The intent of the tests.** The pass conditions of the W3C SVG 1.1 tests
   and the expectations of the reference tests of web-platform-tests decide
   the behavior, unless no browser meets them.
3. **The majority of browsers.** The behavior of at least two of Chrome,
   Firefox and Safari decides it. This includes what the specifications leave
   to the user agent.
4. **resvg.** When browsers disagree, or their behavior can't be checked, the
   rendering of [resvg](https://github.com/linebender/resvg), an SVG renderer
   with a large test suite, decides it.
5. **The limits of the implementation.** When Core Graphics or Core Text can't
   render the behavior that the rules above decide, or rendering it would be
   too slow, SVGUIView renders the closest behavior it can.

Features that the specifications mark as tentative, and features that no
browser implements, aren't supported.

### Invalid values

SVGUIView treats invalid values as the specifications do:

- An invalid declaration in a style sheet or a `style` attribute is ignored,
  and the property keeps the value of the cascade without it.
- An invalid presentation attribute is ignored. A negative `r`, `width` or
  `height` attribute is an error of the element, which isn't rendered, and a
  negative `rx` or `ry` attribute is `auto`.
- A math function such as `calc()` whose value is out of the range of the
  property is clamped to the range: `width: calc(-10px)` is a width of 0. A
  math function without white space around `+` or `-`, such as
  `calc(10%+10px)`, is invalid.
- A custom property that refers to itself through `var()` is invalid, and a
  `var()` of it takes its fallback.

### Features that SVGUIView doesn't support

These features aren't supported, and documents that use them are rendered
without them:

- Scripts and the DOM. An app reads and changes the document with
  ``SVGDocument`` instead. See <doc:ChangingDocuments>.
- User interaction and events, such as `:hover` and SMIL begin times that wait
  for a click. An app begins and ends those animations with
  ``SVGDocument/Element/beginElement()`` and
  ``SVGDocument/Element/endElement()``.
- SVG fonts.
- The `<tref>` element, which SVG 2 removed.
- `enable-background`, and the `BackgroundImage` and `BackgroundAlpha` inputs
  of filter primitives, which are empty.
- The `FillPaint` and `StrokePaint` inputs of filter primitives.
- SVG Tiny 1.2.
- HTML inside `<foreignObject>`.
- The network. Only `data:` URLs, references within the document, and the
  image files that ``ExternalResources`` allows are loaded.

### Where rendering differs from browsers

Because of the limits of Core Graphics and Core Text, a few features are
rendered in a way that differs from browsers:

- `unicode-bidi: isolate` and `plaintext` are rendered as `embed`, and
  `isolate-override` as `bidi-override`.
- Vertical text uses vertical glyph forms only for East Asian characters, so
  Latin letters set upright aren't turned by the vertical forms of the font.
- Color emoji inside a `<clipPath>` don't clip, since their glyphs have no
  outlines.
- `image-rendering: crisp-edges` scales images by their nearest pixels, as
  `pixelated` does.
- SMIL animations of the basic shapes of `clip-path` change discretely. CSS
  animations and transitions interpolate them.
- An interpolation of lengths in different units keeps up to three units, and
  changes discretely beyond them. A `min()`, `max()` or `clamp()` of lengths in
  different units changes discretely too.
- The value that `var()` substitutes is invalid when it's longer than 64 KiB.
- A missing component of the color of a nested `color-mix()` is 0 in the
  outer one.
- A CSS animation from a rule that matches only the copy of an element that a
  `<use>` element makes doesn't run.
- A style sheet in another file whose media queries have conditions, such as
  `@import url(a.css) screen and (min-width: 600px)`, doesn't apply. One
  without media queries, or for `all` or `screen`, applies.
- The `unicode-range` of an `@font-face` rule isn't read, so its font applies
  to every character. A length in `ex`, `ch`, `ic` or `lh` is measured with
  the fonts of the system, without the fonts of `@font-face` rules.
- A document in another file that a `<use>` element shows is shown without
  its animations, at time zero, as an SVG image is.

SVGUIView follows the text of the specifications in a few places where some
browsers don't:

- `<textPath>` bends glyphs with `method="stretch"`, and follows the path
  backward with `side="right"`.
- `glyph-orientation-vertical="0"` sets the characters of vertical text
  upright.
- Selectors match the copies that `<use>` elements make within their own tree.
- The copy of an element of another file that a `<use>` element shows is
  styled by the style sheets of that file, and not of the document of the
  `<use>` element.
- The position and the size of a nested `<svg>` element, and the `width` and
  `height` of a `<use>` element, take math functions, such as
  `width="calc(30% + 10px)"`.
- Selectors don't see the values that SMIL animations give attributes, except
  that class selectors see the class that an animation of `class` gives. A
  SMIL animation of the `style` attribute changes nothing.

A view pauses its animations while it isn't on the screen, and resumes them
where they stopped. To keep them in step with the clock, seek to the time with
``SVGUIView/SVGUIView/seek(to:)`` when the view appears.

### Features that SVGUIView doesn't support yet

These features are planned, but not supported yet:

- Images and references on the network, as an option.
- Math functions other than `calc()`, `min()`, `max()` and `clamp()`, such as
  `round()` and `sin()`.
- The `rect()`, `xywh()`, `path()` and `shape()` shapes of `clip-path`.
- The `font` shorthand, and font features such as `font-variant` and
  `font-stretch`.
- Synthetic bold and italic glyphs for fonts that don't have them.
- Interpolating colors other than the legacy ones in Oklab.
- Colors wider than Display P3.

import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import SVGUIView

/// Tests that an app reads the computed values of an element, as the DOM's `getComputedStyle()` gives them.
@MainActor
@Suite("Computed style", .serialized, .timeLimit(.minutes(2)))
struct ComputedStyleTests {
  /// A document whose elements get their values from presentation attributes, the `style` attribute, inheritance and
  /// initial values.
  private static let values = #"""
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" style="color: #00ff00; font-size: 20px">
    <defs><linearGradient id="g"/><clipPath id="c"/><mask id="m"/><filter id="f"/><marker id="mk"/></defs>
    <g id="p" fill="#f00" stroke="currentColor">
    <rect id="a" class="x" fill="url(#g) red" stroke-width="2em" stroke-dasharray="1 2.5 3px" opacity="0.5" fill-opacity="50%"
     transform="translate(10 20) rotate(45)" clip-path="url(#c)" mask="url(#m)" filter="url(#f)" marker-start="url(#mk)" marker-mid="url(#mk)" marker-end="url(#mk)"
     font-family="Helvetica, 'Times New Roman', serif" font-weight="bold" paint-order="stroke" stroke-linecap="round" visibility="hidden"
     style="--x: 3px; stop-color: rgba(10, 20, 30, 0.25); flood-color: hsl(120 100% 50%); x: 10%; width: calc(10px + 2em); rx: 1.50px; r: 1cm; stroke-dashoffset: 0.1in; lighting-color: color-mix(in srgb, red, blue)"/>
    <rect id="b" fill="none" stroke="url(#g)" font-size="larger" stroke-width="calc(10% + 5px)" filter="blur(2px) drop-shadow(1px 1px red)" clip-path="circle(5px)" transform="matrix(1 0 0 1 5 5)"/>
    <path id="d" d="M 0 0 L 10 10Z" style="d: path('M0,0 L 10 10')" stroke-dasharray="none" marker-start="none" font-size="medium"/>
    <circle id="e" style="fill: currentColor; color: rgb(1 2 3 / 0.5); stroke: color-mix(in srgb, red 50%, blue); stop-color: transparent; font-size: 1.5em; line-height: 1.2; letter-spacing: 0.1em; transform: scale(2)"/>
    </g></svg>
    """#

  /// The values of the elements of ``values`` as Chrome and Firefox give them, where they agree, and as CSS
  /// specifies them where they don't, such as `auto` for a width. Properties that SVGUIView doesn't know, such as
  /// `line-height`, have no value.
  private static let expected: [(id: String, property: String, value: String?)] = [
    ("a", "fill", "url(\"#g\") rgb(255, 0, 0)"),
    ("a", "stroke", "rgb(0, 255, 0)"),
    ("a", "color", "rgb(0, 255, 0)"),
    ("a", "stroke-width", "40px"),
    ("a", "stroke-dasharray", "1px, 2.5px, 3px"),
    ("a", "stroke-dashoffset", "9.6px"),
    ("a", "opacity", "0.5"),
    ("a", "fill-opacity", "0.5"),
    ("a", "transform", "matrix(0.707107, 0.707107, -0.707107, 0.707107, 10, 20)"),
    ("a", "clip-path", "url(\"#c\")"),
    ("a", "mask", "url(\"#m\")"),
    ("a", "filter", "url(\"#f\")"),
    ("a", "marker-start", "url(\"#mk\")"),
    ("a", "marker", "url(\"#mk\")"),
    ("a", "font-family", "Helvetica, \"Times New Roman\", serif"),
    ("a", "font-weight", "700"),
    ("a", "font-size", "20px"),
    ("a", "paint-order", "stroke"),
    ("a", "stroke-linecap", "round"),
    ("a", "visibility", "hidden"),
    ("a", "--x", "3px"),
    ("a", "stop-color", "rgba(10, 20, 30, 0.25)"),
    ("a", "flood-color", "rgb(0, 255, 0)"),
    ("a", "lighting-color", "color(srgb 0.5 0 0.5)"),
    ("a", "x", "10%"),
    ("a", "width", "50px"),
    ("a", "rx", "1.5px"),
    ("a", "r", "37.7953px"),
    ("a", "d", "none"),
    ("a", "letter-spacing", "normal"),
    ("a", "line-height", nil),
    ("a", "display", "inline"),
    ("a", "stroke-miterlimit", "4"),
    ("a", "font-style", "normal"),
    ("a", "text-anchor", "start"),
    ("a", "fill-rule", "nonzero"),
    ("a", "mix-blend-mode", "normal"),
    ("a", "animation-name", "none"),
    ("a", "animation-duration", "0s"),
    ("a", "transition-property", "all"),
    ("a", "transform-origin", "0px 0px"),
    ("a", "transform-box", "view-box"),
    ("a", "vector-effect", nil),
    ("a", "white-space", "normal"),
    ("a", "dominant-baseline", "auto"),
    ("a", "baseline-shift", "0px"),
    ("a", "writing-mode", "horizontal-tb"),
    ("a", "isolation", "auto"),
    ("a", "cx", "0px"),
    ("a", "y", "0px"),
    ("a", "height", "auto"),
    ("a", "ry", "auto"),
    ("b", "fill", "none"),
    ("b", "stroke", "url(\"#g\")"),
    ("b", "color", "rgb(0, 255, 0)"),
    ("b", "stroke-width", "calc(10% + 5px)"),
    ("b", "stroke-dasharray", "none"),
    ("b", "stroke-dashoffset", "0px"),
    ("b", "opacity", "1"),
    ("b", "fill-opacity", "1"),
    ("b", "transform", "matrix(1, 0, 0, 1, 5, 5)"),
    ("b", "clip-path", "circle(5px)"),
    ("b", "mask", "none"),
    ("b", "filter", "blur(2px) drop-shadow(rgb(255, 0, 0) 1px 1px 0px)"),
    ("b", "marker-start", "none"),
    ("b", "marker", "none"),
    ("b", "font-weight", "400"),
    ("b", "font-size", "24px"),
    ("b", "paint-order", "normal"),
    ("b", "stroke-linecap", "butt"),
    ("b", "visibility", "visible"),
    ("b", "--x", nil),
    ("b", "stop-color", "rgb(0, 0, 0)"),
    ("b", "flood-color", "rgb(0, 0, 0)"),
    ("b", "lighting-color", "rgb(255, 255, 255)"),
    ("b", "x", "0px"),
    ("b", "width", "auto"),
    ("b", "rx", "auto"),
    ("b", "r", "0px"),
    ("b", "d", "none"),
    ("b", "letter-spacing", "normal"),
    ("b", "line-height", nil),
    ("b", "display", "inline"),
    ("b", "stroke-miterlimit", "4"),
    ("b", "font-style", "normal"),
    ("b", "text-anchor", "start"),
    ("b", "fill-rule", "nonzero"),
    ("b", "mix-blend-mode", "normal"),
    ("b", "animation-name", "none"),
    ("b", "animation-duration", "0s"),
    ("b", "transition-property", "all"),
    ("b", "transform-origin", "0px 0px"),
    ("b", "transform-box", "view-box"),
    ("b", "vector-effect", nil),
    ("b", "white-space", "normal"),
    ("b", "dominant-baseline", "auto"),
    ("b", "baseline-shift", "0px"),
    ("b", "writing-mode", "horizontal-tb"),
    ("b", "isolation", "auto"),
    ("b", "cx", "0px"),
    ("b", "y", "0px"),
    ("b", "height", "auto"),
    ("b", "ry", "auto"),
    ("d", "fill", "rgb(255, 0, 0)"),
    ("d", "stroke", "rgb(0, 255, 0)"),
    ("d", "color", "rgb(0, 255, 0)"),
    ("d", "stroke-width", "1px"),
    ("d", "stroke-dasharray", "none"),
    ("d", "stroke-dashoffset", "0px"),
    ("d", "opacity", "1"),
    ("d", "fill-opacity", "1"),
    ("d", "transform", "none"),
    ("d", "clip-path", "none"),
    ("d", "mask", "none"),
    ("d", "filter", "none"),
    ("d", "marker-start", "none"),
    ("d", "marker", "none"),
    ("d", "font-weight", "400"),
    ("d", "font-size", "16px"),
    ("d", "paint-order", "normal"),
    ("d", "stroke-linecap", "butt"),
    ("d", "visibility", "visible"),
    ("d", "--x", nil),
    ("d", "stop-color", "rgb(0, 0, 0)"),
    ("d", "flood-color", "rgb(0, 0, 0)"),
    ("d", "lighting-color", "rgb(255, 255, 255)"),
    ("d", "x", "0px"),
    ("d", "width", "auto"),
    ("d", "rx", "auto"),
    ("d", "r", "0px"),
    ("d", "d", "path(\"M 0 0 L 10 10\")"),
    ("d", "letter-spacing", "normal"),
    ("d", "line-height", nil),
    ("d", "display", "inline"),
    ("d", "stroke-miterlimit", "4"),
    ("d", "font-style", "normal"),
    ("d", "text-anchor", "start"),
    ("d", "fill-rule", "nonzero"),
    ("d", "mix-blend-mode", "normal"),
    ("d", "animation-name", "none"),
    ("d", "animation-duration", "0s"),
    ("d", "transition-property", "all"),
    ("d", "transform-origin", "0px 0px"),
    ("d", "transform-box", "view-box"),
    ("d", "vector-effect", nil),
    ("d", "white-space", "normal"),
    ("d", "dominant-baseline", "auto"),
    ("d", "baseline-shift", "0px"),
    ("d", "writing-mode", "horizontal-tb"),
    ("d", "isolation", "auto"),
    ("d", "cx", "0px"),
    ("d", "y", "0px"),
    ("d", "height", "auto"),
    ("d", "ry", "auto"),
    ("e", "fill", "rgba(1, 2, 3, 0.5)"),
    ("e", "stroke", "color(srgb 0.5 0 0.5)"),
    ("e", "color", "rgba(1, 2, 3, 0.5)"),
    ("e", "stroke-width", "1px"),
    ("e", "stroke-dasharray", "none"),
    ("e", "stroke-dashoffset", "0px"),
    ("e", "opacity", "1"),
    ("e", "fill-opacity", "1"),
    ("e", "transform", "matrix(2, 0, 0, 2, 0, 0)"),
    ("e", "clip-path", "none"),
    ("e", "mask", "none"),
    ("e", "filter", "none"),
    ("e", "marker-start", "none"),
    ("e", "marker", "none"),
    ("e", "font-weight", "400"),
    ("e", "font-size", "30px"),
    ("e", "paint-order", "normal"),
    ("e", "stroke-linecap", "butt"),
    ("e", "visibility", "visible"),
    ("e", "--x", nil),
    ("e", "stop-color", "rgba(0, 0, 0, 0)"),
    ("e", "flood-color", "rgb(0, 0, 0)"),
    ("e", "lighting-color", "rgb(255, 255, 255)"),
    ("e", "x", "0px"),
    ("e", "width", "auto"),
    ("e", "rx", "auto"),
    ("e", "r", "0px"),
    ("e", "d", "none"),
    ("e", "letter-spacing", "3px"),
    ("e", "line-height", nil),
    ("e", "display", "inline"),
    ("e", "stroke-miterlimit", "4"),
    ("e", "font-style", "normal"),
    ("e", "text-anchor", "start"),
    ("e", "fill-rule", "nonzero"),
    ("e", "mix-blend-mode", "normal"),
    ("e", "animation-name", "none"),
    ("e", "animation-duration", "0s"),
    ("e", "transition-property", "all"),
    ("e", "transform-origin", "0px 0px"),
    ("e", "transform-box", "view-box"),
    ("e", "vector-effect", nil),
    ("e", "white-space", "normal"),
    ("e", "dominant-baseline", "auto"),
    ("e", "baseline-shift", "0px"),
    ("e", "writing-mode", "horizontal-tb"),
    ("e", "isolation", "auto"),
    ("e", "cx", "0px"),
    ("e", "y", "0px"),
    ("e", "height", "auto"),
    ("e", "ry", "auto"),
  ]

  /// A document whose elements have keywords, lists and functions.
  private static let keywords = #"""
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
    <style>@keyframes k { to { opacity: 0 } }
    #h { animation: k 2s cubic-bezier(0.1, 0.2, 0.3, 0.4) 0.5s infinite alternate both paused; transition: fill 1s steps(3), stroke 0.25s steps(2, jump-start) 1s; }</style>
    <g id="h" shape-rendering="optimizeSpeed" pointer-events="visiblePainted" color-interpolation="linearRGB" color-interpolation-filters="sRGB" text-decoration="underline line-through"
     font-style="oblique 10deg" baseline-shift="sub" clip-path="ellipse(1px 2px at 3px 4px) fill-box" filter="brightness(1.5) hue-rotate(90deg) grayscale(50%)" transform-origin="center"
     font-size="x-large" dominant-baseline="middle" writing-mode="vertical-rl" image-rendering="pixelated" stroke-linejoin="bevel" fill-rule="evenodd" text-anchor="middle" display="block" overflow="hidden" direction="rtl" unicode-bidi="bidi-override" white-space="pre" word-spacing="2mm" letter-spacing="0"/>
    <g id="i" clip-path="inset(1px 2px round 3px)" baseline-shift="2px" font-family="monospace" font-style="italic" paint-order="markers stroke" transform="skewX(30)" style="transition-property: none; animation-timing-function: linear(0, 0.5 25%, 1); font-weight: bolder"/>
    <g id="j" clip-path="polygon(evenodd, 0 0, 10px 0, 5px 10%)" baseline-shift="super" paint-order="fill markers" style="animation-name: k, none; animation-timing-function: ease-in, steps(4, jump-none); font-size: 2cm"/>
    <g id="k" clip-path="fill-box" stroke-dashoffset="-1" stroke-miterlimit="10" style="cx: calc(1px + 10%); cy: max(5px, 10%); font-size: 50%; stop-opacity: 0.333; flood-opacity: 2; text-orientation: upright"/>
    </svg>
    """#

  /// The values of the elements of ``keywords`` as Chrome and Firefox give them, where they agree, and as one of
  /// them gives them where they don't, such as `white-space` as Firefox reads its presentation attribute. The size
  /// of `monospace` is the one that SVGUIView renders it in, which is Chrome's, and a `transform-origin` of `center`
  /// stays a percentage, since SVGUIView doesn't know the box that it's of.
  private static let expectedKeywords: [(id: String, property: String, value: String?)] = [
    ("h", "shape-rendering", "optimizespeed"),
    ("h", "pointer-events", "visiblepainted"),
    ("h", "color-interpolation", "linearrgb"),
    ("h", "color-interpolation-filters", "srgb"),
    ("h", "text-decoration", "underline line-through"),
    ("h", "font-style", "oblique 10deg"),
    ("h", "baseline-shift", "sub"),
    ("h", "clip-path", "ellipse(1px 2px at 3px 4px) fill-box"),
    ("h", "filter", "brightness(1.5) hue-rotate(90deg) grayscale(0.5)"),
    ("h", "transform-origin", "50% 50%"),
    ("h", "font-size", "24px"),
    ("h", "dominant-baseline", "middle"),
    ("h", "writing-mode", "vertical-rl"),
    ("h", "image-rendering", "pixelated"),
    ("h", "stroke-linejoin", "bevel"),
    ("h", "fill-rule", "evenodd"),
    ("h", "text-anchor", "middle"),
    ("h", "display", "block"),
    ("h", "overflow", "hidden"),
    ("h", "direction", "rtl"),
    ("h", "unicode-bidi", "bidi-override"),
    ("h", "white-space", "pre"),
    ("h", "word-spacing", "7.55906px"),
    ("h", "letter-spacing", "normal"),
    ("h", "paint-order", "normal"),
    ("h", "transition-property", "fill, stroke"),
    ("h", "transition-duration", "1s, 0.25s"),
    ("h", "transition-timing-function", "steps(3), steps(2, jump-start)"),
    ("h", "transition-delay", "0s, 1s"),
    ("h", "transition-behavior", "normal, normal"),
    ("h", "animation-name", "k"),
    ("h", "animation-duration", "2s"),
    ("h", "animation-timing-function", "cubic-bezier(0.1, 0.2, 0.3, 0.4)"),
    ("h", "animation-delay", "0.5s"),
    ("h", "animation-iteration-count", "infinite"),
    ("h", "animation-direction", "alternate"),
    ("h", "animation-fill-mode", "both"),
    ("h", "animation-play-state", "paused"),
    ("h", "font-weight", "400"),
    ("h", "text-orientation", "mixed"),
    ("h", "stroke-dashoffset", "0px"),
    ("h", "stroke-miterlimit", "4"),
    ("h", "cx", "0px"),
    ("h", "cy", "0px"),
    ("h", "stop-opacity", "1"),
    ("h", "flood-opacity", "1"),
    ("h", "image-orientation", "from-image"),
    ("h", "alignment-baseline", "auto"),
    ("h", "isolation", "auto"),
    ("h", "clip-rule", "nonzero"),
    ("h", "transform-box", "view-box"),
    ("h", "visibility", "visible"),
    ("i", "shape-rendering", "auto"),
    ("i", "pointer-events", "auto"),
    ("i", "color-interpolation", "srgb"),
    ("i", "color-interpolation-filters", "linearrgb"),
    ("i", "text-decoration", "none"),
    ("i", "font-style", "italic"),
    ("i", "baseline-shift", "2px"),
    ("i", "clip-path", "inset(1px 2px round 3px)"),
    ("i", "filter", "none"),
    ("i", "transform", "matrix(1, 0, 0.57735, 1, 0, 0)"),
    ("i", "transform-origin", "0px 0px"),
    ("i", "font-size", "13px"),
    ("i", "dominant-baseline", "auto"),
    ("i", "mix-blend-mode", "normal"),
    ("i", "writing-mode", "horizontal-tb"),
    ("i", "image-rendering", "auto"),
    ("i", "stroke-linejoin", "miter"),
    ("i", "fill-rule", "nonzero"),
    ("i", "text-anchor", "start"),
    ("i", "display", "inline"),
    ("i", "overflow", "visible"),
    ("i", "direction", "ltr"),
    ("i", "unicode-bidi", "normal"),
    ("i", "white-space", "normal"),
    ("i", "word-spacing", "0px"),
    ("i", "letter-spacing", "normal"),
    ("i", "font-family", "monospace"),
    ("i", "paint-order", "markers stroke"),
    ("i", "transition-property", "none"),
    ("i", "transition-duration", "0s"),
    ("i", "transition-timing-function", "ease"),
    ("i", "transition-delay", "0s"),
    ("i", "transition-behavior", "normal"),
    ("i", "animation-name", "none"),
    ("i", "animation-duration", "0s"),
    ("i", "animation-timing-function", "linear(0 0%, 0.5 25%, 1 100%)"),
    ("i", "animation-delay", "0s"),
    ("i", "animation-iteration-count", "1"),
    ("i", "animation-direction", "normal"),
    ("i", "animation-fill-mode", "none"),
    ("i", "animation-play-state", "running"),
    ("i", "font-weight", "700"),
    ("i", "text-orientation", "mixed"),
    ("i", "stroke-dashoffset", "0px"),
    ("i", "stroke-miterlimit", "4"),
    ("i", "cx", "0px"),
    ("i", "cy", "0px"),
    ("i", "stop-opacity", "1"),
    ("i", "flood-opacity", "1"),
    ("i", "image-orientation", "from-image"),
    ("i", "alignment-baseline", "auto"),
    ("i", "isolation", "auto"),
    ("i", "clip-rule", "nonzero"),
    ("i", "transform-box", "view-box"),
    ("i", "visibility", "visible"),
    ("j", "shape-rendering", "auto"),
    ("j", "pointer-events", "auto"),
    ("j", "color-interpolation", "srgb"),
    ("j", "color-interpolation-filters", "linearrgb"),
    ("j", "text-decoration", "none"),
    ("j", "font-style", "normal"),
    ("j", "baseline-shift", "super"),
    ("j", "clip-path", "polygon(evenodd, 0px 0px, 10px 0px, 5px 10%)"),
    ("j", "filter", "none"),
    ("j", "transform", "none"),
    ("j", "transform-origin", "0px 0px"),
    ("j", "font-size", "75.5906px"),
    ("j", "dominant-baseline", "auto"),
    ("j", "mix-blend-mode", "normal"),
    ("j", "writing-mode", "horizontal-tb"),
    ("j", "image-rendering", "auto"),
    ("j", "stroke-linejoin", "miter"),
    ("j", "fill-rule", "nonzero"),
    ("j", "text-anchor", "start"),
    ("j", "display", "inline"),
    ("j", "overflow", "visible"),
    ("j", "direction", "ltr"),
    ("j", "unicode-bidi", "normal"),
    ("j", "white-space", "normal"),
    ("j", "word-spacing", "0px"),
    ("j", "letter-spacing", "normal"),
    ("j", "paint-order", "fill markers"),
    ("j", "transition-property", "all"),
    ("j", "transition-duration", "0s"),
    ("j", "transition-timing-function", "ease"),
    ("j", "transition-delay", "0s"),
    ("j", "transition-behavior", "normal"),
    ("j", "animation-name", "k, none"),
    ("j", "animation-duration", "0s"),
    ("j", "animation-timing-function", "ease-in, steps(4, jump-none)"),
    ("j", "animation-delay", "0s"),
    ("j", "animation-iteration-count", "1"),
    ("j", "animation-direction", "normal"),
    ("j", "animation-fill-mode", "none"),
    ("j", "animation-play-state", "running"),
    ("j", "font-weight", "400"),
    ("j", "text-orientation", "mixed"),
    ("j", "stroke-dashoffset", "0px"),
    ("j", "stroke-miterlimit", "4"),
    ("j", "cx", "0px"),
    ("j", "cy", "0px"),
    ("j", "stop-opacity", "1"),
    ("j", "flood-opacity", "1"),
    ("j", "image-orientation", "from-image"),
    ("j", "alignment-baseline", "auto"),
    ("j", "isolation", "auto"),
    ("j", "clip-rule", "nonzero"),
    ("j", "transform-box", "view-box"),
    ("j", "visibility", "visible"),
    ("k", "shape-rendering", "auto"),
    ("k", "pointer-events", "auto"),
    ("k", "color-interpolation", "srgb"),
    ("k", "color-interpolation-filters", "linearrgb"),
    ("k", "text-decoration", "none"),
    ("k", "font-style", "normal"),
    ("k", "baseline-shift", "0px"),
    ("k", "clip-path", "fill-box"),
    ("k", "filter", "none"),
    ("k", "transform", "none"),
    ("k", "transform-origin", "0px 0px"),
    ("k", "font-size", "8px"),
    ("k", "dominant-baseline", "auto"),
    ("k", "mix-blend-mode", "normal"),
    ("k", "writing-mode", "horizontal-tb"),
    ("k", "image-rendering", "auto"),
    ("k", "stroke-linejoin", "miter"),
    ("k", "fill-rule", "nonzero"),
    ("k", "text-anchor", "start"),
    ("k", "display", "inline"),
    ("k", "overflow", "visible"),
    ("k", "direction", "ltr"),
    ("k", "unicode-bidi", "normal"),
    ("k", "white-space", "normal"),
    ("k", "word-spacing", "0px"),
    ("k", "letter-spacing", "normal"),
    ("k", "paint-order", "normal"),
    ("k", "transition-property", "all"),
    ("k", "transition-duration", "0s"),
    ("k", "transition-timing-function", "ease"),
    ("k", "transition-delay", "0s"),
    ("k", "transition-behavior", "normal"),
    ("k", "animation-name", "none"),
    ("k", "animation-duration", "0s"),
    ("k", "animation-timing-function", "ease"),
    ("k", "animation-delay", "0s"),
    ("k", "animation-iteration-count", "1"),
    ("k", "animation-direction", "normal"),
    ("k", "animation-fill-mode", "none"),
    ("k", "animation-play-state", "running"),
    ("k", "font-weight", "400"),
    ("k", "text-orientation", "upright"),
    ("k", "stroke-dashoffset", "-1px"),
    ("k", "stroke-miterlimit", "10"),
    ("k", "cx", "calc(10% + 1px)"),
    ("k", "cy", "max(5px, 10%)"),
    ("k", "stop-opacity", "0.333"),
    ("k", "flood-opacity", "1"),
    ("k", "image-orientation", "from-image"),
    ("k", "alignment-baseline", "auto"),
    ("k", "isolation", "auto"),
    ("k", "clip-rule", "nonzero"),
    ("k", "transform-box", "view-box"),
    ("k", "visibility", "visible"),
  ]

  @Test("the values are the ones that browsers give, for a document that no view shows")
  func valuesAsBrowsersGiveThem() throws {
    let document = SVGUIView(data: Data(Self.values.utf8)).document
    for (id, property, value) in Self.expected {
      let element = try #require(document.element(id: id))
      #expect(element.computedStyle.property(property) == value, "\(id) \(property)")
    }
  }

  @Test("keywords, lists and functions are written as browsers write them")
  func keywordsAsBrowsersWriteThem() throws {
    let document = SVGUIView(data: Data(Self.keywords.utf8)).document
    for (id, property, value) in Self.expectedKeywords {
      let element = try #require(document.element(id: id))
      #expect(element.computedStyle.property(property) == value, "\(id) \(property)")
    }
  }

  @Test("rules of style sheets, inheritance and custom properties apply, and names of properties aren't case-sensitive")
  func cascade() throws {
    let document = SVGUIView(
      data: Data(
        #"""
        <svg xmlns="http://www.w3.org/2000/svg"><style>.a { fill: blue; --Size: 4px } #r { stroke-width: 3 }</style>
        <g class="a" stroke="red"><rect id="r" style="stroke-width: 5"/></g></svg>
        """#.utf8)
    ).document
    let style = try #require(document.element(id: "r")).computedStyle
    #expect(style.property("fill") == "rgb(0, 0, 255)")
    #expect(style.property("STROKE") == "rgb(255, 0, 0)")
    #expect(style.property("stroke-width") == "5px")
    #expect(style.property("--Size") == "4px")
    #expect(style.property("--size") == nil)
    #expect(style.property("unknown") == nil)
  }

  @Test("a change of the document is visible at once, and an element out of the tree has no values")
  func changes() throws {
    let document = SVGUIView(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"><rect id="r"/></svg>"#.utf8)).document
    let rect = try #require(document.element(id: "r"))
    #expect(rect.computedStyle.property("fill") == "rgb(0, 0, 0)")
    rect.setAttribute("fill", to: "lime")
    #expect(rect.computedStyle.property("fill") == "rgb(0, 255, 0)")
    let circle = document.createElement("circle")
    #expect(circle.computedStyle.property("fill") == nil)
    rect.remove()
    #expect(rect.computedStyle.property("fill") == nil)
  }

  @Test("a view gives the values at the time that it displays, with its animations")
  func animatedValues() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    let view = SVGUIView(
      frame: CGRect(x: 0, y: 0, width: 20, height: 20),
      data: Data(
        #"""
        <svg xmlns="http://www.w3.org/2000/svg"><style>@keyframes a { from { opacity: 0 } to { opacity: 1 } }
        rect { animation: a 2s linear }</style><rect id="r" width="10" height="10"/></svg>
        """#.utf8))
    view.clock = ManualClock()
    view.isReduceMotionEnabled = { false }
    view.configuration = SVGUIViewConfiguration(animation: .play)
    window.addSubview(view)
    let rect = try #require(view.document.element(id: "r"))
    #expect(rect.computedStyle.property("opacity") == "0")
    view.seek(to: .seconds(1))
    #expect(rect.computedStyle.property("opacity") == "0.5")
    // A change is visible at the time too.
    rect.style.setProperty("animation", to: "none")
    #expect(rect.computedStyle.property("opacity") == "1")
  }
}

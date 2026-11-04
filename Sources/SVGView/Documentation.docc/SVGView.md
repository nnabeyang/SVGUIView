# ``SVGView``

Display an SVG image in SwiftUI.

## Overview

``SVGView/SVGView`` wraps `SVGUIView` so that you can place an SVG image in a
SwiftUI view hierarchy.

```swift
struct ContentView: View {
  let url = Bundle.main.url(forResource: "example", withExtension: "svg")!

  var body: some View {
    SVGView(contentsOf: url, contentMode: .fit)
  }
}
```

Rendering settings come from the environment. Set
``SwiftUICore/EnvironmentValues/svgViewConfiguration`` to change them for every
``SVGView/SVGView`` in a subtree.

```swift
ContentView()
  .environment(
    \.svgViewConfiguration,
    SVGUIViewConfiguration(taskPriority: .high, timeoutDuration: .seconds(2))
  )
```

The views play the animations of their documents by default. The configuration
shows the documents as still images instead:

```swift
ContentView()
  .environment(\.svgViewConfiguration, SVGUIViewConfiguration(animation: .none))
```

## Topics

### Displaying SVG

- ``SVGView/SVGView``

### Configuring Rendering

- ``SwiftUICore/EnvironmentValues/svgViewConfiguration``

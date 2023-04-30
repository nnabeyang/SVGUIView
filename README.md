# SVGUIView

An UIView that displays a single SVG image in your interface.

## Usage

Creating a SVGUIView:
```
guard let svgView = SVGUIView(contentOf: Bundle.main.url(forResource: "example", withExtension: "svg")!) else { return }
view.addSubView(svgView)
```

## Installation

### SwiftPM

Add the `SVGUIView` as a dependency:

```swift
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        // other dependencies
        .package(url: "https://github.com/nnabeyang/SVGUIView", from: "0.0.0"),
    ],
    targets: [
        .executableTarget(name: "<executable-target-name>", dependencies: [
            // other dependencies
                .product(name: "SVGUIView", package: "SVGUIView"),
        ]),
        // other targets
    ]
)
```

## License

SVGUIView is published under the MIT License, see LICENSE.

## Author
[Noriaki Watanabe@nnabeyang](https://twitter.com/nnabeyang)

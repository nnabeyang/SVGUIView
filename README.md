# SVGUIView

An UIView that displays a single SVG image in your interface.

## Usage

Creating a SVGUIView:
```
let data = Bundle.main.url(forResource: "example", withExtension: "svg")!
let svgView = SVGUIView(contentsOf: data)!
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
        .package(url: "https://github.com/nnabeyang/SVGUIView", from: "0.19.3"),
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

### CocoaPods

Add the following to your Podfile:

```terminal
pod 'SVGUIView'
```

## License

SVGUIView is published under the MIT License, see LICENSE.

## Author
[Noriaki Watanabe@nnabeyang](https://twitter.com/nnabeyang)

import Foundation

/// A color space of `color()`, from CSS Color 4.
enum CSSColorSpace: String {
  case sRGB = "srgb"
  case sRGBLinear = "srgb-linear"
  case displayP3 = "display-p3"
  case a98RGB = "a98-rgb"
  case proPhotoRGB = "prophoto-rgb"
  case rec2020
  case xyz
  case xyzD50 = "xyz-d50"
  case xyzD65 = "xyz-d65"
}

/// The conversions of colors to sRGB, with the matrices and the transfer functions of the sample code of CSS Color 4.
enum ColorConversion {
  typealias Vector = (Double, Double, Double)
  typealias Matrix = (Vector, Vector, Vector)

  /// The red, green and blue of sRGB of a color of `color()`, which can be outside 0 to 1.
  static func sRGB(_ components: Vector, in space: CSSColorSpace) -> Vector {
    let (c0, c1, c2) = components
    switch space {
    case .sRGB:
      return components
    case .sRGBLinear:
      return gamma(components)
    case .displayP3:
      let linear = (linearSRGB(c0), linearSRGB(c1), linearSRGB(c2))
      return sRGB(xyzD65: multiply(displayP3ToXYZ, linear))
    case .a98RGB:
      func linear(_ c: Double) -> Double { sign(c) * pow(abs(c), 563 / 256) }
      return sRGB(xyzD65: multiply(a98RGBToXYZ, (linear(c0), linear(c1), linear(c2))))
    case .proPhotoRGB:
      func linear(_ c: Double) -> Double { abs(c) <= 16 / 512 ? c / 16 : sign(c) * pow(abs(c), 1.8) }
      return sRGB(xyzD50: multiply(proPhotoRGBToXYZ, (linear(c0), linear(c1), linear(c2))))
    case .rec2020:
      let alpha = 1.09929682680944
      let beta = 0.018053968510807
      func linear(_ c: Double) -> Double {
        abs(c) < beta * 4.5 ? c / 4.5 : sign(c) * pow((abs(c) + alpha - 1) / alpha, 1 / 0.45)
      }
      return sRGB(xyzD65: multiply(rec2020ToXYZ, (linear(c0), linear(c1), linear(c2))))
    case .xyz, .xyzD65:
      return sRGB(xyzD65: components)
    case .xyzD50:
      return sRGB(xyzD50: components)
    }
  }

  /// The red, green and blue of sRGB of a color in CIE Lab, whose white is D50.
  static func sRGB(lightness: Double, a: Double, b: Double) -> Vector {
    let kappa = 24389.0 / 27
    let epsilon = 216.0 / 24389
    let f1 = (lightness + 16) / 116
    let f0 = a / 500 + f1
    let f2 = f1 - b / 200
    let x = pow(f0, 3) > epsilon ? pow(f0, 3) : (116 * f0 - 16) / kappa
    let y = lightness > kappa * epsilon ? pow(f1, 3) : lightness / kappa
    let z = pow(f2, 3) > epsilon ? pow(f2, 3) : (116 * f2 - 16) / kappa
    let white = (0.3457 / 0.3585, 1.0, (1 - 0.3457 - 0.3585) / 0.3585)
    return sRGB(xyzD50: (x * white.0, y * white.1, z * white.2))
  }

  /// The red, green and blue of sRGB of a color in Oklab.
  static func sRGB(oklabLightness lightness: Double, a: Double, b: Double) -> Vector {
    let lms = multiply(oklabToLMS, (lightness, a, b))
    let cubed = (pow(lms.0, 3), pow(lms.1, 3), pow(lms.2, 3))
    return gamma(multiply(xyzToLinearSRGB, multiply(lmsToXYZ, cubed)))
  }

  /// The a and b of a color of lightness, chroma and hue in degrees.
  static func ab(chroma: Double, hue: Double) -> (a: Double, b: Double) {
    let radians = hue * .pi / 180
    return (chroma * cos(radians), chroma * sin(radians))
  }

  private static func sRGB(xyzD65: Vector) -> Vector {
    gamma(multiply(xyzToLinearSRGB, xyzD65))
  }

  private static func sRGB(xyzD50: Vector) -> Vector {
    sRGB(xyzD65: multiply(d50ToD65, xyzD50))
  }

  /// The sRGB transfer function of linear red, green and blue, which keeps the signs of the values.
  private static func gamma(_ linear: Vector) -> Vector {
    func channel(_ c: Double) -> Double {
      abs(c) > 0.0031308 ? sign(c) * (1.055 * pow(abs(c), 1 / 2.4) - 0.055) : 12.92 * c
    }
    return (channel(linear.0), channel(linear.1), channel(linear.2))
  }

  /// A channel of sRGB made linear, which keeps its sign.
  private static func linearSRGB(_ c: Double) -> Double {
    abs(c) <= 0.04045 ? c / 12.92 : sign(c) * pow((abs(c) + 0.055) / 1.055, 2.4)
  }

  private static func sign(_ value: Double) -> Double {
    value < 0 ? -1 : 1
  }

  private static func multiply(_ m: Matrix, _ v: Vector) -> Vector {
    func row(_ r: Vector) -> Double { r.0 * v.0 + r.1 * v.1 + r.2 * v.2 }
    return (row(m.0), row(m.1), row(m.2))
  }

  private static let xyzToLinearSRGB: Matrix = (
    (3.2409699419045226, -1.537383177570094, -0.4986107602930034),
    (-0.9692436362808796, 1.8759675015077202, 0.04155505740717559),
    (0.05563007969699366, -0.20397695888897652, 1.0569715142428786)
  )

  /// The Bradford chromatic adaptation from D50 to D65.
  private static let d50ToD65: Matrix = (
    (0.955473421488075, -0.02309845494876471, 0.06325924320057072),
    (-0.0283697093338637, 1.0099953980813041, 0.021041441191917323),
    (0.012314014864481998, -0.020507649298898964, 1.330365926242124)
  )

  private static let displayP3ToXYZ: Matrix = (
    (0.4865709486482162, 0.26566769316909306, 0.1982172852343625),
    (0.2289745640697488, 0.6917385218365064, 0.079286914093745),
    (0, 0.04511338185890264, 1.043944368900976)
  )

  private static let a98RGBToXYZ: Matrix = (
    (0.5766690429101305, 0.1855582379065463, 0.1882286462349947),
    (0.29734497525053605, 0.6273635662554661, 0.07529145849399788),
    (0.02703136138641234, 0.07068885253582723, 0.9913375368376388)
  )

  /// To XYZ whose white is D50.
  private static let proPhotoRGBToXYZ: Matrix = (
    (0.7977666449006423, 0.13518129740053308, 0.0313477341283922),
    (0.2880748288194013, 0.711835234241873, 0.00008993693872564),
    (0, 0, 0.8251046025104602)
  )

  private static let rec2020ToXYZ: Matrix = (
    (0.6369580483012914, 0.14461690358620832, 0.1688809751641721),
    (0.2627002120112671, 0.6779980715188708, 0.05930171646986196),
    (0, 0.028072693049087428, 1.060985057710791)
  )

  private static let oklabToLMS: Matrix = (
    (1.0, 0.3963377773761749, 0.2158037573099136),
    (1.0, -0.1055613458156586, -0.0638541728258133),
    (1.0, -0.0894841775298119, -1.2914855480194092)
  )

  private static let lmsToXYZ: Matrix = (
    (1.2268798758459243, -0.5578149944602171, 0.2813910456659647),
    (-0.0405757452148008, 1.1122868032803170, -0.0717110580655164),
    (-0.0763729366746601, -0.4214933324022432, 1.5869240198367816)
  )
}

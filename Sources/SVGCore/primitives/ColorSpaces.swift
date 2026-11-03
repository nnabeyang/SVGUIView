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

  /// The red, green and blue of sRGB of a color in HSL, as CSS Color converts it, which can be outside 0 to 1.
  ///
  /// - Parameters:
  ///   - hue: The hue in degrees, which goes around every 360 degrees.
  ///   - saturation: The saturation, 100 for a full one.
  ///   - lightness: The lightness, from 0 for black to 100 for white.
  static func sRGB(hue: Double, saturation: Double, lightness: Double) -> Vector {
    let hue = hue.truncatingRemainder(dividingBy: 360) + (hue < 0 ? 360 : 0)
    let saturation = saturation / 100
    let lightness = lightness / 100
    func channel(_ n: Double) -> Double {
      let k = (n + hue / 30).truncatingRemainder(dividingBy: 12)
      let a = saturation * min(lightness, 1 - lightness)
      return lightness - a * max(-1, min(k - 3, 9 - k, 1))
    }
    return (channel(0), channel(8), channel(4))
  }

  /// The red, green and blue of sRGB of a color in HWB, whose whiteness and blackness are 100 for full ones.
  static func sRGB(hue: Double, whiteness: Double, blackness: Double) -> Vector {
    let whiteness = whiteness / 100
    let blackness = blackness / 100
    if whiteness + blackness >= 1 {
      let gray = whiteness / (whiteness + blackness)
      return (gray, gray, gray)
    }
    let pure = sRGB(hue: hue, saturation: 100, lightness: 50)
    let scale = 1 - whiteness - blackness
    return (pure.0 * scale + whiteness, pure.1 * scale + whiteness, pure.2 * scale + whiteness)
  }

  // MARK: - From sRGB

  /// The components of a color of sRGB in another color space of `color()`.
  static func components(ofSRGB rgb: Vector, in space: CSSColorSpace) -> Vector {
    let linear = (linearSRGB(rgb.0), linearSRGB(rgb.1), linearSRGB(rgb.2))
    let xyz = multiply(linearSRGBToXYZ, linear)
    switch space {
    case .sRGB:
      return rgb
    case .sRGBLinear:
      return linear
    case .displayP3:
      return gamma(multiply(xyzToDisplayP3, xyz))
    case .a98RGB:
      let c = multiply(xyzToA98RGB, xyz)
      func encoded(_ c: Double) -> Double { sign(c) * pow(abs(c), 256 / 563) }
      return (encoded(c.0), encoded(c.1), encoded(c.2))
    case .proPhotoRGB:
      let c = multiply(xyzToProPhotoRGB, multiply(d65ToD50, xyz))
      func encoded(_ c: Double) -> Double { abs(c) >= 1 / 512 ? sign(c) * pow(abs(c), 1 / 1.8) : 16 * c }
      return (encoded(c.0), encoded(c.1), encoded(c.2))
    case .rec2020:
      let alpha = 1.09929682680944
      let beta = 0.018053968510807
      let c = multiply(xyzToRec2020, xyz)
      func encoded(_ c: Double) -> Double {
        abs(c) > beta ? sign(c) * (alpha * pow(abs(c), 0.45) - (alpha - 1)) : 4.5 * c
      }
      return (encoded(c.0), encoded(c.1), encoded(c.2))
    case .xyz, .xyzD65:
      return xyz
    case .xyzD50:
      return multiply(d65ToD50, xyz)
    }
  }

  /// The lightness, a and b of CIE Lab of a color of sRGB.
  static func lab(ofSRGB rgb: Vector) -> Vector {
    let kappa = 24389.0 / 27
    let epsilon = 216.0 / 24389
    let xyz = components(ofSRGB: rgb, in: .xyzD50)
    let white = (0.3457 / 0.3585, 1.0, (1 - 0.3457 - 0.3585) / 0.3585)
    func f(_ t: Double) -> Double { t > epsilon ? cbrt(t) : (kappa * t + 16) / 116 }
    let (f0, f1, f2) = (f(xyz.0 / white.0), f(xyz.1 / white.1), f(xyz.2 / white.2))
    return (116 * f1 - 16, 500 * (f0 - f1), 200 * (f1 - f2))
  }

  /// The lightness, a and b of Oklab of a color of sRGB.
  static func oklab(ofSRGB rgb: Vector) -> Vector {
    let lms = multiply(xyzToLMS, components(ofSRGB: rgb, in: .xyzD65))
    return multiply(lmsToOklab, (cbrt(lms.0), cbrt(lms.1), cbrt(lms.2)))
  }

  /// The hue in degrees, the saturation and the lightness of HSL of a color of sRGB, both 100 for full ones. The hue
  /// is `nil` for a gray, which has none.
  static func hsl(ofSRGB rgb: Vector) -> (hue: Double?, saturation: Double, lightness: Double) {
    let maximum = max(rgb.0, rgb.1, rgb.2)
    let minimum = min(rgb.0, rgb.1, rgb.2)
    let lightness = (maximum + minimum) / 2
    let difference = maximum - minimum
    guard difference > 1e-9 else { return (nil, 0, lightness * 100) }
    let saturation =
      lightness == 0 || lightness == 1 ? 0 : (maximum - lightness) / min(lightness, 1 - lightness)
    var hue: Double
    switch maximum {
    case rgb.0: hue = (rgb.1 - rgb.2) / difference + (rgb.1 < rgb.2 ? 6 : 0)
    case rgb.1: hue = (rgb.2 - rgb.0) / difference + 2
    default: hue = (rgb.0 - rgb.1) / difference + 4
    }
    hue *= 60
    return (hue, saturation * 100, lightness * 100)
  }

  /// The polar form of the a and b of a color: its chroma, and its hue in degrees from 0 to 360.
  static func polar(a: Double, b: Double) -> (chroma: Double, hue: Double) {
    let hue = atan2(b, a) * 180 / .pi
    return (hypot(a, b), hue < 0 ? hue + 360 : hue)
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

  private static let linearSRGBToXYZ: Matrix = (
    (0.41239079926595934, 0.357584339383878, 0.1804807884018343),
    (0.21263900587151027, 0.715168678767756, 0.07219231536073371),
    (0.01933081871559182, 0.11919477979462598, 0.9505321522496607)
  )

  /// The Bradford chromatic adaptation from D65 to D50.
  private static let d65ToD50: Matrix = (
    (1.0479298208405488, 0.022946793341019088, -0.05019222954313557),
    (0.029627815688159344, 0.990434484573249, -0.01707382502938514),
    (-0.009243058152591178, 0.015055144896577895, 0.7518742899580008)
  )

  private static let xyzToDisplayP3: Matrix = (
    (2.4934969119414254, -0.9313836179191239, -0.40271078445071684),
    (-0.8294889695615747, 1.7626640603183463, 0.023624685841943577),
    (0.03584583024378447, -0.07617238926804182, 0.9568845240076872)
  )

  private static let xyzToA98RGB: Matrix = (
    (2.0415879038107465, -0.5650069742788596, -0.34473135077832956),
    (-0.9692436362808795, 1.8759675015077202, 0.04155505740717557),
    (0.013444280632031142, -0.11836239223101838, 1.0151749943912054)
  )

  /// From XYZ whose white is D50.
  private static let xyzToProPhotoRGB: Matrix = (
    (1.3457868816471583, -0.25557208737979464, -0.05110186497554526),
    (-0.5446307051249019, 1.5082477428451468, 0.02052744743642139),
    (0, 0, 1.2119675456389452)
  )

  private static let xyzToRec2020: Matrix = (
    (1.7166511879712674, -0.35567078377639233, -0.25336628137365974),
    (-0.6666843518324892, 1.6164812366349395, 0.01576854581391113),
    (0.017639857445310783, -0.042770613257808524, 0.9421031212354738)
  )

  private static let xyzToLMS: Matrix = (
    (0.8190224379967030, 0.3619062600528904, -0.1288737815209879),
    (0.0329836539323885, 0.9292868615863434, 0.0361446663506424),
    (0.0481771893596242, 0.2642395317527308, 0.6335478284694309)
  )

  private static let lmsToOklab: Matrix = (
    (0.2104542683093140, 0.7936177747023054, -0.0040720430116193),
    (1.9779985324311684, -2.4285922420485799, 0.4505937096174110),
    (0.0259040424655478, 0.7827717124575296, -0.8086757548809700)
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

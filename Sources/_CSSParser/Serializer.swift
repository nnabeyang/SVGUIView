import Foundation

public protocol ToCSS {
  func toCSS(to: inout some TextOutputStream)
}

extension ToCSS {
  public func toCSSString() -> String {
    var string = ""
    toCSS(to: &string)
    return string
  }
}

func writeNumeric(value: Float32, intValue: Int32?, hasSign: Bool, dest: inout some TextOutputStream) {
  if hasSign {
    switch value.sign {
    case .plus:
      dest.write("+")
    case .minus:
      break
    }
  }
  dest.write(String(format: "%.4g", value))
}

extension Token: ToCSS {
  public func toCSS(to dest: inout some TextOutputStream) {
    switch self {
    case .ident(let value):
      serializeIdentifier(value, dest: &dest)
    case .atKeyword(let value):
      dest.write("@")
      serializeIdentifier(value, dest: &dest)
    case .hash(let value):
      dest.write("#")
      serializeIdentifier(value, dest: &dest)
    case .idHash(let value):
      dest.write("#")
      serializeIdentifier(value, dest: &dest)
    case .quotedString(let value):
      serializeString(value, dest: &dest)
    case .unquotedUrl(let value):
      dest.write("url(")
      serializeUnquotedUrl(value, dest: &dest)
      dest.write(")")
    case .delim(let value):
      dest.write(String([value]))
    case .number(let number):
      writeNumeric(value: number.value, intValue: number.intValue, hasSign: number.hasSign, dest: &dest)
    case .percentage(let percentage):
      writeNumeric(value: percentage.unitValue * 100, intValue: percentage.intValue, hasSign: percentage.hasSign, dest: &dest)
      dest.write("%")
    case .dimention(let dimention):
      writeNumeric(value: dimention.value, intValue: dimention.intValue, hasSign: dimention.hasSign, dest: &dest)
      let unit = dimention.unit
      if unit == "e" || unit == "E" || unit.starts(with: "e-") || unit.starts(with: "E-") {
        dest.write("\\65 ")
        serializeName(unit[unit.index(after: unit.startIndex)...], dest: &dest)
      } else {
        serializeName(unit, dest: &dest)
      }
    case .whitespace(let content):
      dest.write(content)
    case .comment(let content):
      dest.write("/*")
      dest.write(content)
      dest.write("*/")
    case .colon:
      dest.write(":")
    case .semicolon:
      dest.write(";")
    case .comma:
      dest.write(",")
    case .includeMatch:
      dest.write("~=")
    case .dashMatch:
      dest.write("|=")
    case .prefixMatch:
      dest.write("^=")
    case .suffixMatch:
      dest.write("$=")
    case .substringMatch:
      dest.write("*=")
    case .cdo:
      dest.write("<!--")
    case .cdc:
      dest.write("-->")
    case .function(let name):
      serializeIdentifier(name, dest: &dest)
      dest.write("(")
    case .parenthesisBlock:
      dest.write("(")
    case .squareBracketBlock:
      dest.write("[")
    case .curlyBracketBlock:
      dest.write("{")
    case .badUrl(let contents):
      dest.write("url(")
      dest.write(contents)
      dest.write(")")
    case .badString(let contents):
      dest.write("\"")
      var writer = CssStringWriter(&dest)
      writer.write(contents)
    case .closeParenthesis:
      dest.write(")")
    case .closeSquareBracket:
      dest.write("]")
    case .closeCurlyBracket:
      dest.write("}")
    }
  }
}

let hexDigits: [UInt8] = [
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
  0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
]

func hexEscape(_ byte: UInt8, dest: inout some TextOutputStream) {
  let bytes: [UInt8]
  if byte > 0x0F {
    let high: Int = Int(byte >> 4)
    let low: Int = Int(byte & 0x0F)
    bytes = [UInt8(ascii: "\\"), hexDigits[high], hexDigits[low], UInt8(ascii: " ")]
  } else {
    bytes = [UInt8(ascii: "\\"), hexDigits[Int(byte)], UInt8(ascii: " ")]
  }
  dest.write(String(decoding: bytes, as: UTF8.self))
}

func charEscape(_ byte: UInt8, dest: inout some TextOutputStream) {
  dest.write(String(decoding: [UInt8(ascii: "\\"), byte], as: UTF8.self))
}

func serializeIdentifier(_ value: String, dest: inout some TextOutputStream) {
  guard !value.isEmpty else {
    return
  }
  var value = value
  if value.hasPrefix("--") {
    dest.write("--")
    serializeName(value.dropFirst(2), dest: &dest)
  } else if value == "-" {
    dest.write("\\-")
  } else {
    switch value.first! {
    case "-":
      dest.write("-")
      value.removeFirst()
    case "0"..."9":
      let digit: Character = value.removeFirst()
      hexEscape(UInt8(digit.unicodeScalars.first!.value), dest: &dest)
    default:
      break
    }
    serializeName(value, dest: &dest)
  }
}

func serializeName(_ value: some StringProtocol, dest: inout some TextOutputStream) {
  let value = value.utf8
  var chunkStart = value.startIndex
  loop: for (i, b) in value.enumerated() {
    let escaped: String?
    switch b {
    case UInt8(ascii: "0")...UInt8(ascii: "9"),
      UInt8(ascii: "A")...UInt8(ascii: "Z"),
      UInt8(ascii: "a")...UInt8(ascii: "z"),
      UInt8(ascii: "-"),
      UInt8(ascii: "_"):
      continue loop
    case UInt8(ascii: "\0"):
      escaped = "\u{FFFD}"
    case let b:
      if !b.isASCII {
        continue loop
      }
      escaped = nil
    }
    let chunkEnd = value.index(value.startIndex, offsetBy: i)
    let chunk = String(decoding: value[chunkStart..<chunkEnd], as: UTF8.self)
    dest.write(chunk)
    if let escaped {
      dest.write(escaped)
    } else if (0x01...0x1F).contains(b) || b == 0x7F {
      hexEscape(b, dest: &dest)
    } else {
      charEscape(b, dest: &dest)
    }
    chunkStart = value.index(after: chunkEnd)
  }
  dest.write(String(decoding: value[chunkStart...], as: UTF8.self))
}

func serializeUnquotedUrl(_ value: some StringProtocol, dest: inout some TextOutputStream) {
  let value = value.utf8
  var chunkStart = value.startIndex
  loop: for (i, b) in value.enumerated() {
    let hex: Bool
    switch b {
    case UInt8(ascii: "\0")...UInt8(ascii: " "), 0x7F:
      hex = true
    case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "\\"):
      hex = false
    default:
      continue loop
    }
    let chunkEnd = value.index(value.startIndex, offsetBy: i)
    let chunk = String(decoding: value[chunkStart..<chunkEnd], as: UTF8.self)
    dest.write(chunk)
    if hex {
      hexEscape(b, dest: &dest)
    } else {
      charEscape(b, dest: &dest)
    }
    chunkStart = value.index(after: chunkEnd)
  }
  dest.write(String(decoding: value[chunkStart...], as: UTF8.self))
}

func serializeString(_ value: some StringProtocol, dest: inout some TextOutputStream) {
  dest.write("\"")
  var csw = CssStringWriter(&dest)
  csw.write(String(value))
  dest.write("\"")
}

public struct CssStringWriter<T: TextOutputStream>: TextOutputStream {
  private var inner: UnsafeMutablePointer<T>
  public init(_ inner: UnsafeMutablePointer<T>) {
    self.inner = inner
  }

  public mutating func write(_ string: String) {
    let string = string.utf8
    var chunkStart = string.startIndex
    loop: for (i, b) in string.enumerated() {
      let escaped: String?
      switch b {
      case UInt8(ascii: "\""):
        escaped = "\\\""
      case UInt8(ascii: "\\"):
        escaped = "\\\\"
      case UInt8(ascii: "\0"):
        escaped = "\u{FFFD}"
      default:
        continue loop
      }
      let chunkEnd = string.index(string.startIndex, offsetBy: i)
      inner.pointee.write(String(decoding: string[chunkStart..<chunkEnd], as: UTF8.self))
      switch escaped {
      case .some(let escaped):
        inner.pointee.write(escaped)
      case .none:
        hexEscape(b, dest: &inner.pointee)
      }
      chunkStart = string.index(after: chunkEnd)
    }
    inner.pointee.write(String(decoding: string[chunkStart...], as: UTF8.self))
  }
}

/// The source of the kernels of the filter primitives that `MetalFilterRenderer` encodes, which it compiles when it's
/// made, so that building the package doesn't need the Metal toolchain.
///
/// The textures hold premultiplied 8-bit pixels, which the kernels compute with as integers from 0 to 255, so that
/// they round as Core Graphics does.
let filterKernelSource = #"""
  #include <metal_stdlib>
  using namespace metal;

  /// A table that maps a premultiplied component and its alpha to the component and the alpha after an operation of
  /// Core Graphics or vImage, at `alpha * 256 + component`.
  struct ColorEntry {
    uchar color;
    uchar alpha;
  };

  /// The rectangle of pixels from `origin` up to `end` that a primitive draws into, and the offset that it moves what it
  /// draws by, in the rows and the columns of the textures.
  struct DrawArea {
    int2 origin;
    int2 end;
    int2 offset;
  };

  static uint4 readPixel(texture2d<float, access::read> texture, int2 position) {
    if (position.x < 0 || position.y < 0 || position.x >= int(texture.get_width())
        || position.y >= int(texture.get_height())) {
      return uint4(0);
    }
    return uint4(rint(texture.read(uint2(position)) * 255));
  }

  static void writePixel(texture2d<float, access::write> texture, uint4 pixel, uint2 position) {
    texture.write(float4(pixel) / 255, position);
  }

  static uint4 lookUp(uint4 pixel, device const ColorEntry *table) {
    uint row = pixel.a * 256;
    return uint4(table[row + pixel.r].color, table[row + pixel.g].color, table[row + pixel.b].color,
                 table[row + pixel.a].alpha);
  }

  static bool contains(constant DrawArea &area, uint2 position) {
    int2 p = int2(position);
    return all(p >= area.origin) && all(p < area.end);
  }

  /// Draws a texture through a table into the area of an empty texture, as Core Graphics draws an image with a color
  /// space conversion and an alpha into a cleared bitmap that's clipped to the area.
  kernel void drawImage(texture2d<float, access::read> source [[texture(0)]],
                        texture2d<float, access::write> destination [[texture(1)]],
                        device const ColorEntry *table [[buffer(0)]], constant DrawArea &area [[buffer(1)]],
                        uint2 position [[thread_position_in_grid]]) {
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
      return;
    }
    uint4 pixel = uint4(0);
    if (contains(area, position)) {
      pixel = lookUp(readPixel(source, int2(position) - area.offset), table);
    }
    writePixel(destination, pixel, position);
  }

  /// Converts a texture through a table, as vImage converts an image into a buffer of another color space.
  kernel void convertImage(texture2d<float, access::read> source [[texture(0)]],
                           texture2d<float, access::write> destination [[texture(1)]],
                           device const ColorEntry *table [[buffer(0)]], uint2 position [[thread_position_in_grid]]) {
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
      return;
    }
    writePixel(destination, lookUp(readPixel(source, int2(position)), table), position);
  }

  /// Keeps only the alpha of a texture, for `SourceAlpha`.
  kernel void dropColor(texture2d<float, access::read> source [[texture(0)]],
                        texture2d<float, access::write> destination [[texture(1)]],
                        uint2 position [[thread_position_in_grid]]) {
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
      return;
    }
    writePixel(destination, uint4(0, 0, 0, readPixel(source, int2(position)).a), position);
  }

  /// Fills the area of an empty texture with a color.
  kernel void fillArea(texture2d<float, access::write> destination [[texture(0)]], constant uint4 &color [[buffer(0)]],
                       constant DrawArea &area [[buffer(1)]], uint2 position [[thread_position_in_grid]]) {
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
      return;
    }
    writePixel(destination, contains(area, position) ? color : uint4(0), position);
  }

  /// The blend modes that `blendImage` computes, in the order of `MetalBlendMode`.
  enum BlendMode : uint {
    blendNormal,
    blendMultiply,
    blendScreen,
    blendOverlay,
    blendDarken,
    blendLighten,
    blendHardLight,
    blendDifference,
    blendExclusion,
  };

  static float hardLight(float source, float backdrop) {
    if (source <= 0.5) {
      return backdrop * 2 * source;
    }
    float screen = 2 * source - 1;
    return backdrop + screen - backdrop * screen;
  }

  static float blendComponent(uint mode, float source, float backdrop) {
    switch (mode) {
    case blendMultiply:
      return source * backdrop;
    case blendScreen:
      return source + backdrop - source * backdrop;
    case blendOverlay:
      return hardLight(backdrop, source);
    case blendDarken:
      return min(source, backdrop);
    case blendLighten:
      return max(source, backdrop);
    case blendHardLight:
      return hardLight(source, backdrop);
    case blendDifference:
      return abs(source - backdrop);
    case blendExclusion:
      return source + backdrop - 2 * source * backdrop;
    default:
      return source;
    }
  }

  /// Draws a texture through a table over another with a blend mode, as Core Graphics draws an image with a color
  /// space conversion, an alpha and a blend mode over a bitmap.
  kernel void blendImage(texture2d<float, access::read> source [[texture(0)]],
                         texture2d<float, access::read> backdrop [[texture(1)]],
                         texture2d<float, access::write> destination [[texture(2)]],
                         device const ColorEntry *table [[buffer(0)]], constant uint &mode [[buffer(1)]],
                         uint2 position [[thread_position_in_grid]]) {
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
      return;
    }
    uint4 s = lookUp(readPixel(source, int2(position)), table);
    uint4 d = readPixel(backdrop, int2(position));
    uint4 result;
    if (mode == blendNormal) {
      result = s + uint4(rint(float4(d) * float(255 - s.a) / 255));
    } else {
      float4 sp = float4(s) / 255;
      float4 dp = float4(d) / 255;
      float3 cs = sp.a > 0 ? sp.rgb / sp.a : float3(0);
      float3 cd = dp.a > 0 ? dp.rgb / dp.a : float3(0);
      float3 b = float3(blendComponent(mode, cs.r, cd.r), blendComponent(mode, cs.g, cd.g),
                        blendComponent(mode, cs.b, cd.b));
      float3 color = (1 - dp.a) * sp.rgb + (1 - sp.a) * dp.rgb + sp.a * dp.a * b;
      float alpha = sp.a + dp.a - sp.a * dp.a;
      result = uint4(rint(clamp(float4(color, alpha), 0.0, 1.0) * 255));
    }
    writePixel(destination, result, position);
  }

  /// The weights of a Gaussian kernel along one axis.
  struct GaussianPass {
    int radius;
    int2 step;
  };

  /// A pixel of a texture, or transparent black outside it.
  static float4 readEdge(texture2d<float, access::read> texture, int2 position) {
    int2 size = int2(texture.get_width(), texture.get_height());
    if (any(position < 0) || any(position >= size)) {
      return float4(0);
    }
    return texture.read(uint2(position));
  }

  /// Convolves a texture with the weights of a Gaussian kernel along one axis, into a texture of floats, or of 8-bit
  /// pixels rounded once at the end.
  kernel void gaussianPass(texture2d<float, access::read> source [[texture(0)]],
                           texture2d<float, access::write> destination [[texture(1)]],
                           constant float *weights [[buffer(0)]], constant GaussianPass &pass [[buffer(1)]],
                           constant uint &rounds [[buffer(2)]], uint2 position [[thread_position_in_grid]]) {
    if (position.x >= destination.get_width() || position.y >= destination.get_height()) {
      return;
    }
    float4 sum = float4(0);
    for (int i = -pass.radius; i <= pass.radius; i++) {
      sum += weights[i + pass.radius] * readEdge(source, int2(position) + i * pass.step);
    }
    destination.write(rounds != 0 ? rint(clamp(sum, 0.0, 1.0) * 255) / 255 : sum, position);
  }
  """#

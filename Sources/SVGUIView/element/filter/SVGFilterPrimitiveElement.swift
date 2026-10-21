/// A filter primitive element, whose attributes give the primitive subregion and the name of its result.
protocol SVGFilterPrimitiveElement: SVGElement {
  var x: SVGLength? { get }
  var y: SVGLength? { get }
  var width: SVGLength? { get }
  var height: SVGLength? { get }
  var result: String? { get }
}

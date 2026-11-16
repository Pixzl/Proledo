import AppKit
import CoreGraphics

func fillConic(_ ctx: CGContext, center: CGPoint, radius: CGFloat, stops: [(CGFloat, [CGFloat])], start: CGFloat) {
    let steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps)
        var lower = stops[0], upper = stops[stops.count - 1]
        for (a, b) in zip(stops, stops.dropFirst()) where t >= a.0 && t <= b.0 { lower = a; upper = b; break }
        let f = upper.0 > lower.0 ? (t - lower.0) / (upper.0 - lower.0) : 0
        let c = zip(lower.1, upper.1).map { $0 + ($1 - $0) * f }
        let a0 = start + t * 2 * .pi, a1 = start + (t + 1.5 / CGFloat(steps)) * 2 * .pi
        ctx.move(to: center)
        ctx.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(CGColor(red: c[0], green: c[1], blue: c[2], alpha: 1))
        ctx.fillPath()
    }
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.displayP3)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
                                                   CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: s / 2, y: body.maxY), end: CGPoint(x: s / 2, y: body.minY), options: [])

    let center = CGPoint(x: s / 2, y: s / 2)
    let r = body.width * 0.27
    let width = body.width * 0.085
    let ring = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r), transform: nil)
    let stroked = ring.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
    let stops: [(CGFloat, [CGFloat])] = [(0, [0.42, 0.36, 1.0]), (0.4, [0.95, 0.35, 0.75]),
                                         (0.7, [1.0, 0.62, 0.30]), (1, [0.42, 0.36, 1.0])]
    let conic = { fillConic(ctx, center: center, radius: r + width, stops: stops, start: .pi / 2) }

    for (blur, alpha) in [(0.12, 0.55), (0.05, 0.6)] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: body.width * blur, color: CGColor(red: 0.75, green: 0.4, blue: 1, alpha: alpha))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(stroked); ctx.clip()
        conic()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(stroked); ctx.clip()
    conic()
    ctx.restoreGState()

    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
    ctx.setLineWidth(max(1, s / 512))
    ctx.strokePath()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(drawIcon(size: base), to: "\(out)/icon_\(base)x\(base).png")
    writePNG(drawIcon(size: base * 2), to: "\(out)/icon_\(base)x\(base)@2x.png")
}
if CommandLine.arguments.count > 2 { writePNG(drawIcon(size: 512), to: CommandLine.arguments[2]) }
print("ok")

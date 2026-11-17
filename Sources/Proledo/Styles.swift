import CoreGraphics
import Foundation

private func speedFactor(_ speed: TopoOptions.Speed) -> Double {
    switch speed {
    case .calm: return 0.6
    case .normal: return 1
    case .lively: return 1.8
    }
}

private enum Silhouette {
    static func hills(width: Int, height: Int, horizon: Double, seed: UInt64) -> CGPath {
        let w = Double(width), h = Double(height)
        let unit = Double(min(width, height)) / 1440
        let noise = PerlinNoise(seed: seed ^ 0x7EE5)
        func ground(_ x: Double) -> Double {
            let u = x / w
            let frac = horizon + 0.045 * noise.noise(u * 2.6 + 5, 0.5) + 0.015 * noise.noise(u * 9 + 9, 2.5)
            return h * frac
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        var x = 0.0
        while x <= w {
            path.addLine(to: CGPoint(x: x, y: ground(x)))
            x += 3 * unit
        }
        path.addLine(to: CGPoint(x: w, y: ground(w)))
        path.addLine(to: CGPoint(x: w, y: 0))
        path.closeSubpath()

        return path
    }

    static func grass(width: Int, height: Int, seed: UInt64) -> CGPath {
        let w = Double(width), h = Double(height)
        let unit = Double(min(width, height)) / 1440
        let noise = PerlinNoise(seed: seed ^ 0x6A55)
        var random = SeededRandom(seed: seed ^ 0x6A55_6A55)
        func ground(_ x: Double) -> Double {
            h * (0.06 + 0.025 * (noise.noise(x / w * 3 + 2, 1.5) + 0.5))
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        var x = 0.0
        while x <= w {
            path.addLine(to: CGPoint(x: x, y: ground(x)))
            x += 4 * unit
        }
        path.addLine(to: CGPoint(x: w, y: 0))
        path.closeSubpath()
        x = 0
        while x < w {
            let base = ground(x) - 3 * unit
            let blade = unit * (18 + 70 * pow(random.unit(), 2))
            let lean = (random.unit() - 0.5) * blade * 0.6
            let thickness = unit * (1.6 + random.unit() * 1.8)
            path.move(to: CGPoint(x: x - thickness, y: base))
            path.addQuadCurve(to: CGPoint(x: x + lean, y: base + blade),
                              control: CGPoint(x: x - thickness * 0.5 + lean * 0.2, y: base + blade * 0.6))
            path.addQuadCurve(to: CGPoint(x: x + thickness, y: base),
                              control: CGPoint(x: x + thickness * 0.5 + lean * 0.2, y: base + blade * 0.6))
            path.closeSubpath()
            x += unit * (2 + random.unit() * 5)
        }
        return path
    }
}

final class AuroraGenerator: FrameRenderer, @unchecked Sendable {
    let width: Int
    let height: Int
    let bitRateFactor = 1.15

    private struct Curtain {
        let base: Double
        let amplitude: Double
        let feature: Double
        let reach: Double
        let brightness: Double
        let ox: Double
        let oy: Double
        let phase: Double
        let red: Double
    }

    private let lowWidth: Int
    private let lowHeight: Int
    private let noise: PerlinNoise
    private let radius: Double
    private let curtains: [Curtain]
    private let horizon: Double?
    private let silhouette: CGPath?
    private let stars: StarfieldGenerator

    init(width: Int, height: Int, options: TopoOptions) {
        self.width = width
        self.height = height
        lowWidth = max(64, width / 2)
        lowHeight = max(36, height / 2)
        noise = PerlinNoise(seed: options.seed)
        var random = SeededRandom(seed: options.seed ^ 0x51ED_2701)

        let distance = 0.05 * speedFactor(options.speed) * Double(options.seconds)
        radius = distance / (2 * .pi)

        let count: Int
        switch options.density {
        case .loose: count = 1
        case .normal: count = 2
        case .dense: count = 3
        }
        let portrait = height > width
        let top = portrait ? 0.32 : 0.36
        curtains = (0..<count).map { i in
            Curtain(base: top + 0.11 * Double(i) + random.unit() * 0.07,
                    amplitude: 0.09 + random.unit() * 0.06,
                    feature: 0.6 + random.unit() * 0.4,
                    reach: ((portrait ? 0.2 : 0.3) + random.unit() * 0.1) * (count == 1 ? 1 : 0.75 + 0.35 * Double(i) / Double(count - 1)),
                    brightness: count == 1 ? 0.85 : 0.55 + 0.3 * Double(i) / Double(count - 1),
                    ox: random.unit() * 60, oy: random.unit() * 60,
                    phase: random.unit() * 2 * .pi,
                    red: 0.4 + random.unit() * 0.6)
        }

        let horizonFrac = portrait ? 0.12 : 0.16
        horizon = options.landscape ? 1 - horizonFrac : nil
        silhouette = options.landscape
            ? Silhouette.hills(width: width, height: height, horizon: horizonFrac, seed: options.seed)
            : nil

        var starOptions = options
        starOptions.style = .stars
        starOptions.density = .loose
        starOptions.milkyWay = false
        starOptions.speed = .calm
        starOptions.seed = options.seed ^ 0x57A2
        stars = StarfieldGenerator(width: width, height: height, options: starOptions)
    }

    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext) {
        let theta = 2 * .pi * Double(frame) / Double(max(total, 1))
        guard let low = Wallpaper.makeContext(width: lowWidth, height: lowHeight), let data = low.data else { return }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = low.bytesPerRow
        let lw = lowWidth, lh = lowHeight
        let minDim = Double(min(lw, lh))
        let horizon = self.horizon

        DispatchQueue.concurrentPerform(iterations: lw) { x in
            var red = [Double](repeating: 0, count: lh)
            var green = [Double](repeating: 0, count: lh)
            var blue = [Double](repeating: 0, count: lh)
            var sum = 0.0
            for c in curtains {
                let su = Double(x) / (minDim * c.feature)
                let scx = radius * cos(theta + c.phase), scy = radius * sin(theta + c.phase)
                let smooth = noise.noise(su * 1.7 + scx * 1.3 + c.ox + 17, scy * 1.3 + c.oy - 9)
                sum += pow(max(0, 0.3 + smooth * 1.35), 2.0) * c.brightness
            }
            for c in curtains {
                let u = Double(x) / (minDim * c.feature)
                let cx = radius * cos(theta + c.phase), cy = radius * sin(theta + c.phase)
                let base = c.base + c.amplitude * noise.noise(u * 0.9 + cx + c.ox, cy + c.oy)
                    + c.amplitude * 0.25 * noise.noise(u * 2.2 + cx * 1.4 + c.ox - 5, cy * 1.4 + c.oy + 8)
                    + c.amplitude * 0.5 * noise.noise(u * 0.4 + cx * 0.6 + c.ox + 11, cy * 0.6 + c.oy - 3)
                let band = noise.noise(u * 1.7 + cx * 1.3 + c.ox + 17, cy * 1.3 + c.oy - 9)
                    + 0.35 * noise.noise(u * 5 + cx * 2.2 + 3, cy * 2.2 - 14)
                let intensity = pow(max(0, 0.3 + band * 1.35), 2.0) * c.brightness
                guard intensity > 0.002 else { continue }
                let ray1 = max(0, min(1, 0.5 + 1.8 * noise.noise(u * 34 + cx * 3, cy * 3 + 40)))
                let ray2 = max(0, min(1, 0.5 + 1.4 * noise.noise(u * 11 + cx * 1.5, cy * 1.5 + 70)))
                let rays = 0.25 + 0.75 * pow(ray1, 1.6) * (0.5 + 0.5 * ray2)
                let reach = c.reach * (0.45 + 0.9 * ray2)
                    * (0.8 + 0.4 * max(0, min(1, 0.5 + noise.noise(u * 1.2 + 33 + cx, cy - 21))))
                let strength = intensity * rays
                for y in 0..<lh {
                    let fy = Double(y) / Double(lh)
                    let t = (base - fy) / reach
                    if t >= 0 {
                        let profile = 0.55 * exp(-t * 1.9) + 0.75 * exp(-t * 11)
                        let v = strength * profile
                        guard v > 0.0008 else { continue }
                        let lift = min(1, t / 0.9)
                        let high = max(0, t - 0.7) * c.red
                        red[y] += v * (0.32 - 0.22 * lift + 0.9 * high)
                        green[y] += v * (1.0 - 0.1 * lift - 0.75 * high)
                        blue[y] += v * (0.36 + 0.12 * lift + 0.25 * high)
                    } else {
                        let d = t * reach
                        let edge = exp(-(d * d) / 0.00004) * 0.8 + exp(d / 0.03) * 0.12
                        let fringe = exp(-((d + 0.007) * (d + 0.007)) / 0.00004) * max(0, intensity - 0.35)
                        let v = strength * edge
                        red[y] += v * 0.32 + strength * fringe * 0.22
                        green[y] += v * 1.0
                        blue[y] += v * 0.36 + strength * fringe * 0.14
                    }
                }
                for y in 0..<lh {
                    let fy = Double(y) / Double(lh)
                    let scatter = intensity * 0.07 * exp(-abs(fy - (base - c.reach * 0.2)) / 0.2)
                    green[y] += scatter * 0.8
                    blue[y] += scatter * 0.45
                    red[y] += scatter * 0.12
                }
            }
            if let horizon {
                let glow = min(1.2, sum * 0.9)
                for y in 0..<lh {
                    let fy = Double(y) / Double(lh)
                    guard fy < horizon else { break }
                    let haze = glow * 0.2 * exp(-(horizon - fy) / 0.09)
                    red[y] += haze * 0.1
                    green[y] += haze * 0.7
                    blue[y] += haze * 0.55
                }
            }
            for y in 0..<lh {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = UInt8(min(255, blue[y] * 255))
                pixels[offset + 1] = UInt8(min(255, green[y] * 255))
                pixels[offset + 2] = UInt8(min(255, red[y] * 255))
                pixels[offset + 3] = 255
            }
        }

        guard let image = low.makeImage() else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        stars.overlay(frame: frame, total: total, fps: fps, gain: 0.7, into: ctx)
        if let silhouette {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.addPath(silhouette)
            ctx.fillPath()
        }
    }
}

final class FireflyGenerator: FrameRenderer, @unchecked Sendable {
    let width: Int
    let height: Int
    let bitRateFactor = 1.0

    private struct Firefly {
        let x: Double
        let y: Double
        let reach: Double
        let ox: Double
        let oy: Double
        let size: Double
        let brightness: Double
        let flashes: Int
        let phase: Double
        let layer: Int
        let color: (CGFloat, CGFloat, CGFloat)
    }

    private let scale: Double
    private let radius: Double
    private let noise: PerlinNoise
    private let flies: [Firefly]
    private let grass: CGPath

    init(width: Int, height: Int, options: TopoOptions) {
        self.width = width
        self.height = height
        let unit = Double(min(width, height)) / 1440
        scale = unit
        noise = PerlinNoise(seed: options.seed)
        var random = SeededRandom(seed: options.seed ^ 0xF1F1_F1F1)

        let distance = 0.06 * speedFactor(options.speed) * Double(options.seconds)
        radius = distance / (2 * .pi)

        let perArea: Double
        switch options.density {
        case .loose: perArea = 22
        case .normal: perArea = 45
        case .dense: perArea = 85
        }
        let count = max(4, Int(perArea * Double(width * height) / (2560 * 1440)))
        let w = Double(width), h = Double(height)
        let seconds = Double(options.seconds)
        flies = (0..<count).map { _ in
            let pick = random.unit()
            let layer = pick < 0.18 ? 0 : pick < 0.92 ? 1 : 2
            let tint = random.unit()
            let color: (CGFloat, CGFloat, CGFloat) = tint < 0.7 ? (0.82, 1, 0.3) : tint < 0.9 ? (1, 0.9, 0.35) : (0.7, 1, 0.45)
            let period = 4 + random.unit() * 6
            let lift = pow(random.unit(), 1.6)
            return Firefly(x: random.unit() * w, y: h * (0.08 + lift * 0.7),
                           reach: min(w, h) * (0.12 + random.unit() * 0.16),
                           ox: random.unit() * 80, oy: random.unit() * 80,
                           size: layer == 1 ? 2.0 + random.unit() * 1.2 : layer == 0 ? 3 + random.unit() * 1.5 : 8 + random.unit() * 5,
                           brightness: layer == 1 ? 0.8 + random.unit() * 0.2 : layer == 0 ? 0.35 + random.unit() * 0.2 : 0.22 + random.unit() * 0.15,
                           flashes: max(1, Int((seconds / period).rounded())),
                           phase: random.unit(),
                           layer: layer, color: color)
        }
        grass = Silhouette.grass(width: width, height: height, seed: options.seed)
    }

    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext) {
        let theta = 2 * .pi * Double(frame) / Double(max(total, 1))
        let progress = Double(frame) / Double(max(total, 1))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!

        func drawFly(_ fly: Firefly) {
            let cx = radius * cos(theta), cy = radius * sin(theta)
            let x = fly.x + fly.reach * noise.noise(cx + fly.ox, cy + fly.oy)
            let y = fly.y + fly.reach * 0.5 * noise.noise(cx + fly.ox + 31, cy + fly.oy - 17)
            let p = (progress * Double(fly.flashes) + fly.phase).truncatingRemainder(dividingBy: 1)
            let flash = p < 0.04 ? p / 0.04 : exp(-(p - 0.04) * 6)
            let glow = fly.brightness * (0.04 + 0.96 * flash)
            guard glow > 0.01 else { return }
            let (r, g, b) = fly.color
            let sharp = fly.layer == 1
            let outer = CGFloat(fly.size * (sharp ? 11 : 4) * scale)
            let colors = [CGColor(red: r, green: g, blue: b, alpha: CGFloat(glow * (sharp ? 0.75 : 0.7))),
                          CGColor(red: r, green: g, blue: b, alpha: CGFloat(glow * (sharp ? 0.2 : 0.55))),
                          CGColor(red: r, green: g, blue: b, alpha: 0)] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, sharp ? 0.2 : 0.75, 1])!
            let center = CGPoint(x: x, y: y)
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: outer, options: [])
            if sharp {
                let core = CGFloat(fly.size * 1.1 * scale)
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0.82, alpha: CGFloat(min(1, glow * 1.1))))
                ctx.fillEllipse(in: CGRect(x: x - core, y: y - core, width: core * 2, height: core * 2))
            }
        }

        ctx.setBlendMode(.plusLighter)
        for fly in flies where fly.layer < 2 { drawFly(fly) }
        ctx.setBlendMode(.normal)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(grass)
        ctx.fillPath()
        ctx.setBlendMode(.plusLighter)
        for fly in flies where fly.layer == 2 { drawFly(fly) }
        ctx.setBlendMode(.normal)
    }
}

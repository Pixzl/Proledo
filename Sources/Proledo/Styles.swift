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

final class SilkGenerator: FrameRenderer, @unchecked Sendable {
    let width: Int
    let height: Int
    let bitRateFactor = 1.2
    let deepColor = true

    private let gridWidth: Int
    private let gridHeight: Int
    private let cell: Double
    private let noise: PerlinNoise
    private let radius: Double
    private let levelStep: Double
    private let rimWidth: CGFloat
    private let phase: (Double, Double)
    private let light: (Double, Double)
    private let buckets = 8
    private let options: TopoOptions
    private let balanced: Bool
    private let balanceLock = NSLock()
    private var balance: (map: [Double], width: Int, height: Int)?

    init(width: Int, height: Int, options: TopoOptions, balanced: Bool = true) {
        self.width = width
        self.height = height
        self.options = options
        self.balanced = balanced
        cell = 2
        gridWidth = Int(Double(width) / cell) + 2
        gridHeight = Int(Double(height) / cell) + 2
        noise = PerlinNoise(seed: options.seed)
        var random = SeededRandom(seed: options.seed ^ 0x51C0_51C0)
        let distance = 0.045 * speedFactor(options.speed) * Double(options.seconds)
        radius = distance / (2 * .pi)
        switch options.density {
        case .loose: levelStep = 0.34
        case .normal: levelStep = 0.25
        case .dense: levelStep = 0.17
        }
        let unit = Double(min(width, height)) / 1440
        rimWidth = CGFloat((options.lines == .bold ? 2.4 : 1.6) * unit)
        phase = (random.unit() * 2 * .pi, random.unit() * 2 * .pi)
        let angle = (200 + random.unit() * 40) * .pi / 180
        light = (cos(angle), sin(angle))
    }

    private func balanceMap(total: Int, fps: Int) -> (map: [Double], width: Int, height: Int)? {
        guard balanced else { return nil }
        balanceLock.lock()
        defer { balanceLock.unlock() }
        if let balance { return balance }
        let scale = 270 / Double(min(width, height))
        let sw = max(16, Int(Double(width) * scale)), sh = max(16, Int(Double(height) * scale))
        let probe = SilkGenerator(width: sw, height: sh, options: options, balanced: false)
        let samples = 96
        var lut = [Double](repeating: 0, count: 256)
        for i in 0..<256 {
            let c = Double(i) / 255
            lut[i] = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var sum = [Double](repeating: 0, count: sw * sh)
        let sumLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: samples) { k in
            guard let small = Wallpaper.makeContext(width: sw, height: sh), let data = small.data else { return }
            probe.draw(frame: k * max(total, 1) / samples, total: total, fps: fps, into: small)
            let pixels = data.assumingMemoryBound(to: UInt8.self)
            let row = small.bytesPerRow
            var local = [Double](repeating: 0, count: sw * sh)
            for y in 0..<sh {
                for x in 0..<sw { local[y * sw + x] = lut[Int(pixels[y * row + x * 4 + 1])] }
            }
            sumLock.lock()
            for i in 0..<local.count { sum[i] += local[i] }
            sumLock.unlock()
        }
        let radius = max(2, sh / 30)
        for _ in 0..<3 { sum = Self.boxBlur(sum, width: sw, height: sh, radius: radius) }
        let peak = sum.max() ?? 0
        let lit = sum.filter { $0 > peak * 0.05 }.sorted()
        var map = [Double](repeating: 1, count: sw * sh)
        if !lit.isEmpty {
            let cap = lit[Int(Double(lit.count - 1) * 0.7)]
            var before = 0.0, after = 0.0
            for i in 0..<map.count {
                if sum[i] > cap { map[i] = pow(cap / sum[i], 0.45) }
                before += sum[i]
                after += sum[i] * pow(map[i], 2.2)
            }
            let lift = after > 0 ? min(1.08, pow(before / after, 1 / 2.2)) : 1
            for i in 0..<map.count { map[i] *= lift }
        }
        balance = (map, sw, sh)
        return balance
    }

    private static func boxBlur(_ values: [Double], width: Int, height: Int, radius: Int) -> [Double] {
        var horizontal = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            var acc = 0.0
            for x in -radius...radius { acc += values[y * width + min(width - 1, max(0, x))] }
            for x in 0..<width {
                horizontal[y * width + x] = acc / Double(2 * radius + 1)
                acc += values[y * width + min(width - 1, x + radius + 1)] - values[y * width + max(0, x - radius)]
            }
        }
        var result = [Double](repeating: 0, count: values.count)
        for x in 0..<width {
            var acc = 0.0
            for y in -radius...radius { acc += horizontal[min(height - 1, max(0, y)) * width + x] }
            for y in 0..<height {
                result[y * width + x] = acc / Double(2 * radius + 1)
                acc += horizontal[min(height - 1, y + radius + 1) * width + x] - horizontal[max(0, y - radius) * width + x]
            }
        }
        return result
    }

    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext) {
        let theta = 2 * .pi * Double(frame) / Double(max(total, 1))
        let gw = gridWidth, gh = gridHeight
        let balance = balanceMap(total: total, fps: fps)
        let cellSize = cell, fullWidth = Double(width), fullHeightValue = Double(height)
        func gain(_ i: Int, _ j: Int) -> Double {
            guard let balance else { return 1 }
            let x = min(balance.width - 1, max(0, Int(Double(i) * cellSize / fullWidth * Double(balance.width))))
            let y = min(balance.height - 1, max(0, Int(Double(j) * cellSize / fullHeightValue * Double(balance.height))))
            return balance.map[y * balance.width + x]
        }
        let minDim = Double(min(gw, gh))
        let centerX = Double(gw) * (0.5 + 0.17 * cos(theta + phase.0))
        let centerY = Double(gh) * (0.5 + 0.13 * sin(2 * theta + phase.1))
        let blob = minDim * 0.62
        let mx = radius * cos(theta), my = radius * sin(theta)

        let field = UnsafeMutableBufferPointer<Double>.allocate(capacity: gw * gh)
        let fade = UnsafeMutableBufferPointer<Double>.allocate(capacity: gw * gh)
        defer { field.deallocate(); fade.deallocate() }

        DispatchQueue.concurrentPerform(iterations: gh) { j in
            for i in 0..<gw {
                let dx = (Double(i) - centerX) / blob, dy = (Double(j) - centerY) / blob
                let r = sqrt(dx * dx + dy * dy)
                let index = j * gw + i
                guard r < 1.3 else { field[index] = .nan; fade[index] = 0; continue }
                let qx = noise.noise(dx * 0.7 + mx + 3.1, dy * 0.7 + my - 1.7)
                let qy = noise.noise(dx * 0.7 - my + 7.7, dy * 0.7 + mx + 2.9)
                let a = atan2(dy, dx)
                let swirl = min(1, r * 2.5)
                field[index] = r * 2.1
                    + 1.15 * noise.noise(dx * 0.75 + 2.4 * qx + mx * 0.6, dy * 0.75 + 2.4 * qy + my * 0.6)
                    + 0.35 * swirl * sin(2 * a + 2.6 * qx + theta)
                let edge = 1.12 + 0.28 * noise.noise(dx * 0.9 + 10 + mx * 0.5, dy * 0.9 - 4 + my * 0.5)
                let m = max(0, min(1, (edge - r) / 0.42))
                fade[index] = m * m * (3 - 2 * m)
            }
        }

        let deep = ctx.bitsPerComponent > 8
        guard let low = deep ? Wallpaper.makeDeepContext(width: gw, height: gh) : Wallpaper.makeContext(width: gw, height: gh),
              let data = low.data else { return }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let wide = data.assumingMemoryBound(to: UInt16.self)
        let bytesPerRow = low.bytesPerRow
        let seed = UInt64(truncatingIfNeeded: frame) &* 0x9E37_79B9_7F4A_7C15
        let step = levelStep
        let lx = light.0, ly = light.1

        func gradient(_ i: Int, _ j: Int) -> (Double, Double)? {
            let i0 = max(0, i - 1), i1 = min(gw - 1, i + 1), j0 = max(0, j - 1), j1 = min(gh - 1, j + 1)
            let a = field[j * gw + i1], b = field[j * gw + i0], c = field[j1 * gw + i], d = field[j0 * gw + i]
            guard !a.isNaN, !b.isNaN, !c.isNaN, !d.isNaN else { return nil }
            let gx = (a - b) / Double(i1 - i0), gy = (c - d) / Double(j1 - j0)
            let length = sqrt(gx * gx + gy * gy)
            guard length > 1e-9 else { return nil }
            return (gx / length, gy / length)
        }

        DispatchQueue.concurrentPerform(iterations: gh) { j in
            for i in 0..<gw {
                let index = j * gw + i
                let offset = j * bytesPerRow + i * 4
                let h = field[index], m = fade[index]
                var value = 0.0
                if !h.isNaN, m > 0, let g = gradient(i, j) {
                    let f = h / step - floor(h / step)
                    let facing = 0.5 + 0.5 * (g.0 * lx + g.1 * ly)
                    let shade = 0.15 + 0.85 * facing
                    let body = 0.09 * pow(f, 1.4) * shade
                    let gloss = 0.17 * exp(-pow((f - 0.8) / 0.1, 2)) * pow(facing, 2.2)
                    let occlusion = min(1, f / 0.28)
                    let groove = 1 - 0.65 * exp(-pow((f - 0.965) / 0.022, 2))
                    value = (0.006 + body + gloss) * occlusion * occlusion * (3 - 2 * occlusion) * groove * m * gain(i, j)
                }
                if deep {
                    var z = seed ^ (UInt64(index) &* 0xBF58_476D_1CE4_E5B9)
                    z = (z ^ (z >> 29)) &* 0x94D0_49BB_1331_11EB
                    let noise = value > 0 ? (Double(z >> 40 & 0xFFFF) + Double(z >> 20 & 0xFFFF)) / 65535 - 1 : 0
                    let w = j * (bytesPerRow / 2) + i * 4
                    let level = max(0, min(65535, value * 65535 + noise * 64))
                    wide[w] = UInt16(level)
                    wide[w + 1] = UInt16(level)
                    wide[w + 2] = UInt16(max(0, min(65535, value * 0.97 * 65535 + noise * 64)))
                    wide[w + 3] = 65535
                } else {
                    let v = UInt8(min(255, value * 255))
                    pixels[offset] = v
                    pixels[offset + 1] = v
                    pixels[offset + 2] = UInt8(min(255, value * 0.97 * 255))
                    pixels[offset + 3] = 255
                }
            }
        }

        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let image = low.makeImage() {
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: Double(height) - Double(gh) * cell, width: Double(gw) * cell, height: Double(gh) * cell))
        }

        var paths = (0..<buckets).map { _ in CGMutablePath() }
        let fullHeight = Double(height)
        let c = cell
        for j in 0..<(gh - 1) {
            for i in 0..<(gw - 1) {
                let a = field[j * gw + i], b = field[j * gw + i + 1]
                let cc = field[(j + 1) * gw + i + 1], d = field[(j + 1) * gw + i]
                if a.isNaN || b.isNaN || cc.isNaN || d.isNaN { continue }
                let lo = min(min(a, b), min(cc, d)), hi = max(max(a, b), max(cc, d))
                let first = Int(floor(lo / step)) + 1, last = Int(floor(hi / step))
                guard first <= last else { continue }
                let m = fade[j * gw + i]
                guard m > 0.02, let g = gradient(i, j) else { continue }
                let facing = max(0, g.0 * lx + g.1 * ly)
                let brightness = pow(facing, 1.5) * m * gain(i, j)
                guard brightness > 0.025 else { continue }
                let bucket = min(buckets - 1, Int(brightness * Double(buckets)))
                for k in first...last {
                    let level = Double(k) * step
                    var idx = 0
                    if a > level { idx |= 1 }
                    if b > level { idx |= 2 }
                    if cc > level { idx |= 4 }
                    if d > level { idx |= 8 }
                    if idx == 0 || idx == 15 { continue }
                    let x0 = Double(i) * c, y0 = Double(j) * c
                    func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: fullHeight - y) }
                    let top = point(x0 + (level - a) / (b - a) * c, y0)
                    let right = point(x0 + c, y0 + (level - b) / (cc - b) * c)
                    let bottom = point(x0 + (level - d) / (cc - d) * c, y0 + c)
                    let left = point(x0, y0 + (level - a) / (d - a) * c)
                    func segment(_ p: CGPoint, _ q: CGPoint) { paths[bucket].move(to: p); paths[bucket].addLine(to: q) }
                    switch idx {
                    case 1, 14: segment(left, top)
                    case 2, 13: segment(top, right)
                    case 3, 12: segment(left, right)
                    case 4, 11: segment(right, bottom)
                    case 6, 9: segment(top, bottom)
                    case 7, 8: segment(left, bottom)
                    case 5: segment(left, top); segment(right, bottom)
                    case 10: segment(top, right); segment(left, bottom)
                    default: break
                    }
                }
            }
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(rimWidth)
        for (index, path) in paths.enumerated() where !path.isEmpty {
            let v = CGFloat((Double(index) + 0.5) / Double(buckets))
            ctx.setStrokeColor(CGColor(red: v, green: v, blue: v * 0.98, alpha: 1))
            ctx.addPath(path)
            ctx.strokePath()
        }
        paths.removeAll()
    }
}

final class NebulaGenerator: FrameRenderer, @unchecked Sendable {
    let width: Int
    let height: Int
    let bitRateFactor = 1.3
    let deepColor = true

    private let stars: StarfieldGenerator
    private let shape: PerlinNoise
    private let warp: PerlinNoise
    private let tint: PerlinNoise
    private let grain: PerlinNoise
    private let step: Int
    private let cols: Int
    private let rows: Int
    private let unit: Double
    private let low: Double
    private let high: Double
    private let brightness: Double
    private let radius: Double
    private let cycles: Double
    private let phase: Double

    init(width: Int, height: Int, options: TopoOptions) {
        self.width = width
        self.height = height
        var starOptions = options
        starOptions.milkyWay = false
        stars = StarfieldGenerator(width: width, height: height, options: starOptions)
        shape = PerlinNoise(seed: options.seed ^ 0x4E42_554C)
        warp = PerlinNoise(seed: options.seed ^ 0x5741_5250)
        tint = PerlinNoise(seed: options.seed ^ 0x5449_4E54)
        grain = PerlinNoise(seed: options.seed ^ 0x4752_4149)
        step = max(2, min(width, height) / 360)
        cols = width / step + 2
        rows = height / step + 2
        unit = Double(min(width, height))
        switch options.density {
        case .loose: (low, high, brightness) = (0.08, 0.42, 0.26)
        case .normal: (low, high, brightness) = (0.0, 0.36, 0.32)
        case .dense: (low, high, brightness) = (-0.06, 0.3, 0.27)
        }
        let pace: Double
        switch options.speed {
        case .calm: pace = 0.006
        case .normal: pace = 0.0105
        case .lively: pace = 0.016
        }
        radius = pace * Double(options.seconds)
        cycles = 1
        var random = SeededRandom(seed: options.seed ^ 0x9E37)
        phase = random.unit() * 2 * .pi
    }

    private func fbm(_ noise: PerlinNoise, _ x: Double, _ y: Double, octaves: Int) -> Double {
        var sum = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for octave in 0..<octaves {
            sum += amplitude * noise.noise(x * frequency + Double(octave) * 17.3, y * frequency - Double(octave) * 9.1)
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2.03
        }
        return sum / norm
    }

    private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private func color(hue: Double, saturation: Double, value: Double) -> (Double, Double, Double) {
        let h = (hue - floor(hue)) * 6
        let i = Int(h) % 6, f = h - floor(h)
        let p = value * (1 - saturation), q = value * (1 - saturation * f), t = value * (1 - saturation * (1 - f))
        switch i {
        case 0: return (value, t, p)
        case 1: return (q, value, p)
        case 2: return (p, value, t)
        case 3: return (p, q, value)
        case 4: return (t, p, value)
        default: return (value, p, q)
        }
    }

    private func nebula(at progress: Double) -> CGImage? {
        guard let ctx = Wallpaper.makeDeepContext(width: cols, height: rows) else { return nil }
        let buffer = ctx.data!.assumingMemoryBound(to: UInt16.self)
        let stride = ctx.bytesPerRow / 2
        let angle = 2 * .pi * cycles * progress
        let ox = cos(angle + phase) * radius, oy = sin(angle + phase) * radius
        let wx = cos(-angle + phase * 1.7) * radius * 0.6, wy = sin(-angle + phase * 1.7) * radius * 0.6
        let cell = Double(step)
        DispatchQueue.concurrentPerform(iterations: rows) { j in
            for i in 0..<cols {
                let u = Double(i) * cell / unit, v = Double(j) * cell / unit
                let bend = fbm(warp, u * 0.9 + wx, v * 0.9 + wy, octaves: 3)
                let n = fbm(shape, u * 1.3 + bend * 1.6 + ox, v * 1.3 + oy, octaves: 5)
                let mask = smooth(low, high, n)
                var value = 0.0, rgb = (0.0, 0.0, 0.0)
                if mask > 0 {
                    let detail = 0.75 + 0.25 * (0.5 + fbm(grain, u * 6 + ox, v * 6 + oy, octaves: 3))
                    value = mask * brightness * detail
                    let swirl = fbm(tint, u * 0.6 + ox * 0.5, v * 0.6 + oy * 0.5, octaves: 2)
                    let hue = 0.7 + 0.2 * sin(2 * .pi * (swirl * 1.6 + u * 0.15 + progress * cycles))
                    rgb = color(hue: hue, saturation: 0.75, value: value)
                }
                let o = j * stride + i * 4
                buffer[o] = UInt16(min(65535, rgb.0 * 65535))
                buffer[o + 1] = UInt16(min(65535, rgb.1 * 65535))
                buffer[o + 2] = UInt16(min(65535, rgb.2 * 65535))
                buffer[o + 3] = 65535
            }
        }
        return ctx.makeImage()
    }

    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let image = nebula(at: Double(frame) / Double(max(total, 1))) {
            ctx.saveGState()
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: Double(height - (rows - 0) * step), width: Double(cols * step), height: Double(rows * step)))
            ctx.restoreGState()
        }
        stars.overlay(frame: frame, total: total, fps: fps, gain: 1, into: ctx)
    }
}

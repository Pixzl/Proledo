import CoreGraphics
import Foundation

private func speedFactor(_ speed: TopoOptions.Speed) -> Double {
    switch speed {
    case .calm: return 0.6
    case .normal: return 1
    case .lively: return 1.8
    }
}

final class AuroraGenerator: FrameRenderer, @unchecked Sendable {
    let width: Int
    let height: Int
    let bitRateFactor = 1.0

    private struct Curtain {
        let base: Double
        let amplitude: Double
        let feature: Double
        let reach: Double
        let brightness: Double
        let ox: Double
        let oy: Double
        let phase: Double
        let violet: Double
    }

    private let lowWidth: Int
    private let lowHeight: Int
    private let noise: PerlinNoise
    private let radius: Double
    private let curtains: [Curtain]
    private let ridge: [Double]?

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
        let top = portrait ? 0.3 : 0.4
        curtains = (0..<count).map { i in
            Curtain(base: top + 0.1 * Double(i) + random.unit() * 0.08,
                    amplitude: 0.1 + random.unit() * 0.07,
                    feature: 0.6 + random.unit() * 0.4,
                    reach: (portrait ? 0.16 : 0.24) + random.unit() * 0.1,
                    brightness: 0.85 - 0.18 * Double(i),
                    ox: random.unit() * 60, oy: random.unit() * 60,
                    phase: random.unit() * 2 * .pi,
                    violet: 0.3 + random.unit() * 0.5)
        }

        if options.landscape {
            let ridgeNoise = PerlinNoise(seed: options.seed ^ 0x77AA)
            let w = Double(lowWidth)
            let horizon = portrait ? 0.9 : 0.86
            ridge = (0..<lowWidth).map { x in
                let u = Double(x) / w
                return horizon + 0.05 * ridgeNoise.noise(u * 3.1 + 5, 0.5) + 0.02 * ridgeNoise.noise(u * 11 + 9, 2.5)
            }
        } else {
            ridge = nil
        }
    }

    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext) {
        let theta = 2 * .pi * Double(frame) / Double(max(total, 1))
        guard let low = Wallpaper.makeContext(width: lowWidth, height: lowHeight), let data = low.data else { return }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = low.bytesPerRow
        let lw = lowWidth, lh = lowHeight
        let minDim = Double(min(lw, lh))

        DispatchQueue.concurrentPerform(iterations: lw) { x in
            var red = [Double](repeating: 0, count: lh)
            var green = [Double](repeating: 0, count: lh)
            var blue = [Double](repeating: 0, count: lh)
            for c in curtains {
                let u = Double(x) / (minDim * c.feature)
                let cx = radius * cos(theta + c.phase), cy = radius * sin(theta + c.phase)
                let base = c.base + c.amplitude * noise.noise(u * 0.9 + cx + c.ox, cy + c.oy)
                    + c.amplitude * 0.35 * noise.noise(u * 3.4 + cx * 1.7 + c.ox - 5, cy * 1.7 + c.oy + 8)
                let band = noise.noise(u * 1.7 + cx * 1.3 + c.ox + 17, cy * 1.3 + c.oy - 9)
                let intensity = pow(max(0, 0.42 + band * 1.1), 1.6) * c.brightness
                guard intensity > 0.002 else { continue }
                let fine = noise.noise(u * 22 + cx * 2.5, cy * 2.5 + 40) * 0.6 + noise.noise(u * 7 + cx, cy + 70) * 0.4
                let rays = 0.4 + 0.6 * max(0, min(1, 0.5 + fine * 1.6))
                let reach = c.reach * (0.7 + 0.6 * max(0, min(1, 0.5 + noise.noise(u * 1.2 + 33 + cx, cy - 21))))
                for y in 0..<lh {
                    let fy = Double(y) / Double(lh)
                    let t = (base - fy) / reach
                    let profile = t >= 0 ? exp(-t * 2.0) * (0.55 + 0.45 * exp(-t * 9)) * 1.6 : exp(-(t * t) / 0.005)
                    let value = intensity * rays * profile
                    guard value > 0.001 else { continue }
                    let mix = min(1, max(0, t) / 1.1)
                    let high = max(0, max(0, t) - 0.8) * c.violet
                    red[y] += value * (0.18 + 0.05 * mix + 0.5 * high)
                    green[y] += value * (1.0 - 0.35 * mix - 0.4 * high)
                    blue[y] += value * (0.5 + 0.35 * mix + 0.3 * high)
                }
            }
            let ground = ridge?[x]
            if let ground {
                var glow = 0.0
                for y in 0..<lh { glow += green[y] }
                glow = min(1.5, glow / Double(lh) * 6)
                for y in 0..<lh {
                    let fy = Double(y) / Double(lh)
                    guard fy < ground else { break }
                    let haze = glow * 0.16 * exp(-(ground - fy) / 0.07)
                    red[y] += haze * 0.12
                    green[y] += haze * 0.75
                    blue[y] += haze * 0.55
                }
            }
            for y in 0..<lh {
                let row = y
                let offset = row * bytesPerRow + x * 4
                var r = red[y], g = green[y], b = blue[y]
                if let ground, Double(y) / Double(lh) > ground { r = 0; g = 0; b = 0 }
                pixels[offset] = UInt8(min(255, b * 255))
                pixels[offset + 1] = UInt8(min(255, g * 255))
                pixels[offset + 2] = UInt8(min(255, r * 255))
                pixels[offset + 3] = 255
            }
        }

        guard let image = low.makeImage() else { return }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
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
        let pulses: Int
        let phase: Double
        let sharp: Bool
        let color: (CGFloat, CGFloat, CGFloat)
    }

    private let scale: Double
    private let radius: Double
    private let noise: PerlinNoise
    private let flies: [Firefly]

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
            let sharp = random.unit() < 0.7
            let warm = random.unit()
            let color: (CGFloat, CGFloat, CGFloat) = warm < 0.6 ? (1, 0.82, 0.32) : warm < 0.85 ? (0.82, 1, 0.38) : (1, 0.68, 0.25)
            let period = 3.5 + random.unit() * 5
            return Firefly(x: random.unit() * w, y: h * (0.08 + random.unit() * 0.84),
                           reach: min(w, h) * (0.18 + random.unit() * 0.2),
                           ox: random.unit() * 80, oy: random.unit() * 80,
                           size: sharp ? 1.6 + random.unit() * 1.0 : 3.5 + random.unit() * 2.5,
                           brightness: sharp ? 0.75 + random.unit() * 0.25 : 0.3 + random.unit() * 0.2,
                           pulses: max(1, Int((seconds / period).rounded())),
                           phase: random.unit() * 2 * .pi,
                           sharp: sharp, color: color)
        }
    }

    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext) {
        let theta = 2 * .pi * Double(frame) / Double(max(total, 1))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setBlendMode(.plusLighter)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!

        for fly in flies {
            let cx = radius * cos(theta), cy = radius * sin(theta)
            let x = fly.x + fly.reach * noise.noise(cx + fly.ox, cy + fly.oy)
            let y = fly.y + fly.reach * 0.7 * noise.noise(cx + fly.ox + 31, cy + fly.oy - 17)
            let wave = max(0, sin(Double(fly.pulses) * theta + fly.phase))
            let glow = fly.brightness * (0.12 + 0.88 * pow(wave, 2))
            guard glow > 0.01 else { continue }
            let (r, g, b) = fly.color
            let outer = CGFloat(fly.size * (fly.sharp ? 10 : 6) * scale)
            let colors = [CGColor(red: r, green: g, blue: b, alpha: CGFloat(glow * (fly.sharp ? 0.7 : 0.75))),
                          CGColor(red: r, green: g, blue: b, alpha: CGFloat(glow * (fly.sharp ? 0.22 : 0.45))),
                          CGColor(red: r, green: g, blue: b, alpha: 0)] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, fly.sharp ? 0.22 : 0.7, 1])!
            let center = CGPoint(x: x, y: y)
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: outer, options: [])
            if fly.sharp {
                let core = CGFloat(fly.size * 1.1 * scale)
                ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.8, alpha: CGFloat(min(1, glow * 1.1))))
                ctx.fillEllipse(in: CGRect(x: x - core, y: y - core, width: core * 2, height: core * 2))
            }
        }
        ctx.setBlendMode(.normal)
    }
}

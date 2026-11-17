import AVFoundation
import CoreGraphics
import Foundation

protocol FrameRenderer: AnyObject, Sendable {
    var width: Int { get }
    var height: Int { get }
    var bitRateFactor: Double { get }
    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext)
}

struct PerlinNoise {
    private let perm: [Int]

    init(seed: UInt64) {
        var p = Array(0..<256)
        var state = seed
        for i in stride(from: 255, to: 0, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            p.swapAt(i, Int((state >> 33) % UInt64(i + 1)))
        }
        perm = (0..<512).map { p[$0 & 255] }
    }

    @inline(__always) private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

    @inline(__always) private func grad(_ h: Int, _ x: Double, _ y: Double) -> Double {
        switch h & 7 {
        case 0: return x + y
        case 1: return -x + y
        case 2: return x - y
        case 3: return -x - y
        case 4: return x
        case 5: return -x
        case 6: return y
        default: return -y
        }
    }

    @inline(__always) func noise(_ x: Double, _ y: Double) -> Double {
        let xf = floor(x), yf = floor(y)
        let xi = Int(xf) & 255, yi = Int(yf) & 255
        let dx = x - xf, dy = y - yf
        let u = fade(dx), v = fade(dy)
        let aa = perm[perm[xi] + yi], ab = perm[perm[xi] + yi + 1]
        let ba = perm[perm[xi + 1] + yi], bb = perm[perm[xi + 1] + yi + 1]
        let x1 = grad(aa, dx, dy) + u * (grad(ba, dx - 1, dy) - grad(aa, dx, dy))
        let x2 = grad(ab, dx, dy - 1) + u * (grad(bb, dx - 1, dy - 1) - grad(ab, dx, dy - 1))
        return x1 + v * (x2 - x1)
    }
}

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

enum Wallpaper {
    static let fps = 30

    static func renderer(width: Int, height: Int, options: TopoOptions) -> FrameRenderer {
        switch options.style {
        case .contours: return TopoGenerator(width: width, height: height, options: options)
        case .stars: return StarfieldGenerator(width: width, height: height, options: options)
        case .aurora: return AuroraGenerator(width: width, height: height, options: options)
        case .fireflies: return FireflyGenerator(width: width, height: height, options: options)
        }
    }

    static func bitRate(width: Int, height: Int, factor: Double) -> Int {
        let scale = Double(min(width, height)) / 1440
        return Int(9_000_000 * pow(scale, 1.5) * factor)
    }

    static func makeContext(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    static func still(_ renderer: FrameRenderer, seconds: Int, at fraction: Double) -> CGImage? {
        guard let ctx = makeContext(width: renderer.width, height: renderer.height) else { return nil }
        let total = seconds * fps
        renderer.draw(frame: Int(Double(total) * fraction) % max(total, 1), total: total, fps: fps, into: ctx)
        return ctx.makeImage()
    }

    static func renderVideo(_ renderer: FrameRenderer, seconds: Int, to url: URL,
                            progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) -> Bool {
        let width = renderer.width, height = renderer.height
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate(width: width, height: height, factor: renderer.bitRateFactor),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let total = seconds * fps
        let batch = max(4, ProcessInfo.processInfo.activeProcessorCount)
        let lock = NSLock()
        var frame = 0
        var ok = true

        while frame < total && ok {
            if isCancelled() { ok = false; break }
            let count = min(batch, total - frame)
            var images = [CGImage?](repeating: nil, count: count)
            let base = frame
            DispatchQueue.concurrentPerform(iterations: count) { k in
                guard let ctx = makeContext(width: width, height: height) else { return }
                renderer.draw(frame: base + k, total: total, fps: fps, into: ctx)
                let image = ctx.makeImage()
                lock.lock()
                images[k] = image
                lock.unlock()
            }
            for k in 0..<count {
                while !input.isReadyForMoreMediaData { usleep(2000) }
                guard let image = images[k], let pool = adaptor.pixelBufferPool else { ok = false; break }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { ok = false; break }
                CVPixelBufferLockBaseAddress(buffer, [])
                let ctx = makeContext(width: width, height: height,
                                      data: CVPixelBufferGetBaseAddress(buffer),
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
                ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                CVPixelBufferUnlockBaseAddress(buffer, [])
                if !adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(base + k), timescale: CMTimeScale(fps))) {
                    ok = false
                    break
                }
            }
            frame += count
            progress(Double(frame) / Double(total))
        }

        if !ok {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return false
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        return writer.status == .completed
    }
}

final class StarfieldGenerator: FrameRenderer, @unchecked Sendable {
    let width: Int
    let height: Int
    let bitRateFactor = 1.3

    private struct Star {
        let x: Double
        let y: Double
        let depth: Double
        let radius: CGFloat
        let brightness: Double
        let color: (CGFloat, CGFloat, CGFloat)
        let twinkleFrequency: Double
        let twinklePhase: Double
        let twinkleAmount: Double
        let glows: Bool
    }

    private struct Meteor {
        let start: Double
        let duration: Double
        let x: Double
        let y: Double
        let dx: Double
        let dy: Double
        let length: Double
    }

    private let scale: Double
    private let stars: [Star]
    private let meteors: [Meteor]
    private let velocity: (x: Double, y: Double)
    private let fade = 4.0
    private let loopSeconds: Double
    private let milkyWay: CGImage?
    private let milkyOrigin: (x: Double, y: Double)
    private let milkySize: (width: Double, height: Double)
    private let milkyDepth = 0.35
    private let glow: CGGradient

    init(width: Int, height: Int, options: TopoOptions) {
        self.width = width
        self.height = height
        let unit = Double(min(width, height)) / 1440
        scale = unit
        loopSeconds = Double(options.seconds)
        var random = SeededRandom(seed: options.seed)

        let speedFactor: Double
        switch options.speed {
        case .calm: speedFactor = 0.6
        case .normal: speedFactor = 1
        case .lively: speedFactor = 1.8
        }
        let angle = (165 + random.unit() * 20) * .pi / 180
        let speed = 4.5 * unit * speedFactor
        velocity = (cos(angle) * speed, sin(angle) * speed)

        let densityFactor: Double
        switch options.density {
        case .loose: densityFactor = 0.45
        case .normal: densityFactor = 1
        case .dense: densityFactor = 2.1
        }

        let w = Double(width), h = Double(height)
        let bandAngle = (20 + random.unit() * 25) * .pi / 180
        let bandCenter = (w * (0.35 + random.unit() * 0.3), h * (0.35 + random.unit() * 0.3))
        let bandWidth = min(w, h) * 0.16

        func makeStar(x: Double, y: Double, depth: Double, faint: Bool) -> Star {
            let u = random.unit()
            var brightness = faint ? 0.1 + 0.6 * pow(u, 3.5) : 0.18 + 0.82 * pow(u, 2.6)
            brightness *= 0.65 + 0.35 * depth
            let size = random.unit()
            let radius = CGFloat(max(0.5, unit * (0.45 + 1.5 * pow(size, 3)) * (0.7 + 0.45 * depth)))
            let tint = random.unit()
            let color: (CGFloat, CGFloat, CGFloat) = tint < 0.7 ? (1, 1, 1) : tint < 0.85 ? (0.78, 0.86, 1) : (1, 0.88, 0.72)
            return Star(x: x, y: y, depth: depth, radius: radius, brightness: brightness, color: color,
                        twinkleFrequency: 0.08 + random.unit() * 0.35,
                        twinklePhase: random.unit() * 2 * .pi,
                        twinkleAmount: 0.1 + random.unit() * 0.4,
                        glows: brightness > 0.7 && radius > CGFloat(1.1 * unit))
        }

        var list: [Star] = []
        let count = Int(w * h / 1700 * densityFactor)
        for _ in 0..<count {
            let layer = random.unit()
            let depth = layer < 0.55 ? 0.35 : layer < 0.85 ? 0.6 : 1.0
            list.append(makeStar(x: random.unit() * w, y: random.unit() * h, depth: depth, faint: false))
        }
        if options.milkyWay {
            for _ in 0..<Int(Double(count) * 1.2) {
                let along = (random.unit() - 0.5) * (w + h) * 1.2
                let gaussian = sqrt(-2 * log(max(random.unit(), 1e-9))) * cos(2 * .pi * random.unit())
                let across = gaussian * bandWidth * 0.38
                let x = bandCenter.0 + cos(bandAngle) * along - sin(bandAngle) * across
                let y = bandCenter.1 + sin(bandAngle) * along + cos(bandAngle) * across
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                list.append(makeStar(x: x, y: y, depth: milkyDepth, faint: true))
            }
        }
        stars = list

        var meteorList: [Meteor] = []
        let meteorCount = max(1, Int(loopSeconds / 40))
        for i in 0..<meteorCount {
            let slot = (loopSeconds - fade - 6) / Double(meteorCount)
            let start = fade + 2 + Double(i) * slot + random.unit() * max(slot - 2, 0)
            let heading = (200 + random.unit() * 50) * .pi / 180
            meteorList.append(Meteor(start: start, duration: 0.6 + random.unit() * 0.5,
                                     x: w * (0.2 + random.unit() * 0.7), y: h * (0.45 + random.unit() * 0.5),
                                     dx: cos(heading), dy: sin(heading),
                                     length: min(w, h) * (0.15 + random.unit() * 0.15)))
        }
        meteors = options.speed == .calm ? Array(meteorList.prefix(1)) : meteorList

        let travelX = abs(velocity.x) * milkyDepth * (loopSeconds + fade)
        let travelY = abs(velocity.y) * milkyDepth * (loopSeconds + fade)
        milkySize = (w + travelX, h + travelY)
        milkyOrigin = (velocity.x > 0 ? -travelX : 0, velocity.y > 0 ? -travelY : 0)
        milkyWay = options.milkyWay
            ? Self.makeMilkyWay(size: milkySize, offset: milkyOrigin, center: bandCenter, angle: bandAngle,
                                width: bandWidth, seed: options.seed)
            : nil

        glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.35),
                                   CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    }

    private static func makeMilkyWay(size: (width: Double, height: Double), offset: (x: Double, y: Double),
                                     center: (Double, Double), angle: Double, width: Double, seed: UInt64) -> CGImage? {
        let step = 4.0
        let cols = Int(size.width / step) + 1, rows = Int(size.height / step) + 1
        guard let ctx = Wallpaper.makeContext(width: cols, height: rows) else { return nil }
        let noise = PerlinNoise(seed: seed ^ 0xA5A5_5A5A)
        let feature = width * 0.9
        let buffer = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = ctx.bytesPerRow
        DispatchQueue.concurrentPerform(iterations: rows) { j in
            for i in 0..<cols {
                let x = offset.x + Double(i) * step, y = offset.y + Double(j) * step
                let rx = x - center.0, ry = y - center.1
                let across = -sin(angle) * rx + cos(angle) * ry
                let band = exp(-(across * across) / (width * width))
                let n1 = noise.noise(x / feature, y / feature) * 0.6
                    + noise.noise(x / feature * 2.3 + 7, y / feature * 2.3 - 3) * 0.3
                let dust = max(0, noise.noise(x / feature * 1.7 - 11, y / feature * 1.7 + 5))
                let value = max(0, band * (0.5 + n1 * 1.3) - dust * band * 0.95)
                let core = exp(-(across * across) / (width * width * 0.12))
                let intensity = min(1, value) * (0.13 + 0.07 * core)
                let red = 0.82 + 0.18 * core, green = 0.84 + 0.04 * core, blue = 1.0 - 0.22 * core
                let offsetBytes = (rows - 1 - j) * bytesPerRow + i * 4
                buffer[offsetBytes] = UInt8(min(255, intensity * 255 * blue))
                buffer[offsetBytes + 1] = UInt8(min(255, intensity * 255 * green))
                buffer[offsetBytes + 2] = UInt8(min(255, intensity * 255 * red))
                buffer[offsetBytes + 3] = 255
            }
        }
        return ctx.makeImage()
    }

    func draw(frame: Int, total: Int, fps: Int, into ctx: CGContext) {
        let loop = Double(total) / Double(fps)
        let t = Double(frame) / Double(fps)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setBlendMode(.plusLighter)
        if t < fade {
            let a = t / fade
            scene(at: t + loop, gain: 1 - a, into: ctx)
            scene(at: t, gain: a, into: ctx)
        } else {
            scene(at: t, gain: 1, into: ctx)
        }
        ctx.setBlendMode(.normal)
    }

    private func wrap(_ v: Double, _ m: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    private func scene(at t: Double, gain: Double, into ctx: CGContext) {
        guard gain > 0.001 else { return }
        let w = Double(width), h = Double(height)

        if let milkyWay {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(gain))
            ctx.interpolationQuality = .high
            let ox = milkyOrigin.x + velocity.x * milkyDepth * t
            let oy = milkyOrigin.y + velocity.y * milkyDepth * t
            ctx.draw(milkyWay, in: CGRect(x: ox, y: oy, width: milkySize.width, height: milkySize.height))
            ctx.restoreGState()
        }

        for star in stars {
            let x = wrap(star.x + velocity.x * star.depth * t, w)
            let y = wrap(star.y + velocity.y * star.depth * t, h)
            let twinkle = 1 - star.twinkleAmount * 0.5 * (1 + sin(2 * .pi * star.twinkleFrequency * t + star.twinklePhase))
            let alpha = CGFloat(min(1, star.brightness * twinkle * gain))
            if star.glows {
                let r = star.radius * 5
                ctx.saveGState()
                ctx.setAlpha(alpha)
                ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                       endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
                ctx.restoreGState()
            }
            ctx.setFillColor(CGColor(red: star.color.0, green: star.color.1, blue: star.color.2, alpha: alpha))
            ctx.fillEllipse(in: CGRect(x: x - Double(star.radius), y: y - Double(star.radius),
                                       width: Double(star.radius) * 2, height: Double(star.radius) * 2))
        }

        for meteor in meteors where t >= meteor.start && t <= meteor.start + meteor.duration {
            let p = (t - meteor.start) / meteor.duration
            let envelope = sin(.pi * p)
            let headX = meteor.x + meteor.dx * meteor.length * p
            let headY = meteor.y + meteor.dy * meteor.length * p
            let tail = meteor.length * 0.45
            let tailX = headX - meteor.dx * tail, tailY = headY - meteor.dy * tail
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                                               CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(0.9 * envelope * gain))] as CFArray,
                                      locations: [0, 1])!
            ctx.saveGState()
            ctx.setLineWidth(CGFloat(1.6 * scale))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: tailX, y: tailY))
            ctx.addLine(to: CGPoint(x: headX, y: headY))
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(gradient, start: CGPoint(x: tailX, y: tailY), end: CGPoint(x: headX, y: headY), options: [])
            ctx.restoreGState()
        }
    }
}

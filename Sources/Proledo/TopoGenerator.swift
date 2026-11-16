import AVFoundation
import CoreGraphics
import Foundation

struct TopoOptions: Equatable {
    enum Density: String, CaseIterable, Identifiable {
        case loose = "Locker", normal = "Normal", dense = "Dicht"
        var id: Self { self }
    }

    enum Speed: String, CaseIterable, Identifiable {
        case calm = "Ruhig", normal = "Normal", lively = "Lebhaft"
        var id: Self { self }
    }

    enum Lines: String, CaseIterable, Identifiable {
        case fine = "Fein", bold = "Kräftig"
        var id: Self { self }
    }

    var density = Density.normal
    var speed = Speed.normal
    var lines = Lines.fine
    var seconds = 120
    var seed = TopoOptions.randomSeed()

    static func randomSeed() -> UInt64 { UInt64.random(in: 1...(UInt64.max >> 2)) }
}

final class TopoGenerator: @unchecked Sendable {
    let width: Int
    let height: Int
    let fps = 30
    let options: TopoOptions

    private let cell: Double
    private let featureSize: Double
    private let levelStep: Double
    private let thin: CGFloat
    private let thick: CGFloat
    private let r1: Double
    private let r2: Double
    private let cols: Int
    private let rows: Int
    private let perm: [Int]
    private let indexEvery = 5

    init(width: Int, height: Int, options: TopoOptions) {
        self.width = width
        self.height = height
        self.options = options

        let scale = Double(min(width, height)) / 1440
        let densityFactor: Double
        switch options.density {
        case .loose: densityFactor = 1.3; levelStep = 0.13
        case .normal: densityFactor = 1.0; levelStep = 0.105
        case .dense: densityFactor = 0.78; levelStep = 0.088
        }
        featureSize = 680 * scale * densityFactor
        cell = 4 * scale

        let lineScale: Double = options.lines == .bold ? 1.5 : 1
        thin = CGFloat(1.6 * scale * lineScale)
        thick = CGFloat(3.4 * scale * lineScale)

        let speedFactor: Double
        switch options.speed {
        case .calm: speedFactor = 0.6
        case .normal: speedFactor = 1
        case .lively: speedFactor = 1.8
        }
        let distance = 0.0576 * speedFactor * Double(options.seconds)
        r1 = distance / (2 * .pi)
        r2 = r1 * 0.73

        cols = Int(Double(width) / cell) + 2
        rows = Int(Double(height) / cell) + 2

        var p = Array(0..<256)
        var state = options.seed
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

    @inline(__always) private func noise(_ x: Double, _ y: Double) -> Double {
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

    @inline(__always) private func heightAt(_ px: Double, _ py: Double, _ theta: Double) -> Double {
        let x = px / featureSize, y = py / featureSize
        let a = noise(x + r1 * cos(theta) + 13.7, y + r1 * sin(theta) + 7.1)
            + 0.5 * noise(2.03 * x + 3.3, 2.03 * y + r1 * 0.5 * cos(theta) - 1.9)
        let b = noise(1.37 * x - r2 * cos(theta + 1.3) - 5.2, 1.37 * y + r2 * sin(theta + 1.3) + 11.4)
        return a * 0.75 + b * 0.55
    }

    private func render(theta: Double, into ctx: CGContext) {
        let field = UnsafeMutableBufferPointer<Double>.allocate(capacity: cols * rows)
        defer { field.deallocate() }
        let cols = self.cols, cell = self.cell
        DispatchQueue.concurrentPerform(iterations: rows) { j in
            for i in 0..<cols { field[j * cols + i] = heightAt(Double(i) * cell, Double(j) * cell, theta) }
        }
        var lo = Double.infinity, hi = -Double.infinity
        for v in field { lo = min(lo, v); hi = max(hi, v) }
        let first = Int(floor(lo / levelStep)), last = Int(ceil(hi / levelStep))

        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for (isIndex, lineWidth) in [(false, thin), (true, thick)] {
            let path = CGMutablePath()
            for k in first...last where ((k % indexEvery + indexEvery) % indexEvery == 0) == isIndex {
                let level = Double(k) * levelStep
                for j in 0..<(rows - 1) {
                    for i in 0..<(cols - 1) {
                        let a = field[j * cols + i], b = field[j * cols + i + 1]
                        let c = field[(j + 1) * cols + i + 1], d = field[(j + 1) * cols + i]
                        var index = 0
                        if a > level { index |= 1 }
                        if b > level { index |= 2 }
                        if c > level { index |= 4 }
                        if d > level { index |= 8 }
                        if index == 0 || index == 15 { continue }
                        let x0 = Double(i) * cell, y0 = Double(j) * cell
                        let top = CGPoint(x: x0 + (level - a) / (b - a) * cell, y: y0)
                        let right = CGPoint(x: x0 + cell, y: y0 + (level - b) / (c - b) * cell)
                        let bottom = CGPoint(x: x0 + (level - d) / (c - d) * cell, y: y0 + cell)
                        let left = CGPoint(x: x0, y: y0 + (level - a) / (d - a) * cell)
                        func segment(_ p: CGPoint, _ q: CGPoint) { path.move(to: p); path.addLine(to: q) }
                        switch index {
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
            ctx.setLineWidth(lineWidth)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private func makeContext(_ data: UnsafeMutableRawPointer?, bytesPerRow: Int) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    func still(at fraction: Double = 0) -> CGImage? {
        guard let ctx = makeContext(nil, bytesPerRow: 0) else { return nil }
        render(theta: 2 * .pi * fraction, into: ctx)
        return ctx.makeImage()
    }

    func renderVideo(to url: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let scale = Double(min(width, height)) / 1440
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(9_000_000 * pow(scale, 1.5)),
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

        let total = options.seconds * fps
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
                guard let ctx = makeContext(nil, bytesPerRow: 0) else { return }
                render(theta: 2 * .pi * Double(base + k) / Double(total), into: ctx)
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
                let ctx = makeContext(CVPixelBufferGetBaseAddress(buffer), bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
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

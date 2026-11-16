import AVFoundation
import Foundation

enum EcoResult {
    case converted(URL)
    case notNeeded
    case failed
}

private struct Pipeline: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderVideoCompositionOutput
    let input: AVAssetWriterInput
}

enum EcoConverter {
    static let maxShortSide: CGFloat = 1440
    static let maxFrameRate: Float = 30

    static func convert(source: URL, to target: URL) async -> EcoResult {
        let asset = AVURLAsset(url: source)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let fps = try? await track.load(.nominalFrameRate),
              let duration = try? await asset.load(.duration)
        else { return .failed }

        let scale = min(1, maxShortSide / min(size.width, size.height))
        if fps <= maxFrameRate + 1 && scale >= 1 { return .notNeeded }

        let renderSize = CGSize(width: (size.width * scale / 2).rounded() * 2,
                                height: (size.height * scale / 2).rounded() * 2)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(CGAffineTransform(scaleX: scale, y: scale), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = renderSize
        let targetFps = fps > maxFrameRate + 1 ? Int32(maxFrameRate) : Int32(max(1, fps.rounded()))
        composition.frameDuration = CMTime(value: 1, timescale: targetFps)

        try? FileManager.default.removeItem(at: target)
        let ok = await encode(asset: asset, track: track, composition: composition,
                              size: renderSize, fps: Int(targetFps), to: target)
        guard ok else {
            try? FileManager.default.removeItem(at: target)
            return .failed
        }
        return .converted(target)
    }

    private static func encode(asset: AVAsset, track: AVAssetTrack, composition: AVVideoComposition,
                               size: CGSize, fps: Int, to target: URL) async -> Bool {
        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: target, fileType: .mp4)
        else { return false }

        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        output.videoComposition = composition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)

        let bitRate = Int(size.width * size.height * Double(fps) * 0.05)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return false }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "proledo.eco")
        let pipe = Pipeline(reader: reader, output: output, input: input)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipe.input.requestMediaDataWhenReady(on: queue) {
                while pipe.input.isReadyForMoreMediaData {
                    if let sample = pipe.output.copyNextSampleBuffer() {
                        if !pipe.input.append(sample) {
                            pipe.reader.cancelReading()
                            pipe.input.markAsFinished()
                            continuation.resume()
                            return
                        }
                    } else {
                        pipe.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
        await writer.finishWriting()
        return reader.status == .completed && writer.status == .completed
    }
}

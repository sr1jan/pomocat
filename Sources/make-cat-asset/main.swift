// make-cat-asset — Extract the cat from a green-screen source using Apple Vision's
// VNGenerateForegroundInstanceMaskRequest (the same engine as iOS Photos' "lift subject"),
// then encode as HEVC-with-alpha .mov via AVFoundation. No chromakey tuning required —
// the matter is shape/semantics-aware, so a non-uniform green floor is irrelevant.
//
// Usage: swift run make-cat-asset <input-video> <output.mov>

import Foundation
import AVFoundation
import Vision
import CoreVideo

@main
struct MakeCatAsset {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            FileHandle.standardError.write(Data("usage: make-cat-asset <input-video> <output.mov>\n".utf8))
            exit(1)
        }

        let input = URL(fileURLWithPath: args[1])
        let output = URL(fileURLWithPath: args[2])
        try? FileManager.default.removeItem(at: output)

        let asset = AVURLAsset(url: input)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            FileHandle.standardError.write(Data("error: no video track in \(input.path)\n".utf8))
            exit(1)
        }

        let dimensions = try await track.load(.naturalSize)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        print("input: \(width)×\(height)")

        // Reader — request BGRA so Vision can use the buffer directly without conversion.
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(readerOutput)
        reader.startReading()

        // Writer — HEVC-with-alpha is Apple's native alpha codec; ~10× smaller than ProRes 4444
        // and AVPlayerLayer renders it transparent for free.
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        writer.add(writerInput)
        guard writer.startWriting() else {
            FileHandle.standardError.write(Data("error: writer.startWriting failed: \(writer.error?.localizedDescription ?? "?")\n".utf8))
            exit(1)
        }
        writer.startSession(atSourceTime: .zero)

        var frameCount = 0
        var missedFrames = 0
        let startTime = Date()

        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { break }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            try handler.perform([request])

            let outputBuffer: CVPixelBuffer
            if let result = request.results?.first {
                // generateMaskedImage returns the source RGB with the mask baked into alpha,
                // matching source dimensions — exactly the BGRA-with-alpha buffer we need.
                outputBuffer = try result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                )
            } else {
                missedFrames += 1
                // No subject found — write a fully transparent frame so timing stays aligned.
                var blank: CVPixelBuffer?
                CVPixelBufferCreate(
                    nil, width, height, kCVPixelFormatType_32BGRA,
                    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                    &blank
                )
                outputBuffer = blank!
            }

            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }

            if !adaptor.append(outputBuffer, withPresentationTime: presentationTime) {
                FileHandle.standardError.write(Data("error: append failed at frame \(frameCount): \(writer.error?.localizedDescription ?? "?")\n".utf8))
                exit(1)
            }

            frameCount += 1
            if frameCount % 30 == 0 {
                let fps = Double(frameCount) / Date().timeIntervalSince(startTime)
                print("processed \(frameCount) frames (\(String(format: "%.1f", fps)) fps)")
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status != .completed {
            FileHandle.standardError.write(Data("error: writer ended in status \(writer.status.rawValue): \(writer.error?.localizedDescription ?? "?")\n".utf8))
            exit(1)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("done. \(frameCount) frames (\(missedFrames) without subject) in \(String(format: "%.1f", elapsed))s → \(output.path)")
    }
}

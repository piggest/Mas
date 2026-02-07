import AppKit
import Vision

struct RecognizedTextBlock {
    let text: String
    let rect: CGRect  // canvas座標系（左下原点）
}

class TextRecognitionService {
    func recognizeText(in image: NSImage, imageSize: CGSize) async -> [RecognizedTextBlock] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let blocks = observations.compactMap { observation -> RecognizedTextBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }

                    // Vision の boundingBox は正規化座標（左下原点、0-1）
                    let box = observation.boundingBox
                    let rect = CGRect(
                        x: box.origin.x * imageSize.width,
                        y: box.origin.y * imageSize.height,
                        width: box.width * imageSize.width,
                        height: box.height * imageSize.height
                    )

                    return RecognizedTextBlock(text: candidate.string, rect: rect)
                }

                continuation.resume(returning: blocks)
            }

            request.recognitionLanguages = ["ja", "en"]
            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}

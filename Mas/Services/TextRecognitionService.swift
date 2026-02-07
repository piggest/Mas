import AppKit
import Vision

struct RecognizedTextBlock {
    let text: String
    let rect: CGRect  // canvas座標系（左下原点）
    let charRects: [CGRect]  // 文字ごとのrect（canvas座標系、左下原点）
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

                    // 文字単位のbounding box取得
                    let str = candidate.string
                    var charRects: [CGRect] = []
                    for i in str.indices {
                        let range = i..<str.index(after: i)
                        if let charObs = try? candidate.boundingBox(for: range) {
                            let cb = charObs.boundingBox
                            charRects.append(CGRect(
                                x: cb.origin.x * imageSize.width,
                                y: cb.origin.y * imageSize.height,
                                width: cb.width * imageSize.width,
                                height: cb.height * imageSize.height
                            ))
                        } else {
                            // Fallback: ブロック全体を均等分割
                            let charCount = CGFloat(str.count)
                            let idx = CGFloat(str.distance(from: str.startIndex, to: i))
                            let charWidth = rect.width / charCount
                            charRects.append(CGRect(
                                x: rect.origin.x + charWidth * idx,
                                y: rect.origin.y,
                                width: charWidth,
                                height: rect.height
                            ))
                        }
                    }

                    return RecognizedTextBlock(text: candidate.string, rect: rect, charRects: charRects)
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

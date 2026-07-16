import Foundation
import ImageIO
import Vision

protocol ClipboardImageTextRecognizing: Sendable {
    func recognizeText(at imageURL: URL) async throws -> String
}

enum ClipboardImageTextRecognitionError: Error {
    case invalidImage
}

struct ClipboardImageTextRecognizer: ClipboardImageTextRecognizing {
    static let maximumPixelDimension = 2_560

    func recognizeText(at imageURL: URL) async throws -> String {
        let recognitionTask = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(
                      source,
                      0,
                      [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelDimension,
                          kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary
                  ) else {
                throw ClipboardImageTextRecognitionError.invalidImage
            }

            try Task.checkCancellation()

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            try Task.checkCancellation()

            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        return try await withTaskCancellationHandler {
            try await recognitionTask.value
        } onCancel: {
            recognitionTask.cancel()
        }
    }
}

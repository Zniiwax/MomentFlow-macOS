import AppKit
import Foundation
import Vision

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = try FileManager.default.contentsOfDirectory(
    at: folder,
    includingPropertiesForKeys: nil
).filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

var foundChinese = false

for file in files {
    guard let image = NSImage(contentsOf: file),
          let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let cgImage = bitmap.cgImage else {
        continue
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "en-US"]

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])

    let observations = request.results ?? []
    for observation in observations {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let text = candidate.string
        if text.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            foundChinese = true
            print("CHINESE \(file.lastPathComponent): \(text)")
        }
    }
}

if foundChinese {
    exit(2)
}
print("No Chinese text detected in audited frames.")

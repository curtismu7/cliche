import AppKit
import Vision

/// "Copy text from screen": interactive region selection → on-device Vision
/// text recognition → recognized text onto the clipboard (where the
/// clipboard monitor picks it up into history).
public final class OCRService {
    public init() {}

    /// Recognizes text in an image file, lines joined with newlines in the
    /// top-to-bottom order Vision returns. Entirely on-device.
    public static func recognizeText(in url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(url: url).perform([request])
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// Runs the native region picker, OCRs the selection, and puts the text
    /// on the clipboard. Beeps if nothing was recognized; does nothing if the
    /// user cancels. `onRecognized` runs on the main queue with the text.
    public func captureText(onRecognized: ((String) -> Void)? = nil) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipshot-ocr-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", tempURL.path]
        process.terminationHandler = { _ in
            defer { try? FileManager.default.removeItem(at: tempURL) }
            // No file: the user pressed Esc.
            guard FileManager.default.fileExists(atPath: tempURL.path) else { return }
            let text = (try? Self.recognizeText(in: tempURL)) ?? ""
            DispatchQueue.main.async {
                if text.isEmpty {
                    NSSound.beep()
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
                onRecognized?(text)
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("ClipShot: failed to launch screencapture for OCR: \(error)")
        }
    }
}

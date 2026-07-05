import AVFoundation
import AppKit
import ScreenCaptureKit

/// Records a display region to an MP4 via SCStream → AVAssetWriter.
public final class ScreenRecorder: NSObject, SCStreamOutput {
    public enum RecorderError: Error {
        case displayNotFound
        case writerFailed
    }

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private let sampleQueue = DispatchQueue(label: "cliche.recorder.samples")

    public private(set) var isRecording = false
    public private(set) var outputURL: URL?

    /// `sourceRect` in points, top-left origin, display-relative; nil records
    /// the whole display.
    public func start(
        displayID: CGDirectDisplayID,
        sourceRect: CGRect?,
        scale: CGFloat,
        showsCursor: Bool,
        hideDesktopIcons: Bool = false,
        outputURL: URL
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw RecorderError.displayNotFound }

        let excluded = DesktopClutter.exclusions(
            in: content.windows, hideDesktopIcons: hideDesktopIcons)
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let rect = sourceRect
            ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        // H.264 requires even dimensions.
        let width = Int(rect.width * scale) & ~1
        let height = Int(rect.height * scale) & ~1

        let configuration = SCStreamConfiguration()
        if sourceRect != nil { configuration.sourceRect = rect }
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = showsCursor
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.writerFailed }
        writer.add(input)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.writer = writer
        self.input = input
        self.stream = stream
        self.outputURL = outputURL
        self.sessionStarted = false
        self.isRecording = true
    }

    /// Stops and finalizes; returns the file URL on success.
    public func stop() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        try? await stream?.stopCapture()
        stream = nil

        guard let writer, sessionStarted else {
            writer?.cancelWriting()
            self.writer = nil
            return nil
        }
        input?.markAsFinished()
        await writer.finishWriting()
        let url = outputURL
        self.writer = nil
        self.input = nil
        return writer.status == .completed ? url : nil
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              isRecording,
              let writer,
              let input
        else { return }

        // Only append fully rendered frames.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: statusRaw) != .complete {
            return
        }

        if !sessionStarted {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}

import AVFoundation
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

/// 录一段素材：画面和 / 或系统声音。
///
/// 三种来源（窗口 / 整屏 / 选区）× 三种媒体组合（画面+声音 / 只有画面 / 只有声音），
/// 输出统一是一个文件：有画面时是 mp4，只有声音时是 m4a。
///
/// 线程模型：所有 writer 状态只在 `sampleQueue` 上读写，SCStream 的音视频输出
/// 都挂到同一个串行队列，天然避免两路样本交错写入的时序问题。
public final class ClipRecorder: NSObject, @unchecked Sendable {

    private static let logger = Logger(subsystem: "local.momentflow.app", category: "capture")

    /// 录哪一块。
    public enum Source {
        /// 一个窗口。画面最干净，没有桌面图标和其他窗口的通知。
        case window(SCWindow)
        /// 一整块屏幕。
        case display(SCDisplay)
        /// 屏幕上的一块矩形。`rect` 是 sourceRect 口径（原点左上、单位为点）。
        case region(display: SCDisplay, rect: CGRect)
    }

    public struct Result: Sendable {
        public var url: URL
        public var duration: TimeInterval
    }

    public enum Failure: LocalizedError {
        case alreadyRecording
        case notRecording
        case nothingSelected
        case noCaptureTarget
        case stream(String)
        case writer(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "已经在录制了"
            case .notRecording: return "当前没有在录制"
            case .nothingSelected: return "画面和声音至少要选一个"
            case .noCaptureTarget: return "找不到可录制的窗口或屏幕"
            case .stream(let message): return "采集失败：\(message)"
            case .writer(let message): return "写入失败：\(message)"
            }
        }
    }

    /// 把 ScreenCaptureKit 的错误码翻译成人话。
    ///
    /// 系统原文是 "用户拒绝了应用程序、窗口、显示器捕捉的 TCC" 这种，
    /// 里面既有术语又没有下一步动作，直接甩给用户等于没说。
    public static func describe(_ error: Error) -> String {
        let failure = error as NSError
        if failure.domain == SCStreamErrorDomain,
           let code = SCStreamError.Code(rawValue: failure.code) {
            switch code {
            case .userDeclined:
                return "系统没有给屏幕录制权限。去「系统设置 → 隐私与安全性 → 屏幕录制」里打开 MomentFlow，然后退出本应用重新打开。"
            case .missingEntitlements:
                return "缺少录制所需的系统授权。把 MomentFlow 从屏幕录制列表里删掉，再重新打开本应用授权一次。"
            case .noCaptureSource, .noDisplayList, .noWindowList:
                return "找不到可录制的窗口或屏幕。如果刚才改过显示器配置（插拔外接屏、改分辨率），重开一次本应用。"
            case .failedApplicationConnectionInvalid, .failedApplicationConnectionInterrupted:
                return "和系统采集服务的连接断了。重开一次本应用通常就好了。"
            case .attemptToStartStreamState:
                return "上一次录制还没结束。稍等一下再试。"
            case .failedToStartAudioCapture:
                return "声音部分没能启动。可以先取消勾选「系统声音」只录画面。"
            default:
                break
            }
        }
        return failure.localizedDescription
    }

    private let sampleQueue = DispatchQueue(label: "com.momentflow.recorder.samples")
    private let stateLock = NSLock()

    // 以下状态只在 sampleQueue 上访问。
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var wantsVideo = true
    private var sessionStart: CMTime?
    private var lastSampleTime: CMTime?
    private var pendingFailure: Error?

    // 跨线程读写的标志位，由 stateLock 保护。
    private var runningStream: SCStream?
    private var lastStreamError: Error?

    public override init() {
        super.init()
    }

    public var isRecording: Bool {
        currentStream() != nil
    }

    /// 已经录了多久。给界面上的计时器读。
    public var recordedDuration: TimeInterval {
        sampleQueue.sync { durationLocked() }
    }

    // MARK: - 开始

    public func start(
        source: Source,
        media: MediaSelection,
        outputURL: URL,
        frameRate: Int = 30
    ) async throws {
        guard media.isValid else { throw Failure.nothingSelected }
        if isRecording { throw Failure.alreadyRecording }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let setup = try Self.makeSetup(source: source, content: content) else {
            throw Failure.noCaptureTarget
        }

        let config = SCStreamConfiguration()
        config.width = setup.pixelSize.width
        config.height = setup.pixelSize.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 6
        config.showsCursor = true
        // 单窗口采集默认会把窗口阴影也算进源区域。源区域因此比窗口本身大一圈，
        // 再被压缩到指定的输出尺寸，画面会整体缩小并偏向一侧。
        // 截图路径同样需要这个设置，否则两条路径的输出会不一致。
        config.ignoreShadowsSingleWindow = true
        if let sourceRect = setup.sourceRect {
            config.sourceRect = sourceRect
        }
        config.capturesAudio = media.systemAudio
        config.sampleRate = 48_000
        config.channelCount = 2
        // 别把本工具自己的提示音录进去。
        config.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: setup.filter, configuration: config, delegate: self)

        try withSampleQueue {
            try self.prepareWriterLocked(
                outputURL: outputURL,
                media: media,
                pixelSize: setup.pixelSize,
                bitrate: setup.bitrate,
                frameRate: frameRate
            )
        }

        do {
            if media.video {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            }
            if media.systemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            try await stream.startCapture()
        } catch {
            withSampleQueue { self.resetLocked() }
            throw Failure.stream(Self.describe(error))
        }

        setStream(stream)
    }

    private func prepareWriterLocked(
        outputURL: URL,
        media: MediaSelection,
        pixelSize: PixelSize,
        bitrate: Int,
        frameRate: Int
    ) throws {
        let fileType: AVFileType = media.video ? .mp4 : .m4a
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)

        if media.video {
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: pixelSize.width,
                AVVideoHeightKey: pixelSize.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw Failure.writer("无法加入视频轨") }
            writer.add(input)
            videoInput = input
        }

        if media.systemAudio {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 192_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw Failure.writer("无法加入音频轨") }
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else {
            throw Failure.writer(writer.error?.localizedDescription ?? "未知原因")
        }

        self.writer = writer
        self.outputURL = outputURL
        wantsVideo = media.video
        sessionStart = nil
        lastSampleTime = nil
        pendingFailure = nil
    }

    // MARK: - 停止

    public func stop() async throws -> Result {
        let (stream, streamError) = takeStream()
        guard let stream else {
            // 流可能已经自己挂掉了（采集服务断了、窗口被关了……）。
            // 这种情况还报「当前没有在录制」就太误导了——用户刚按的停止，
            // 得把真正的原因说出来。
            if let streamError {
                throw Failure.stream(Self.describe(streamError))
            }
            throw Failure.notRecording
        }

        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
        try? stream.removeStreamOutput(self, type: .audio)

        return try await withCheckedThrowingContinuation { continuation in
            sampleQueue.async {
                if let error = self.pendingFailure ?? streamError {
                    self.resetLocked()
                    continuation.resume(throwing: Failure.stream(Self.describe(error)))
                    return
                }
                self.finishLocked(continuation: continuation)
            }
        }
    }

    private func finishLocked(continuation: CheckedContinuation<Result, Error>) {
        guard let writer, let outputURL else {
            continuation.resume(throwing: Failure.notRecording)
            return
        }

        let duration = durationLocked()

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        resetLocked()

        writer.finishWriting {
            guard writer.status == .completed else {
                continuation.resume(
                    throwing: Failure.writer(writer.error?.localizedDescription ?? "文件没有写完")
                )
                return
            }
            continuation.resume(returning: Result(url: outputURL, duration: duration))
        }
    }

    /// 时长以「最后到达的那一路样本」为准。
    ///
    /// 不能只看视频：只录声音的时候没有视频样本，那样算出来永远是 0。
    private func durationLocked() -> TimeInterval {
        guard let start = sessionStart, let end = lastSampleTime, end > start else { return 0 }
        return CMTimeGetSeconds(CMTimeSubtract(end, start))
    }

    private func resetLocked() {
        writer = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        wantsVideo = true
        sessionStart = nil
        lastSampleTime = nil
    }

    // MARK: - 追加样本（只在 sampleQueue 上跑）

    private func ensureSession(at time: CMTime) {
        guard let writer, sessionStart == nil else { return }
        // 用第一个到的样本开 session。音频往往比视频先到，
        // 如果等视频，先到的音频样本会因为早于 session 起点而被丢掉。
        writer.startSession(atSourceTime: time)
        sessionStart = time
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard let writer, let input, writer.status == .writing else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        ensureSession(at: time)
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) {
            lastSampleTime = time
        } else {
            recordFailure(writer.error)
        }
    }

    // MARK: - 跨线程状态

    /// 锁只在同步方法里进出。
    ///
    /// `NSLock.lock()` 出现在 `async` 函数里，在 Swift 6 语言模式下是错误，
    /// 所以收进这几个小函数，别散落在 async 代码里。
    private func currentStream() -> SCStream? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return runningStream
    }

    private func takeStream() -> (stream: SCStream?, error: Error?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let result = (runningStream, lastStreamError)
        runningStream = nil
        lastStreamError = nil
        return result
    }

    private func setStream(_ stream: SCStream?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        runningStream = stream
        lastStreamError = nil
    }

    private func recordFailure(_ error: Error?) {
        guard let error, pendingFailure == nil else { return }
        pendingFailure = error
    }

    private func withSampleQueue<T>(_ body: () throws -> T) rethrows -> T {
        try sampleQueue.sync(execute: body)
    }

    // MARK: - 采集目标

    struct Setup {
        var filter: SCContentFilter
        var pixelSize: PixelSize
        var sourceRect: CGRect?
        var bitrate: Int
    }

    static func makeSetup(source: Source, content: SCShareableContent) throws -> Setup? {
        switch source {
        case .window(let window):
            let filter = SCContentFilter(desktopIndependentWindow: window)

            // 全屏窗口改走「整屏 + sourceRect 裁剪」。
            //
            // 单窗口流在 macOS 全屏窗口上存在一个缩放问题：源区域会比窗口宽出一圈，
            // 再被压缩回指定的输出尺寸，画面会缩小几个百分点并偏向一侧。
            // 同一时刻用 SCScreenshotManager 走同样的滤镜是准确的，
            // 说明问题只出在流的缩放路径上。
            //
            // 窗口占满整块屏幕时（全屏就是这种），用屏幕滤镜 + 区域裁剪可以
            // 绕开这套缩放，而且坐标系是显示器的，明确得多。
            if let region = Self.coveredDisplayRegion(for: window, in: content) {
                let displayFilter = SCContentFilter(
                    display: region.display,
                    excludingWindows: ownWindows(in: content)
                )
                let regionScale = CGFloat(displayFilter.pointPixelScale)
                let size = DisplayGeometry.pixelSize(
                    forSourceRect: region.rect,
                    scale: regionScale
                )
                logger.info("""
                    capture fullscreen-as-region \
                    sourceRect=\(Int(region.rect.minX), privacy: .public),\(Int(region.rect.minY), privacy: .public) \
                    \(Int(region.rect.width), privacy: .public)x\(Int(region.rect.height), privacy: .public) \
                    output=\(size.width, privacy: .public)x\(size.height, privacy: .public)
                    """)
                return Setup(
                    filter: displayFilter,
                    pixelSize: size,
                    sourceRect: region.rect,
                    bitrate: DisplayGeometry.bitrate(forPixelSize: size)
                )
            }

            let scale = CGFloat(filter.pointPixelScale)
            let pixelSize = DisplayGeometry.pixelSize(
                forSourceRect: CGRect(origin: .zero, size: window.frame.size),
                scale: scale
            )
            // 诊断用：记录窗口在屏幕上的真实尺寸，和据此算出来的输出尺寸。
            // 排查「录出来和看到的不一致」这类问题时，这组数字能直接定位到
            // 是尺寸算错、窗口选错，还是流的缩放有问题。
            let appName = window.owningApplication?.applicationName ?? "?"
            logger.info("""
                capture window app=\(appName, privacy: .public) \
                frame=\(Int(window.frame.width), privacy: .public)x\(Int(window.frame.height), privacy: .public) \
                origin=(\(Int(window.frame.minX), privacy: .public),\(Int(window.frame.minY), privacy: .public)) \
                scale=\(Double(scale), privacy: .public) \
                output=\(pixelSize.width, privacy: .public)x\(pixelSize.height, privacy: .public) \
                layer=\(window.windowLayer, privacy: .public) \
                contentRect=\(Int(filter.contentRect.width), privacy: .public)x\(Int(filter.contentRect.height), privacy: .public) \
                contentOrigin=(\(Int(filter.contentRect.minX), privacy: .public),\(Int(filter.contentRect.minY), privacy: .public)) \
                filterScale=\(Double(filter.pointPixelScale), privacy: .public)
                """)
            return Setup(
                filter: filter,
                pixelSize: pixelSize,
                sourceRect: nil,
                bitrate: DisplayGeometry.bitrate(forPixelSize: pixelSize)
            )

        case .display(let display):
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows(in: content))
            let pixelSize = PixelSize(width: display.width, height: display.height)
            return Setup(
                filter: filter,
                pixelSize: pixelSize,
                sourceRect: nil,
                bitrate: DisplayGeometry.bitrate(forPixelSize: pixelSize)
            )

        case .region(let display, let rect):
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows(in: content))
            let scale = CGFloat(filter.pointPixelScale)
            let pixelSize = DisplayGeometry.pixelSize(forSourceRect: rect, scale: scale)
            return Setup(
                filter: filter,
                pixelSize: pixelSize,
                sourceRect: rect,
                bitrate: DisplayGeometry.bitrate(forPixelSize: pixelSize)
            )
        }
    }

    /// 排除本进程自己的窗口。
    ///
    /// 选区浮层和工具栏都是我们自己的窗口，它们就盖在要被录的区域上面。
    /// 虽然采集开始前会把它们关掉，但关窗和出第一帧之间有个时间差，
    /// 直接把自家窗口排除掉更保险。
    static func ownWindows(in content: SCShareableContent) -> [SCWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter { $0.owningApplication?.processID == ownPID }
    }

    /// 窗口如果几乎占满某块屏幕（全屏），返回那块屏幕和窗口在屏幕内的区域。
    ///
    /// 区域用「显示器左上角为原点、单位点」的坐标，正好是 sourceRect 要的口径。
    static func coveredDisplayRegion(
        for window: SCWindow,
        in content: SCShareableContent
    ) -> (display: SCDisplay, rect: CGRect)? {
        let frame = window.frame
        for display in content.displays {
            let bounds = CGDisplayBounds(display.displayID)
            let overlap = bounds.intersection(frame)
            guard !overlap.isNull, bounds.width > 0, bounds.height > 0 else { continue }
            let coverage = (overlap.width * overlap.height) / (bounds.width * bounds.height)
            guard coverage >= 0.9 else { continue }
            let rect = CGRect(
                x: frame.minX - bounds.minX,
                y: frame.minY - bounds.minY,
                width: frame.width,
                height: frame.height
            )
            return (display, rect)
        }
        return nil
    }

    /// SCStream 会送「内容没变化」的空帧，必须过滤掉，否则画面会周期性地闪一下背景。
    static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}

extension ClipRecorder: SCStreamOutput {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // 只录音频时没有视频轨，这里会自然丢弃。
            guard wantsVideo else { return }
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            append(sampleBuffer, to: videoInput)
        case .audio:
            append(sampleBuffer, to: audioInput)
        default:
            break
        }
    }
}

extension ClipRecorder: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        // 这个回调不在 sampleQueue 上，所以只碰加锁的状态。
        stateLock.lock()
        lastStreamError = error
        runningStream = nil
        stateLock.unlock()
    }
}

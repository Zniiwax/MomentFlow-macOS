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
        /// 麦克风单独一轨，没有开麦克风时为 nil。
        public var microphoneURL: URL?
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
    private var microphoneWriter: AVAssetWriter?
    private var microphoneInput: AVAssetWriterInput?
    private var microphoneSessionStart: CMTime?
    private var wantsMicrophone = false
    private var microphoneURL: URL?
    /// 麦克风轨写失败过。主轨照常完成，只在结尾丢掉麦克风。
    private var microphoneFailed = false
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
        microphoneOutputURL: URL? = nil,
        microphoneDeviceID: String? = nil,
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
        // 不强制 48 kHz / 立体声。
        //
        // 如果音频设备的原生格式是 44.1 kHz，强制指定会让系统在开始采集的瞬间
        // 重新协商音频格式，正在播放的音乐会明显卡一下。
        // 交给系统用设备原生格式，采样率转换交给 AVAssetWriter 的编码器。
        // 别把本工具自己的提示音录进去。
        config.excludesCurrentProcessAudio = true
        if #available(macOS 15.0, *) {
            config.captureMicrophone = media.microphone
            if media.microphone, let microphoneDeviceID {
                config.microphoneCaptureDeviceID = microphoneDeviceID
            }
        }

        let stream = SCStream(filter: setup.filter, configuration: config, delegate: self)

        try withSampleQueue {
            try self.prepareWriterLocked(
                outputURL: outputURL,
                microphoneURL: media.microphone ? microphoneOutputURL : nil,
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
            if #available(macOS 15.0, *), media.microphone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
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
        microphoneURL: URL?,
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
        self.microphoneURL = microphoneURL
        self.wantsMicrophone = media.microphone
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
        if #available(macOS 15.0, *) {
            try? stream.removeStreamOutput(self, type: .microphone)
        }

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
        let microphoneWriter = self.microphoneWriter
        let microphoneURL = self.microphoneURL
        let microphoneFailed = self.microphoneFailed

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        resetLocked()

        writer.finishWriting {
            guard writer.status == .completed else {
                continuation.resume(
                    throwing: Failure.writer(writer.error?.localizedDescription ?? "文件没有写完")
                )
                return
            }
            guard let microphoneWriter, let microphoneURL else {
                continuation.resume(returning: Result(url: outputURL, duration: duration, microphoneURL: nil))
                return
            }
            if microphoneFailed {
                // 写过的半截文件没有用，删掉；主录制照常交付。
                try? FileManager.default.removeItem(at: microphoneURL)
                continuation.resume(returning: Result(url: outputURL, duration: duration, microphoneURL: nil))
                return
            }
            microphoneWriter.finishWriting {
                let saved = microphoneWriter.status == .completed ? microphoneURL : nil
                continuation.resume(returning: Result(url: outputURL, duration: duration, microphoneURL: saved))
            }
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
        microphoneWriter = nil
        microphoneInput = nil
        microphoneSessionStart = nil
        wantsMicrophone = false
        microphoneURL = nil
        microphoneFailed = false
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

    /// 麦克风单独写一个 m4a。
    ///
    /// writer 是延迟创建的：采样率、声道数以设备实际吐出来的格式为准。
    /// 写死 48k 立体声在单声道麦克风上会直接写不进去（AirPods 的 HFP 就是单声道）。
    private func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard wantsMicrophone, let url = microphoneURL else { return }

        if microphoneWriter == nil {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
            else {
                Self.logger.error("microphone: sample buffer has no audio format description")
                microphoneFailed = true
                return
            }

            let isInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            Self.logger.info("""
                microphone format: \
                id=\(description.mFormatID, privacy: .public) \
                rate=\(description.mSampleRate, privacy: .public) \
                channels=\(description.mChannelsPerFrame, privacy: .public) \
                bits=\(description.mBitsPerChannel, privacy: .public) \
                bytesPerFrame=\(description.mBytesPerFrame, privacy: .public) \
                interleaved=\(isInterleaved, privacy: .public) \
                frames=\(CMSampleBufferGetNumSamples(sampleBuffer), privacy: .public)
                """)

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: max(1, Int(description.mChannelsPerFrame)),
                AVSampleRateKey: description.mSampleRate
                // 不指定位率。24 kHz 单声道（蓝牙通话麦就是这种）允许的
                // AAC 位率远低于 128 kbps，写死会让编码器报「无法编码媒体」。
                // 交给编码器按采样率和声道数自己选。
            ]
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                Self.logger.error("microphone: writer can't accept an audio input")
                microphoneFailed = true
                return
            }
            writer.add(input)
            guard writer.startWriting() else {
                Self.logger.error("""
                    microphone: startWriting failed: \
                    \(writer.error?.localizedDescription ?? "unknown", privacy: .public)
                    """)
                microphoneFailed = true
                return
            }
            microphoneWriter = writer
            microphoneInput = input
        }

        guard let writer = microphoneWriter,
              let input = microphoneInput,
              writer.status == .writing
        else { return }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if microphoneSessionStart == nil {
            writer.startSession(atSourceTime: time)
            microphoneSessionStart = time
        }
        guard input.isReadyForMoreMediaData else { return }
        if !input.append(sampleBuffer) {
            // 麦克风是附加轨：写失败不能连累画面和系统声音。
            microphoneFailed = true
            Self.logger.error("""
                microphone append failed: \
                \(writer.error?.localizedDescription ?? "unknown", privacy: .public)
                """)
            input.markAsFinished()
            writer.cancelWriting()
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
        if #available(macOS 15.0, *), type == .microphone {
            appendMicrophone(sampleBuffer)
            return
        }
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

import AVFoundation
import AppKit
import CoreGraphics
import Foundation

/// 权限状态。屏幕录制是 TCC 授权，没有 Info.plist 键，只能走系统 API 申请；
/// 麦克风走标准的 AVFoundation 授权流程。
public enum CapturePermission {

    public static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 第一次调用会弹系统授权框；用户改了设置之后需要重启 App 才生效。
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - 麦克风

    public static var microphone: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static var hasMicrophone: Bool {
        microphone == .authorized
    }

    /// 第一次用麦克风时申请权限。
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// 直接跳到系统设置里的屏幕录制面板。
    ///
    /// 权限被拒之后系统不会再自动弹框，只能自己去开——那就别让用户自己找，
    /// 从提示框里点一下跳过去。两个 URL 是不同系统版本的写法，取第一个能用的。
    @discardableResult
    public static func openScreenRecordingSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

}

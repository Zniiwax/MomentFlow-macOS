import AVFoundation
import Foundation

/// 系统里可用的音频输入设备。
///
/// AirPods 这类蓝牙设备被选中时，macOS 会把蓝牙切到通话模式，
/// 系统声音的音质会一起下降——这是设备行为，不是应用能控制的。
public enum AudioInputDevices {

    public struct Device: Identifiable, Hashable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public static func all() -> [Device] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// 系统当前默认的输入设备名字，用来在界面上显示"跟随系统 = 哪个"。
    public static var systemDefaultName: String? {
        AVCaptureDevice.default(for: .audio)?.localizedName
    }

    /// 粗略判断是不是蓝牙设备：蓝牙设备的 uniqueID 形如 `AA-BB-CC-DD-EE-FF:input`。
    public static func isBluetooth(_ device: Device) -> Bool {
        device.id.range(of: #"^[0-9A-F]{2}(-[0-9A-F]{2}){5}:input$"#, options: .regularExpression) != nil
    }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "tech.gluk.glukwave/energy", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "snapshot" else { result(FlutterMethodNotImplemented); return }
        let device = UIDevice.current
        let monitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        let battery = device.batteryLevel
        let charging = device.batteryState == .charging || device.batteryState == .full
        device.isBatteryMonitoringEnabled = monitoring
        result(["saving": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "battery": battery < 0 ? -1 : Int((battery * 100).rounded()), "charging": charging])
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

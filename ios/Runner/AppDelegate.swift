import Flutter
import UIKit
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let clockChannel = FlutterMethodChannel(
      name: "attendance/clock",
      binaryMessenger: engineBridge.engine.binaryMessenger
    )
    clockChannel.setMethodCallHandler { call, result in
      guard call.method == "elapsedRealtime" else {
        result(FlutterMethodNotImplemented)
        return
      }

      var timebase = mach_timebase_info_data_t()
      mach_timebase_info(&timebase)
      let nanoseconds = mach_continuous_time() &* UInt64(timebase.numer)
        / UInt64(timebase.denom)
      result(Int64(nanoseconds / 1_000_000))
    }
  }
}

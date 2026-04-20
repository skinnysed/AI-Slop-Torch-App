import Flutter
import AVFoundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channelsConfigured = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      configureChannels(binaryMessenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TorchAppChannels") {
      configureChannels(binaryMessenger: registrar.messenger())
    }
  }

  private func configureChannels(binaryMessenger: FlutterBinaryMessenger) {
    if channelsConfigured {
      return
    }

    channelsConfigured = true
    UIDevice.current.isBatteryMonitoringEnabled = true

    FlutterMethodChannel(
      name: "torch_app/vibration",
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "click":
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(
      name: "torch_app/battery",
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "getBatteryPercent":
        let batteryLevel = UIDevice.current.batteryLevel
        result(batteryLevel < 0 ? nil : Int(batteryLevel * 100))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(
      name: "torch_app/torch",
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "setBrightness":
        let arguments = call.arguments as? [String: Any]
        let brightness = arguments?["brightness"] as? Double ?? 1
        self.setTorch(brightness: brightness)
        result(nil)
      case "disable":
        self.disableTorch()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterMethodChannel(
      name: "torch_app/voice",
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "startListening", "stopListening":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setTorch(brightness: Double) {
    #if targetEnvironment(simulator)
    return
    #else
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
      return
    }

    do {
      try device.lockForConfiguration()
      try device.setTorchModeOn(level: Float(max(0.01, min(brightness, 1))))
      device.unlockForConfiguration()
    } catch {
      device.unlockForConfiguration()
    }
    #endif
  }

  private func disableTorch() {
    #if targetEnvironment(simulator)
    return
    #else
    guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
      return
    }

    do {
      try device.lockForConfiguration()
      device.torchMode = .off
      device.unlockForConfiguration()
    } catch {
      device.unlockForConfiguration()
    }
    #endif
  }
}

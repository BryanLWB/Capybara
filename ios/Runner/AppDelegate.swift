import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
      
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Method Channel
    let vpnChannel = FlutterMethodChannel(name: "app.capybara.client/v2ray", binaryMessenger: controller.binaryMessenger)
    vpnChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        switch call.method {
        case "connect":
            if let args = call.arguments as? [String: Any],
               let config = args["config"] as? String {
                VPNManager.shared.connect(config: config, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing config", details: nil))
            }
        case "disconnect":
            VPNManager.shared.disconnect(result: result)
        case "isConnected":
            result(VPNManager.shared.isConnected())
        default:
            result(FlutterMethodNotImplemented)
        }
    })
      
    // Event Channel
    let statusChannel = FlutterEventChannel(name: "app.capybara.client/v2ray_status", binaryMessenger: controller.binaryMessenger)
    statusChannel.setStreamHandler(VPNStatusStreamHandler())

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

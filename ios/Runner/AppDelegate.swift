import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let mobileSignals = MobileSignals()
  private let screenshots = Screenshots()
  private let connectors = IOSConnectorHost()
  let notices = IOSNotices()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A location wake can occur before any Flutter scene is created.
    mobileSignals.restore()
    UNUserNotificationCenter.current().delegate = notices
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    mobileSignals.register(with: engineBridge.applicationRegistrar.messenger())
    screenshots.register(with: engineBridge.applicationRegistrar.messenger())
    connectors.register(with: engineBridge.applicationRegistrar.messenger())
    notices.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

import Flutter
import UIKit
import UserNotifications
import CryptoKit

final class IOSNotices: NSObject, UNUserNotificationCenterDelegate, UIDocumentPickerDelegate {
  private let center = UNUserNotificationCenter.current()
  private var channel: FlutterMethodChannel?
  private var pendingOpen: [String: String]?
  private var lastTap: (identifier: String, date: Date)?
  private var exportResult: FlutterResult?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.purin/user_notifications", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "status", "enable":
        self.permission(request: call.method == "enable", result: result)
      case "takeOpen":
        let tap = self.pendingOpen
        self.pendingOpen = nil
        result(tap)
      case "foregroundArrival", "dismiss":
        guard let scope = args["scope"] as? String, let id = args["id"] as? String else {
          return result(FlutterError(code: "notice", message: "缺少通知标识", details: nil))
        }
        let key = SHA256.hash(data: Data((scope + "\u{0}" + id).utf8))
          .map { String(format: "%02x", $0) }.joined()
        if call.method == "dismiss" {
          self.center.removeDeliveredNotifications(withIdentifiers: [key])
          self.center.removePendingNotificationRequests(withIdentifiers: [key])
          result(nil)
        } else {
          self.present(key: key, scope: scope, id: id, args: args, result: result)
        }
      case "exportAttachment":
        self.export(path: call.arguments as? String, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func permission(request: Bool, result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        let allowed = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
        guard request && !allowed else { return result(allowed) }
        if settings.authorizationStatus == .notDetermined {
          self.center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            self.permission(request: false, result: result)
          }
        } else {
          let url = URL(string: UIApplication.openSettingsURLString)!
          UIApplication.shared.open(url) { _ in result(false) }
        }
      }
    }
  }

  private func present(key: String, scope: String, id: String,
                       args: [String: Any], result: @escaping FlutterResult) {
    let defaults = UserDefaults.standard
    let receipts = "purin.notice.receipts"
    let seen = defaults.stringArray(forKey: receipts) ?? []
    guard !seen.contains(key) else { return result(false) }
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        guard settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
          else { return result(false) }
        let content = UNMutableNotificationContent()
        content.title = args["title"] as? String ?? ""
        content.body = args["body"] as? String ?? ""
        content.userInfo = ["scope": scope, "id": id]
        content.sound = .default
        self.center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) { error in
          DispatchQueue.main.async {
            if let error {
              return result(FlutterError(code: "notice", message: error.localizedDescription, details: nil))
            }
            defaults.set(Array((seen + [key]).suffix(512)), forKey: receipts)
            result(true)
          }
        }
      }
    }
  }

  func open(_ response: UNNotificationResponse) {
    let info = response.notification.request.content.userInfo
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
          let scope = info["scope"] as? String, let id = info["id"] as? String else { return }
    let identifier = response.notification.request.identifier
    let date = response.notification.date
    if lastTap?.identifier == identifier && lastTap?.date == date { return }
    lastTap = (identifier, date)
    pendingOpen = ["scope": scope, "id": id]
    channel?.invokeMethod("openNotice", arguments: nil)
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    DispatchQueue.main.async { self.open(response); completionHandler() }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  private func export(path: String?, result: @escaping FlutterResult) {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard exportResult == nil, let path,
          var host = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      return result(FlutterError(code: "export", message: "暂时无法打开文件选择器", details: nil))
    }
    while let next = host.presentedViewController { host = next }
    let url = URL(fileURLWithPath: path)
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: url, in: .exportToService)
    }
    exportResult = result
    picker.delegate = self
    host.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    exportResult?(!urls.isEmpty)
    exportResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    exportResult?(false)
    exportResult = nil
  }
}

import Flutter
import ReplayKit
import UIKit

final class Screenshots: NSObject {
  private var store: ScreenshotStore?
  private var pickerController: UIViewController?
  #if canImport(ScreenCaptureKit) && compiler(>=6.4)
  private var modernCapture: AnyObject?
  #endif

  func register(with messenger: FlutterBinaryMessenger) {
    store = try? ScreenshotStore()
    updateVisibility(nil)
    for name in [UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification,
                 UIApplication.protectedDataWillBecomeUnavailableNotification,
                 UIApplication.protectedDataDidBecomeAvailableNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(updateVisibility(_:)), name: name, object: nil)
    }
    let channel = FlutterMethodChannel(name: "dev.purin/screenshots", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { return reply(FlutterMethodNotImplemented) }
      guard let store = self.store else {
        if call.method == "configure" { return reply(["access": "unsupported", "pending": 0]) }
        return reply(FlutterError(code: "app_group", message: "截图共享存储不可用，请检查 App Group 签名。", details: nil))
      }
      let args = call.arguments as? [String: Any] ?? [:]
      let scope = args["scope"] as? String ?? ""
      do {
        switch call.method {
        case "configure":
          let enabled = args["enabled"] as? Bool == true && !scope.isEmpty
          let seconds = args["intervalSeconds"] as? Int ?? 300
          guard [60, 300, 900].contains(seconds) else { throw ScreenshotStore.Failure.disabled }
          try store.configure(scope: scope, enabled: enabled, interval: seconds, background: self.isBackground)
          #if canImport(ScreenCaptureKit) && compiler(>=6.4)
          if #available(iOS 27, *), let capture = self.modernCapture as? ScreenCaptureSession {
            capture.reconcile(generation: try store.current()?.generation)
          }
          #endif
          if !enabled { self.pickerController?.dismiss(animated: true); self.pickerController = nil }
          reply(try store.status())
        case "request":
          guard let c = try store.current(), let host = self.presenter else {
            throw ScreenshotStore.Failure.disabled
          }
          #if canImport(ScreenCaptureKit) && compiler(>=6.4)
          if #available(iOS 27, *) {
            let capture = self.modernCapture as? ScreenCaptureSession ?? ScreenCaptureSession(store: store)
            self.modernCapture = capture
            capture.present(generation: c.generation)
            return reply(nil)
          }
          #endif
          self.showBroadcastPicker(from: host)
          reply(nil)
        case "read":
          reply(try store.read(scope: scope))
        case "bytes":
          if let data = try store.bytes(scope: scope, id: args["id"] as? String ?? "") {
            reply(FlutterStandardTypedData(bytes: data))
          } else { reply(nil) }
        case "ack":
          try store.ack(scope: scope, ids: Set(args["ids"] as? [String] ?? []))
          reply(nil)
        default: reply(FlutterMethodNotImplemented)
        }
      } catch {
        reply(FlutterError(code: "screenshots", message: "无法访问本机截图或启动屏幕共享。", details: nil))
      }
    }
  }

  private func background(excluding scene: UIScene? = nil) -> Bool {
    let scenes = UIApplication.shared.connectedScenes.filter { $0 !== scene }
    return !scenes.contains { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
  }

  private var isBackground: Bool { UIApplication.shared.isProtectedDataAvailable && background() }

  @objc private func updateVisibility(_ note: Notification?) {
    let hidden: Bool
    switch note?.name {
    case UIScene.willEnterForegroundNotification, UIApplication.protectedDataWillBecomeUnavailableNotification:
      hidden = false
    case UIScene.didEnterBackgroundNotification:
      hidden = UIApplication.shared.isProtectedDataAvailable && background(excluding: note?.object as? UIScene)
    default: hidden = isBackground
    }
    try? store?.setBackground(hidden)
  }

  private var presenter: UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first(where: { $0.activationState == .foregroundActive })
    var host = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let next = host?.presentedViewController { host = next }
    return host
  }

  private func showBroadcastPicker(from host: UIViewController) {
    if let existing = pickerController, existing.presentingViewController != nil { return }
    let controller = UIViewController()
    controller.title = "共享屏幕"
    controller.view.backgroundColor = .systemBackground
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 58, height: 58))
    picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "") + ".Broadcast"
    picker.showsMicrophoneButton = false
    let label = UILabel()
    label.numberOfLines = 0
    label.textAlignment = .center
    label.text = "轻点系统广播按钮，选择 Purin 并开始广播。"
    let done = UIButton(type: .system)
    done.setTitle("返回", for: .normal)
    done.addTarget(self, action: #selector(dismissPicker), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [label, picker, done])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(stack)
    NSLayoutConstraint.activate([
      picker.widthAnchor.constraint(equalToConstant: 58), picker.heightAnchor.constraint(equalToConstant: 58),
      stack.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 26),
      stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -26)
    ])
    pickerController = controller
    host.present(controller, animated: true)
  }

  @objc private func dismissPicker() { pickerController?.dismiss(animated: true); pickerController = nil }
}

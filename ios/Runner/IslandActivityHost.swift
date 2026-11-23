import ActivityKit
import Flutter
import UIKit

@MainActor
final class IslandActivityHost: NSObject {
  private var channel: FlutterMethodChannel?
  private var tail: Task<Void, Never>?
  private var running = false
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid

  func register(_ messenger: FlutterBinaryMessenger) {
    guard #available(iOS 16.2, *) else { return }
    let bridge = FlutterMethodChannel(name: "dev.wintermute/island", binaryMessenger: messenger)
    channel = bridge
    // A fresh Flutter engine starts at chat and has no folded conversation yet.
    tail = Task {
      for activity in Activity<IslandAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
    bridge.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      let previous = self.tail
      self.tail = Task { @MainActor in
        await previous?.value
        do {
          switch call.method {
          case "set":
            if let args = call.arguments as? [String: Any] { try await self.set(args) }
          case "clear":
            if let owner = call.arguments as? String {
              for activity in Activity<IslandAttributes>.activities where activity.attributes.owner == owner {
                await activity.end(nil, dismissalPolicy: .immediate)
              }
              self.running = !Activity<IslandAttributes>.activities.isEmpty
              if !self.running { self.releaseBackgroundTime() }
            }
          default: result(FlutterMethodNotImplemented); return
          }
          result(nil)
        } catch {
          result(FlutterError(code: "island_unavailable", message: error.localizedDescription, details: nil))
        }
      }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(releaseBackgroundTime),
      name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  func open(_ url: URL) -> Bool {
    guard url.scheme == "wintermute-island", url.host == "chat" else { return false }
    channel?.invokeMethod("openChat", arguments: nil)
    return true
  }

  @available(iOS 16.2, *)
  private func set(_ args: [String: Any]) async throws {
    guard let owner = args["owner"] as? String, let phase = args["phase"] as? String else { return }
    let state = IslandAttributes.ContentState(phase: phase, lines: args["lines"] as? [String] ?? [],
      dayEnd: (args["dayEnd"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) })
    let content = ActivityContent(state: state,
      staleDate: phase == "working" ? Date().addingTimeInterval(60) : nil)
    let activity = Activity<IslandAttributes>.activities.first { $0.attributes.owner == owner }
    if phase == "working" {
      if let activity {
        await activity.update(content)
      } else {
        guard UIApplication.shared.applicationState == .active,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try Activity.request(attributes: IslandAttributes(owner: owner), content: content, pushType: nil)
      }
      running = true
    } else {
      await activity?.end(content, dismissalPolicy: .after(Date().addingTimeInterval(90)))
      running = false
      releaseBackgroundTime()
    }
  }

  @objc private func backgrounded() {
    guard running, backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish folded reply") { [weak self] in
      self?.channel?.invokeMethod("stopPolling", arguments: nil)
      self?.releaseBackgroundTime()
    }
  }

  @objc private func releaseBackgroundTime() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}

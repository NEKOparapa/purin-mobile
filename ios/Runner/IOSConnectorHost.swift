import Contacts
import CoreLocation
import EventKit
import Flutter
import HealthKit
import MusicKit
import Photos
import UIKit

typealias ToolData = [String: Any]

struct ConnectorIssue: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

extension Dictionary where Key == String, Value == Any {
  func text(_ key: String, _ max: Int) throws -> String {
    guard let s = self[key] as? String, s.count <= max,
          !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ConnectorIssue("无效参数 \(key)")
    }
    return s
  }

  func number(_ key: String, _ range: ClosedRange<Int>, fallback: Int? = nil) throws -> Int {
    if self[key] == nil, let fallback = fallback { return fallback }
    guard let n = self[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
          n.doubleValue == Double(n.intValue), range.contains(n.intValue) else {
      throw ConnectorIssue("无效参数 \(key)")
    }
    return n.intValue
  }

  func interval() throws -> (Date, Date) {
    let start = try number("start_ms", 0...4_102_444_800_000)
    let end = try number("end_ms", 1...4_102_444_800_000)
    guard end > start, end - start <= 31 * 86_400_000 else { throw ConnectorIssue("查询区间须在 31 天内") }
    return (Date(timeIntervalSince1970: Double(start)/1000), Date(timeIntervalSince1970: Double(end)/1000))
  }
}

extension Date {
  var connectorMillis: Int64 { Int64(timeIntervalSince1970 * 1000) }
}

struct ConnectorRequest {
  let deadline: TimeInterval
  let server: String
  @MainActor func check() throws {
    guard UIApplication.shared.applicationState == .active else { throw ConnectorIssue("请在前台打开 Wintermute") }
    guard ProcessInfo.processInfo.systemUptime < deadline else { throw ConnectorIssue("设备调用超时") }
  }
  @MainActor func presenter() throws -> UIViewController {
    try check()
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var host = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      throw ConnectorIssue("未找到前台窗口")
    }
    while let next = host.presentedViewController { host = next }
    guard !(host is UIAlertController), !host.isBeingDismissed else { throw ConnectorIssue("请先关闭当前弹窗") }
    return host
  }
}

@MainActor
final class IOSConnectorHost: NSObject {
  let events = EKEventStore()
  let contacts = CNContactStore()
  let location = IOSConnectorLocation()
  let health = HKHealthStore()
  private let groups = [
    "calendar": ["ios_calendar_events", "ios_calendar_create"], "contacts": ["ios_contacts"],
    "health": ["ios_health_summary"], "music": ["ios_music_search", "ios_music_control"],
    "photos": ["ios_photos_search", "ios_photo_open"],
    "reminders": ["ios_reminders_list", "ios_reminders_create", "ios_reminders_complete"],
    "location": ["ios_location"],
  ]

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.wintermute/ios_connectors", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, reply in
      Task { @MainActor in
        guard let self = self else { return reply(FlutterMethodNotImplemented) }
        let data = call.arguments as? ToolData ?? [:]
        do {
          switch call.method {
          case "access":
            reply(Dictionary(uniqueKeysWithValues: self.groups.keys.map { ($0, self.granted($0)) }))
          case "authorize":
            guard let id = data["id"] as? String, self.groups[id] != nil else { throw ConnectorIssue("无效的 iOS 连接器") }
            reply(try await self.authorize(id))
          case "execute":
            let tool = try data.text("tool", 64)
            guard let group = self.groups.first(where: { $0.value.contains(tool) })?.key,
                  self.granted(group), let args = data["args"] as? ToolData else {
              throw ConnectorIssue("此工具不可用或缺少系统授权")
            }
            let timeout = try data.number("timeout", 1...120)
            let scope = try data.text("scope", 4096)
            guard let binding = try JSONSerialization.jsonObject(with: Data(scope.utf8)) as? [String],
                  let server = binding.first, let url = URL(string: server), url.host != nil else {
              throw ConnectorIssue("连接信息无效")
            }
            let request = ConnectorRequest(deadline: ProcessInfo.processInfo.systemUptime + Double(timeout), server: server)
            try request.check()
            let result: ToolData
            switch group {
            case "calendar", "contacts", "reminders", "photos":
              result = try await self.personalData(tool, args, request)
            case "location": result = try await self.location.read(request)
            case "health": result = try await self.healthSummary(args, request)
            case "music":
              guard #available(iOS 15, *) else { throw ConnectorIssue("Apple Music 需要 iOS 15 或更新版本") }
              result = try await self.music(tool, args, request)
            default: throw ConnectorIssue("未知工具")
            }
            reply(result)
          default: reply(FlutterMethodNotImplemented)
          }
        } catch {
          reply(FlutterError(code: "ios_connector", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func granted(_ group: String) -> Bool {
    switch group {
    case "calendar", "reminders":
      let status = EKEventStore.authorizationStatus(for: group == "calendar" ? .event : .reminder)
      if #available(iOS 17, *) { return status == .fullAccess }
      return status == .authorized
    case "contacts":
      let status = CNContactStore.authorizationStatus(for: .contacts)
      if #available(iOS 18, *), status == .limited { return true }
      return status == .authorized
    case "photos":
      if #available(iOS 14, *) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
      }
      return PHPhotoLibrary.authorizationStatus() == .authorized
    case "location": return location.granted
    case "music":
      if #available(iOS 15, *) { return MusicAuthorization.currentStatus == .authorized }
      return false
    // HealthKit intentionally does not expose read-grant status. An empty query is a valid outcome.
    case "health": return HKHealthStore.isHealthDataAvailable()
    default: return false
    }
  }

  private func authorize(_ group: String) async throws -> Bool {
    if group != "health", granted(group) { return true }
    switch group {
    case "calendar", "reminders":
      if #available(iOS 17, *) {
        if group == "calendar" { return try await events.requestFullAccessToEvents() }
        return try await events.requestFullAccessToReminders()
      }
      return try await withCheckedThrowingContinuation { cont in
        events.requestAccess(to: group == "calendar" ? .event : .reminder) { accepted, err in
          if let err = err { cont.resume(throwing: err) } else { cont.resume(returning: accepted) }
        }
      }
    case "contacts":
      let _: Bool = try await withCheckedThrowingContinuation { cont in
        contacts.requestAccess(for: .contacts) { allowed, error in
          if let error = error { cont.resume(throwing: error) } else { cont.resume(returning: allowed) }
        }
      }
    case "photos":
      await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        if #available(iOS 14, *) { PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in cont.resume() } }
        else { PHPhotoLibrary.requestAuthorization { _ in cont.resume() } }
      }
    case "health":
      guard granted("health") else { throw ConnectorIssue("本设备不支持健康数据") }
      return try await withCheckedThrowingContinuation { cont in
        health.requestAuthorization(toShare: [], read: Self.healthTypes) { completed, error in
          if let error = error { cont.resume(throwing: error) } else { cont.resume(returning: completed) }
        }
      }
    case "location": return await location.authorize()
    case "music":
      guard #available(iOS 15, *) else { throw ConnectorIssue("Apple Music 需要 iOS 15 或更新版本") }
      _ = await MusicAuthorization.request()
    default: return false
    }
    return granted(group)
  }
}

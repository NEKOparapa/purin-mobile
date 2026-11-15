import CoreLocation
import Flutter
import UIKit

// Core Location can wake the app without starting Flutter. Keep the selected
// terminal and its outbox together so a relaunch or a retry preserves ownership.
final class MobileSignals: NSObject, CLLocationManagerDelegate {
  private struct LocationOutbox: Codable {
    var scope: String
    var generation = UUID().uuidString
    var since = Date()
    var awaitingAuthorization = false
    var visitsSince: Date?
    var records: [Record] = []
    // iOS may report the same arrival again when the visit ends.
    var recentVisitIDs: [String] = []
  }

  private struct Record: Codable {
    let id: String
    let at: Int64
    let lat: Double
    let lon: Double
    let accuracy: Double
    let kind: String

    var message: [String: Any] {
      ["source": "location", "id": id, "at": at, "lat": lat,
       "lon": lon, "accuracy": accuracy, "kind": kind]
    }
  }

  private var outbox: LocationOutbox?
  private var collector: CLLocationManager?
  private var authorizationManager: CLLocationManager?
  private var permissionResult: FlutterResult?
  private var monitoringVisits = false
  private var updatingInForeground = false

  private func file() throws -> URL {
    let directory = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    return directory.appendingPathComponent("location-outbox.plist")
  }

  private func save(_ value: LocationOutbox?) throws {
    var url = try file()
    if let value = value {
      let data = try PropertyListEncoder().encode(value)
      try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      var properties = URLResourceValues()
      properties.isExcludedFromBackup = true
      try? url.setResourceValues(properties)
    } else if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    outbox = value
  }

  func restore() {
    if let url = try? file(), let bytes = try? Data(contentsOf: url) {
      outbox = try? PropertyListDecoder().decode(LocationOutbox.self, from: bytes)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(refresh), name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(refresh), name: UIApplication.didEnterBackgroundNotification, object: nil)
    refresh()
  }

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.wintermute/mobile_signals", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { return reply(FlutterMethodNotImplemented) }
      let args = call.arguments as? [String: Any] ?? [:]
      let scope = args["scope"] as? String
      let source = args["source"] as? String
      do {
        switch call.method {
        case "status":
          reply(self.status())
        case "configure":
          guard let scope = scope, let enabled = args["location"] as? Bool else {
            return reply(FlutterError(code: "arguments", message: "无效的采集配置", details: nil))
          }
          if scope.isEmpty || !enabled {
            self.stop()
            try self.save(nil)
          } else if self.outbox?.scope != scope {
            self.stop()
            try self.save(LocationOutbox(scope: scope))
          }
          self.refresh()
          reply(self.status())
        case "request":
          self.request(source, reply: reply)
        case "settings":
          guard source == "location" || source == "backgroundLocation" else { return reply(nil) }
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
          reply(nil)
        case "read":
          guard let box = self.outbox, box.scope == scope, self.permitted else { return reply([]) }
          reply(box.records.prefix(100).map { $0.message })
        case "ack":
          if var box = self.outbox, box.scope == scope, let ids = args["ids"] as? [String] {
            let acknowledged = Set(ids)
            box.records.removeAll { acknowledged.contains($0.id) }
            try self.save(box)
          }
          reply(nil)
        default:
          reply(FlutterMethodNotImplemented)
        }
      } catch {
        reply(FlutterError(code: "location_storage", message: "无法保存本机地点采集状态", details: nil))
      }
    }
  }

  private var authorization: CLAuthorizationStatus {
    if #available(iOS 14.0, *), let manager = collector ?? authorizationManager {
      return manager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private var permitted: Bool {
    authorization == .authorizedAlways || authorization == .authorizedWhenInUse
  }

  private func status() -> [String: Any] {
    let location: String
    switch authorization {
    case .authorizedAlways, .authorizedWhenInUse: location = "granted"
    case .notDetermined: location = "denied"
    case .denied: location = CLLocationManager.locationServicesEnabled() ? "blocked" : "disabled"
    default: location = "blocked"
    }
    return ["location": location, "usage": "unsupported", "backgroundLocation": authorization == .authorizedAlways]
  }

  private func request(_ source: String?, reply: @escaping FlutterResult) {
    guard source == "location" || source == "backgroundLocation" else { return reply(nil) }
    if authorizationManager == nil {
      let manager = CLLocationManager()
      authorizationManager = manager
      manager.delegate = self
    }
    if source == "backgroundLocation" && authorization == .authorizedWhenInUse {
      let key = "wintermute.requestedAlwaysLocation"
      if UserDefaults.standard.bool(forKey: key) {
        // iOS limits repeat upgrade prompts. The user can still choose Always in Settings.
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      } else {
        UserDefaults.standard.set(true, forKey: key)
        authorizationManager?.requestAlwaysAuthorization()
      }
      reply(nil) // iOS may defer the first upgrade prompt.
    } else if authorization == .notDetermined && source == "location" {
      guard permissionResult == nil else {
        return reply(FlutterError(code: "permission_pending", message: "正在等待定位授权", details: nil))
      }
      permissionResult = reply
      authorizationManager?.requestWhenInUseAuthorization()
    } else {
      reply(nil)
    }
  }

  private func stop() {
    collector?.delegate = nil
    collector?.stopUpdatingLocation()
    if monitoringVisits {
      collector?.stopMonitoringVisits()
      collector?.stopMonitoringSignificantLocationChanges()
    }
    collector = nil
    monitoringVisits = false
    updatingInForeground = false
  }

  @objc private func refresh() {
    guard outbox != nil, permitted else {
      stop()
      if !permitted, let previous = outbox, !previous.awaitingAuthorization {
        var box = LocationOutbox(scope: previous.scope)
        box.awaitingAuthorization = true
        try? save(box)
      }
      // Continue watching authorization while enabled, even after revocation.
      // A change made in Settings can then restart collection without a Flutter scene.
      if outbox != nil && authorizationManager == nil {
        let manager = CLLocationManager()
        authorizationManager = manager
        manager.delegate = self
      }
      return
    }
    if var box = outbox, box.awaitingAuthorization {
      // Visits can refer back to an arrival before permission was restored.
      box.since = Date()
      box.awaitingAuthorization = false
      do { try save(box) } catch { return }
    }
    if collector == nil {
      let manager = CLLocationManager()
      manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
      manager.distanceFilter = 250
      collector = manager
      manager.delegate = self
    }
    let background = authorization == .authorizedAlways
    if var box = outbox, (box.visitsSince != nil) != background {
      box.visitsSince = background ? Date() : nil
      do { try save(box) } catch { return }
    }
    if background != monitoringVisits {
      monitoringVisits = background
      if background {
        collector?.startMonitoringVisits()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
          collector?.startMonitoringSignificantLocationChanges()
        }
      } else {
        collector?.stopMonitoringVisits()
        collector?.stopMonitoringSignificantLocationChanges()
      }
    }
    let foreground = UIApplication.shared.applicationState == .active
    if foreground != updatingInForeground {
      updatingInForeground = foreground
      if foreground { collector?.startUpdatingLocation() }
      else { collector?.stopUpdatingLocation() }
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationChanged(manager)
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    authorizationChanged(manager) // iOS 13 delegate
  }

  private func authorizationChanged(_ manager: CLLocationManager) {
    guard manager === authorizationManager || manager === collector else { return }
    refresh()
    if authorization != .notDetermined, let reply = permissionResult {
      permissionResult = nil
      reply(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard manager === collector, permitted else { return }
    for location in locations {
      record("fix", location.timestamp, location.coordinate, location.horizontalAccuracy)
    }
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    guard manager === collector, authorization == .authorizedAlways, let since = outbox?.visitsSince else { return }
    if visit.arrivalDate >= since {
      record("arrival", visit.arrivalDate, visit.coordinate, visit.horizontalAccuracy)
    }
    if visit.departureDate != .distantFuture, visit.departureDate >= since {
      record("departure", visit.departureDate, visit.coordinate, visit.horizontalAccuracy)
    }
  }

  private func record(_ kind: String, _ date: Date, _ coordinate: CLLocationCoordinate2D, _ accuracy: Double) {
    guard var box = outbox, date >= box.since, CLLocationCoordinate2DIsValid(coordinate),
          accuracy.isFinite, accuracy >= 0 else { return }
    let at = Int64(date.timeIntervalSince1970 * 1000)
    let id = "\(box.generation)-\(kind)-\(at)"
    guard !box.records.contains(where: { $0.id == id }) else { return }
    if kind != "fix" {
      guard !box.recentVisitIDs.contains(id) else { return }
      box.recentVisitIDs = Array((box.recentVisitIDs + [id]).suffix(64))
    }
    let event = Record(id: id, at: at, lat: coordinate.latitude, lon: coordinate.longitude,
                       accuracy: accuracy, kind: kind)
    // Visit callbacks can arrive well after the initial position fix.
    let index = box.records.firstIndex { $0.at > at } ?? box.records.endIndex
    box.records.insert(event, at: index)
    try? save(box)
  }
}

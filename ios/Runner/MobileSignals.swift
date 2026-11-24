import CoreLocation
import Network
import SystemConfiguration.CaptiveNetwork
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
    var lastSample: Date?
    var network: Bool?
    var records: [Record] = []
  }

  private struct Record: Codable {
    let id: String
    let at: Int64
    let lat: Double
    let lon: Double
    let accuracy: Double
    let kind: String
    var wifiState: String?
    var wifiSsid: String?

    var message: [String: Any] {
      var result: [String: Any] = ["source": "location", "id": id, "at": at, "lat": lat,
       "lon": lon, "accuracy": accuracy, "kind": kind]
      result["wifiState"] = wifiState
      result["wifiSsid"] = wifiSsid
      return result
    }
  }

  private var outbox: LocationOutbox?
  private var collector: CLLocationManager?
  private var authorizationManager: CLLocationManager?
  private var permissionResult: FlutterResult?
  private var channel: FlutterMethodChannel?
  private var wifiMonitor: NWPathMonitor?
  private var wifiConnected: Bool?
  private var updating = false

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
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { return reply(FlutterMethodNotImplemented) }
      let args = call.arguments as? [String: Any] ?? [:]
      let scope = args["scope"] as? String
      let source = args["source"] as? String
      do {
        switch call.method {
        case "deviceName":
          reply(UIDevice.current.name)
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
          if var box = self.outbox, box.network != (args["network"] as? Bool ?? false) {
            box.network = args["network"] as? Bool ?? false
            try self.save(box)
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
    collector = nil
    updating = false
    configureWifi(false)
  }

  private func configureWifi(_ enabled: Bool) {
    if !enabled {
      wifiMonitor?.cancel()
      wifiMonitor = nil
      wifiConnected = nil
    } else if wifiMonitor == nil {
      let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
      wifiMonitor = monitor
      monitor.pathUpdateHandler = { [weak self, weak monitor] path in
        guard let self = self, self.wifiMonitor === monitor else { return }
        self.wifiConnected = path.status == .satisfied
      }
      monitor.start(queue: .main)
    }
  }

  private func sampleWifi() -> (String, String?) {
    for interface in CNCopySupportedInterfaces() as? [String] ?? [] {
      if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any],
         let name = info[kCNNetworkInfoKeySSID as String] as? String, !name.isEmpty {
        return ("connected", name)
      }
    }
    guard let connected = wifiConnected else { return ("unknown", nil) }
    return (connected ? "connected" : "disconnected", nil)
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
      manager.distanceFilter = kCLDistanceFilterNone
      manager.pausesLocationUpdatesAutomatically = false
      collector = manager
      manager.delegate = self
    }
    let background = authorization == .authorizedAlways
    collector?.allowsBackgroundLocationUpdates = background
    configureWifi(outbox?.network == true)
    let shouldRun = background || UIApplication.shared.applicationState != .background
    if shouldRun != updating {
      updating = shouldRun
      if shouldRun { collector?.startUpdatingLocation() }
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
    guard let location = locations.last, var box = outbox,
          location.timestamp >= box.since,
          location.timestamp.timeIntervalSince(box.lastSample ?? .distantPast) >= 20 * 60,
          CLLocationCoordinate2DIsValid(location.coordinate),
          location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0 else { return }
    let at = Int64(location.timestamp.timeIntervalSince1970 * 1000)
    let wifi = box.network == true ? sampleWifi() : nil
    let coordinate = location.coordinate
    box.records.append(Record(id: "\(box.generation)-fix-\(at)", at: at,
        lat: coordinate.latitude, lon: coordinate.longitude, accuracy: location.horizontalAccuracy,
        kind: "fix", wifiState: wifi?.0, wifiSsid: wifi?.1))
    box.lastSample = location.timestamp
    do {
      try save(box)
      channel?.invokeMethod("locationReady", arguments: nil)
    } catch { return }
  }
}

import CoreLocation
import Foundation

// This one-shot manager is independent of the optional background timeline collector.
final class IOSConnectorLocation: NSObject, CLLocationManagerDelegate {
  private lazy var manager: CLLocationManager = {
    let value = CLLocationManager()
    value.delegate = self
    value.desiredAccuracy = kCLLocationAccuracyHundredMeters
    return value
  }()
  private var permission: CheckedContinuation<Bool, Never>?
  private var fix: CheckedContinuation<ToolData, Error>?
  private var expiry: Timer?
  private var status: CLAuthorizationStatus {
    if #available(iOS 14, *) { return manager.authorizationStatus }
    return CLLocationManager.authorizationStatus()
  }
  var granted: Bool { status == .authorizedAlways || status == .authorizedWhenInUse }

  @MainActor func authorize() async -> Bool {
    if status != .notDetermined { return granted }
    guard permission == nil else { return false }
    return await withCheckedContinuation { continuation in
      permission = continuation
      manager.requestWhenInUseAuthorization()
    }
  }

  @MainActor func read(_ request: ConnectorRequest) async throws -> ToolData {
    try request.check()
    guard granted, fix == nil else { throw ConnectorIssue("定位不可用或已有定位请求") }
    return try await withCheckedThrowingContinuation { continuation in
      fix = continuation
      expiry = Timer.scheduledTimer(withTimeInterval: max(0.1, request.deadline - ProcessInfo.processInfo.systemUptime - 0.1),
                                    repeats: false) { [weak self] _ in
        self?.finish(.failure(ConnectorIssue("未能在时限内取得当前位置")))
      }
      manager.requestLocation()
    }
  }

  private func authorizationChanged() {
    if status != .notDetermined {
      let waiter = permission
      permission = nil
      waiter?.resume(returning: granted)
      if !granted { finish(.failure(ConnectorIssue("系统定位权限已关闭"))) }
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorizationChanged() }
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) { authorizationChanged() }

  private func finish(_ result: Result<ToolData, Error>) {
    guard let waiter = fix else { return }
    fix = nil
    expiry?.invalidate()
    expiry = nil
    manager.stopUpdatingLocation()
    waiter.resume(with: result)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let position = locations.last(where: { CLLocationCoordinate2DIsValid($0.coordinate) && $0.horizontalAccuracy >= 0 }) else {
      return finish(.failure(ConnectorIssue("没有有效定位")))
    }
    finish(.success(["latitude": position.coordinate.latitude, "longitude": position.coordinate.longitude,
                     "accuracy_m": position.horizontalAccuracy, "timestamp_ms": position.timestamp.connectorMillis]))
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(.failure(error)) }
}

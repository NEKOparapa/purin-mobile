import Darwin
import Foundation

/// Shared by the containing app and its broadcast extension. Files are private
/// to one terminal generation. Only the host can change consent or acknowledge.
final class ScreenshotStore {
  struct Config: Codable {
    let scope: String
    let generation: UUID
    var interval: Int
    var backgroundSince: Date?
  }

  enum Failure: Error { case appGroup, lock, disabled }

  private let root: URL
  private let files = FileManager.default

  convenience init() throws {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:
      "group.dev.purin.purinMobile.screenshots") else { throw Failure.appGroup }
    try self.init(root: group.appendingPathComponent("Screenshots", isDirectory: true))
  }

  init(root: URL) throws {
    self.root = root
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    var url = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  private func locked<T>(_ action: () throws -> T) throws -> T {
    let fd = open(root.appendingPathComponent("queue.lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw Failure.lock }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw Failure.lock }
    defer { flock(fd, LOCK_UN) }
    return try action()
  }

  private var configURL: URL { root.appendingPathComponent("config.plist") }
  private func config() throws -> Config? {
    guard files.fileExists(atPath: configURL.path) else { return nil }
    return try PropertyListDecoder().decode(Config.self, from: Data(contentsOf: configURL))
  }

  private func save(_ config: Config) throws {
    try PropertyListEncoder().encode(config).write(to: configURL,
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  private func folder(_ c: Config) -> URL {
    root.appendingPathComponent(c.generation.uuidString, isDirectory: true)
  }

  func configure(scope: String, enabled: Bool, interval: Int, background: Bool) throws {
    try locked {
      let old = try config()
      if enabled && !scope.isEmpty {
        if var old = old, old.scope == scope {
          if old.interval != interval { old.interval = interval; try save(old) }
        } else {
          let next = Config(scope: scope, generation: UUID(), interval: interval,
                            backgroundSince: background ? Date() : nil)
          try files.createDirectory(at: folder(next), withIntermediateDirectories: true)
          // Class A data becomes unreadable while the device is protected. The
          // extension can check this even while the Flutter host is suspended.
          try Data([1]).write(to: folder(next).appendingPathComponent("unlocked"),
                              options: [.atomic, .completeFileProtection])
          try save(next)
        }
      } else if old != nil {
        try files.removeItem(at: configURL)
      }
      // Also collect stale generations after an interruption during a switch.
      let keep = try config()?.generation.uuidString
      for url in try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
        if UUID(uuidString: url.lastPathComponent) != nil && url.lastPathComponent != keep {
          try files.removeItem(at: url)
        }
      }
    }
  }

  func setBackground(_ background: Bool) throws {
    try locked {
      guard var c = try config(), (c.backgroundSince != nil) != background else { return }
      c.backgroundSince = background ? Date() : nil
      try save(c)
    }
  }

  func current() throws -> Config? { try locked { try config() } }

  /// The kernel releases this lock if the producer is killed. A stale "active"
  /// flag would otherwise survive a crash or an extension memory-pressure kill.
  func begin(_ generation: UUID) throws -> Int32 {
    try locked {
      guard let c = try config(), c.generation == generation else { throw Failure.disabled }
      let fd = open(folder(c).appendingPathComponent("active.lock").path, O_CREAT | O_RDWR, 0o600)
      guard fd >= 0 else { throw Failure.lock }
      guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw Failure.lock }
      return fd
    }
  }

  func status() throws -> [String: Any] {
    try locked {
      guard let c = try config() else { return ["access": "ready", "pending": 0] }
      let fd = open(folder(c).appendingPathComponent("active.lock").path, O_RDONLY)
      var active = false
      if fd >= 0 {
        active = flock(fd, LOCK_SH | LOCK_NB) != 0 && errno == EWOULDBLOCK
        close(fd)
      }
      return ["access": active ? "active" : "ready", "pending": try images(c).count]
    }
  }

  private func images(_ c: Config) throws -> [URL] {
    try files.contentsOfDirectory(at: folder(c), includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  func append(_ data: Data, generation: UUID, at: Date) throws {
    try locked {
      guard let c = try config(), c.generation == generation,
            let since = c.backgroundSince, at.timeIntervalSince(since) >= 1 else { return }
      // Bound the offline queue, preserving earlier evidence awaiting receipt.
      guard (try? Data(contentsOf: folder(c).appendingPathComponent("unlocked"))) != nil,
            try images(c).count < 64 else { return }
      let name = "\(Int64(at.timeIntervalSince1970 * 1000))-\(UUID().uuidString).jpg"
      try data.write(to: folder(c).appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }
  }

  private func parse(_ url: URL) -> (id: String, at: Int64)? {
    let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-", maxSplits: 1)
    guard parts.count == 2, let time = Int64(parts[0]), let id = UUID(uuidString: String(parts[1])) else { return nil }
    return (id.uuidString, time)
  }

  func read(scope: String) throws -> [[String: Any]] {
    try locked {
      guard let c = try config(), c.scope == scope else { return [] }
      return try images(c).compactMap { url in
        guard let item = parse(url) else { return nil }
        return ["id": item.id, "at": item.at]
      }
    }
  }

  func bytes(scope: String, id: String) throws -> Data? {
    try locked {
      guard let c = try config(), c.scope == scope,
            let url = try images(c).first(where: { parse($0)?.id == id }) else { return nil }
      return try Data(contentsOf: url)
    }
  }

  func ack(scope: String, ids: Set<String>) throws {
    try locked {
      guard let c = try config(), c.scope == scope else { return }
      for url in try images(c) {
        if let id = parse(url)?.id, ids.contains(id) { try files.removeItem(at: url) }
      }
    }
  }
}

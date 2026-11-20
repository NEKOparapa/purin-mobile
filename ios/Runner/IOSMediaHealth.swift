import HealthKit
import MusicKit
import UIKit

extension IOSConnectorHost {
  @available(iOS 15, *)
  func music(_ tool: String, _ args: ToolData, _ request: ConnectorRequest) async throws -> ToolData {
    if tool == "ios_music_search" {
      var search = MusicCatalogSearchRequest(term: try args.text("query", 80), types: [Song.self])
      search.limit = try args.number("limit", 1...30, fallback: 10)
      let response = try await search.response()
      let rows: [ToolData] = response.songs.map { song in
        var item: ToolData = ["id": song.id.rawValue, "title": song.title, "artist": song.artistName]
        item["duration_seconds"] = song.duration
        return item
      }
      return ["items": rows]
    }
    let player = SystemMusicPlayer.shared
    switch try args.text("action", 16) {
    case "play":
      let id = MusicItemID(try args.text("id", 100))
      let subscription = try await MusicSubscription.current
      guard subscription.canPlayCatalogContent else { throw ConnectorIssue("此 Apple Music 账号无法播放曲库歌曲") }
      let lookup = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
      guard let song = try await lookup.response().items.first else { throw ConnectorIssue("曲库中没有这首歌") }
      try request.check()
      player.queue = [song]
      try await player.play()
    case "pause": player.pause()
    case "resume": try await player.play()
    case "next": try await player.skipToNextEntry()
    case "previous": try await player.skipToPreviousEntry()
    case "seek":
      let seconds = try args.number("seconds", 0...86400)
      guard player.queue.currentEntry != nil else { throw ConnectorIssue("没有正在播放的歌曲") }
      player.playbackTime = TimeInterval(seconds)
    case "status": break
    default: throw ConnectorIssue("不支持的播放操作")
    }
    var result: ToolData = ["state": String(describing: player.state.playbackStatus)]
    result["title"] = player.queue.currentEntry?.title
    if player.playbackTime.isFinite { result["position_seconds"] = player.playbackTime }
    return result
  }

  static var healthTypes: Set<HKObjectType> {
    var types: Set<HKObjectType> = [HKObjectType.workoutType()]
    if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
    if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
    return types
  }

  private func samples(_ type: HKSampleType, _ predicate: NSPredicate) async throws -> [HKSample] {
    try await withCheckedThrowingContinuation { cont in
      health.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, rows, error in
        if let error = error { cont.resume(throwing: error) } else { cont.resume(returning: rows ?? []) }
      })
    }
  }

  private func dailySteps(_ predicate: NSPredicate, type: HKQuantityType) async throws -> Int? {
    try await withCheckedThrowingContinuation { cont in
      health.execute(HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, err in
        if let error = err as NSError? {
          if #available(iOS 14, *), error.domain == HKErrorDomain, error.code == HKError.Code.errorNoData.rawValue {
            cont.resume(returning: nil)
          } else {
            cont.resume(throwing: error)
          }
          return
        }
        cont.resume(returning: stats?.sumQuantity().map { Int($0.doubleValue(for: .count())) })
      })
    }
  }

  func healthSummary(_ args: ToolData, _ request: ConnectorRequest) async throws -> ToolData {
    let offset = try args.number("days_ago", 0...6, fallback: 0)
    let calendar = Calendar.current
    guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date())),
          let end = calendar.date(byAdding: .day, value: 1, to: day),
          let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
          let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { throw ConnectorIssue("健康数据不可用") }
    let started = HKQuery.predicateForSamples(withStart: day, end: end, options: .strictStartDate)
    let overlaps = HKQuery.predicateForSamples(withStart: day, end: end, options: [])
    let steps = try await dailySteps(started, type: stepType)
    let workouts = try await samples(HKObjectType.workoutType(), started).compactMap { $0 as? HKWorkout }
    let sleep = try await samples(sleepType, overlaps).compactMap { $0 as? HKCategorySample }
    var asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleep.rawValue]
    if #available(iOS 16, *) {
      asleep.formUnion([HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue])
    }
    // Multiple devices may report the same sleep interval. Clip at local midnight and count the union.
    var cursor = day, sleeping: TimeInterval = 0
    for sample in sleep.filter({ asleep.contains($0.value) }).sorted(by: { $0.startDate < $1.startDate }) {
      let finish = min(end, sample.endDate)
      sleeping += max(0, finish.timeIntervalSince(max(cursor, sample.startDate)))
      cursor = max(cursor, finish)
    }
    var data: ToolData = ["day_start_ms": day.connectorMillis, "timezone": calendar.timeZone.identifier]
    var lines = [DateFormatter.localizedString(from: day, dateStyle: .medium, timeStyle: .none)]
    if let steps = steps { data["steps"] = steps; lines.append("步数：\(steps)") }
    if sleeping > 0 {
      let minutes = Int(sleeping / 60)
      data["sleep_minutes"] = minutes
      lines.append("当日睡眠：\(minutes) 分钟")
    }
    if !workouts.isEmpty {
      let minutes = Int(workouts.reduce(0.0) { $0 + $1.duration } / 60)
      data["workouts"] = workouts.count
      data["workout_minutes"] = minutes
      lines.append("当日开始的锻炼：\(workouts.count) 次，共 \(minutes) 分钟")
    }
    if lines.count == 1 { data["status"] = "no_visible_data"; lines.append("没有可读取的记录") }
    let host = try request.presenter()
    let approved = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      let alert = UIAlertController(title: "分享这一天的健康摘要？",
        message: lines.joined(separator: "\n") + "\n\n接收服务：\(request.server)\n仅在你使用该服务进行健康或健身分析时分享。摘要将保存到发起调用的会话。",
        preferredStyle: .alert)
      var waiting = true
      func finish(_ allow: Bool) {
        guard waiting else { return }
        waiting = false
        continuation.resume(returning: allow)
      }
      alert.addAction(UIAlertAction(title: "不分享", style: .cancel) { _ in finish(false) })
      alert.addAction(UIAlertAction(title: "分享摘要", style: .default) { _ in finish(true) })
      host.present(alert, animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, request.deadline - ProcessInfo.processInfo.systemUptime - 0.2)) {
        if waiting { alert.dismiss(animated: false); finish(false) }
      }
    }
    guard approved else { throw ConnectorIssue("本次健康摘要未分享") }
    try request.check()
    return data
  }
}

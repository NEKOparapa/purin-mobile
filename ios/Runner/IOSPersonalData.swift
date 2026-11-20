import Contacts
import EventKit
import Photos
import UIKit

extension IOSConnectorHost {
  func personalData(_ tool: String, _ args: ToolData, _ request: ConnectorRequest) async throws -> ToolData {
    switch tool {
    case "ios_calendar_events":
      let (start, end) = try args.interval()
      let limit = try args.number("limit", 1...30, fallback: 10)
      let found = events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: nil))
      let rows: [ToolData] = found.sorted { $0.startDate < $1.startDate }.prefix(limit).map { event in
        var row: ToolData = ["title": event.title ?? "", "start_ms": event.startDate.connectorMillis,
                             "end_ms": event.endDate.connectorMillis, "all_day": event.isAllDay]
        row["location"] = event.location
        return row
      }
      return ["items": rows, "truncated": found.count > limit]
    case "ios_calendar_create":
      let (start, end) = try args.interval()
      let event = EKEvent(eventStore: events)
      event.title = try args.text("title", 200)
      event.startDate = start
      event.endDate = end
      if args["location"] != nil, (args["location"] as? String) != "" {
        event.location = try args.text("location", 200)
      }
      guard let calendar = events.defaultCalendarForNewEvents else { throw ConnectorIssue("没有可写入的默认日历") }
      event.calendar = calendar
      try events.save(event, span: .thisEvent)
      return ["id": event.calendarItemIdentifier, "status": "created"]
    case "ios_reminders_list":
      let limit = try args.number("limit", 1...30, fallback: 10)
      let predicate = events.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
      let reminders: [EKReminder] = try await withCheckedThrowingContinuation { cont in
        events.fetchReminders(matching: predicate) { rows in
          if let rows = rows { cont.resume(returning: rows) }
          else { cont.resume(throwing: ConnectorIssue("无法读取提醒事项")) }
        }
      }
      let sorted = reminders.sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
      let rows: [ToolData] = sorted.prefix(limit).map { reminder in
        var row: ToolData = ["id": reminder.calendarItemIdentifier, "title": reminder.title ?? ""]
        row["due_ms"] = reminder.dueDateComponents?.date?.connectorMillis
        return row
      }
      return ["items": rows, "truncated": sorted.count > limit]
    case "ios_reminders_create":
      let value = EKReminder(eventStore: events)
      value.title = try args.text("title", 200)
      guard let calendar = events.defaultCalendarForNewReminders() else { throw ConnectorIssue("没有默认的提醒事项列表") }
      value.calendar = calendar
      if let due = args["due_ms"], !(due is NSNull) {
        let ms = try args.number("due_ms", 1...4_102_444_800_000)
        let date = Date(timeIntervalSince1970: Double(ms)/1000)
        value.dueDateComponents = Calendar.current.dateComponents([.calendar,.timeZone,.year,.month,.day,.hour,.minute,.second], from: date)
        value.addAlarm(EKAlarm(absoluteDate: date))
      }
      try events.save(value, commit: true)
      return ["id": value.calendarItemIdentifier, "status": "created"]
    case "ios_reminders_complete":
      guard let value = events.calendarItem(withIdentifier: try args.text("id", 200)) as? EKReminder else {
        throw ConnectorIssue("未找到该提醒事项")
      }
      if !value.isCompleted {
        value.isCompleted = true
        try events.save(value, commit: true)
      }
      return ["id": value.calendarItemIdentifier, "status": "completed"]
    case "ios_contacts":
      let query = try args.text("query", 80)
      let limit = try args.number("limit", 1...30, fallback: 10)
      return try await Task.detached(priority: .userInitiated) {
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                      CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let found = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
        let rows: [ToolData] = found.prefix(limit).map { contact in
          ["name": CNContactFormatter.string(from: contact, style: .fullName) ?? "",
           "phones": contact.phoneNumbers.prefix(5).map { $0.value.stringValue },
           "emails": contact.emailAddresses.prefix(5).map { $0.value as String }]
        }
        return ["items": rows, "truncated": found.count > limit]
      }.value
    case "ios_photos_search":
      let (start, end) = try args.interval()
      let limit = try args.number("limit", 1...30, fallback: 10)
      let kind = args["kind"] as? String ?? "all"
      guard ["all","screenshot","video","photo"].contains(kind) else { throw ConnectorIssue("未知的照片类型") }
      let options = PHFetchOptions()
      var filters = [NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)]
      if kind != "all" {
        let type: PHAssetMediaType = kind == "video" ? .video : .image
        filters.append(NSPredicate(format: "mediaType == %d", type.rawValue))
      }
      options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: filters)
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.fetchLimit = limit + 1
      let found: PHFetchResult<PHAsset>
      if kind == "screenshot" {
        guard let album = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil).firstObject else {
          return ["items": [], "truncated": false]
        }
        found = PHAsset.fetchAssets(in: album, options: options)
      } else { found = PHAsset.fetchAssets(with: options) }
      let rows: [ToolData] = (0..<min(limit, found.count)).map { index in
        let asset = found.object(at: index)
        var row: ToolData = ["id": asset.localIdentifier, "width": asset.pixelWidth, "height": asset.pixelHeight,
                             "kind": asset.mediaSubtypes.contains(.photoScreenshot) ? "screenshot" : asset.mediaType == .video ? "video" : "photo"]
        row["created_ms"] = asset.creationDate?.connectorMillis
        return row
      }
      return ["items": rows, "truncated": found.count > limit]
    case "ios_photo_open":
      let id = try args.text("id", 200)
      guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
        throw ConnectorIssue("照片不可用或不在授权范围内")
      }
      let options = PHImageRequestOptions()
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .highQualityFormat
      let image: UIImage = try await withCheckedThrowingContinuation { cont in
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1024, height: 1024),
                                              contentMode: .aspectFit, options: options) { image, info in
          if info?[PHImageResultIsDegradedKey] as? Bool == true { return }
          if let image = image { cont.resume(returning: image) }
          else { cont.resume(throwing: ConnectorIssue("无法载入照片预览")) }
        }
      }
      let host = try request.presenter()
      if let preview = (host as? UINavigationController)?.visibleViewController as? ConnectorPhotoPreview {
        preview.imageView.image = image
      } else {
        let page = ConnectorPhotoPreview()
        page.imageView.image = image
        host.present(UINavigationController(rootViewController: page), animated: true)
      }
      return ["status": "opened"]
    default: throw ConnectorIssue("未知 iOS 工具")
    }
  }

}

private final class ConnectorPhotoPreview: UIViewController {
  let imageView = UIImageView()
  override func loadView() {
    imageView.backgroundColor = .systemBackground
    imageView.contentMode = .scaleAspectFit
    view = imageView
    title = "照片预览"
    navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
  }
  @objc private func close() { dismiss(animated: true) }
}

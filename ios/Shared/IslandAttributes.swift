import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct IslandAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let phase: String
    let lines: [String]
    let dayEnd: Date?
  }
  let owner: String
}

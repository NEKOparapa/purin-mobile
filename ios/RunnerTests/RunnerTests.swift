import Darwin
import Foundation
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testScreenshotConsentAndTerminalIsolation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let host = try ScreenshotStore(root: root)
    let producer = try ScreenshotStore(root: root)
    try host.configure(scope: "a", enabled: true, interval: 300, background: false)
    let generation = try XCTUnwrap(try host.current()?.generation)
    let data = Data([1, 2, 3])
    let at = Date().addingTimeInterval(5)
    try producer.append(data, generation: generation, at: at)
    XCTAssertTrue(try host.read(scope: "a").isEmpty)
    try host.setBackground(true)
    try producer.append(data, generation: generation, at: at)
    let row = try XCTUnwrap(try host.read(scope: "a").first)
    let id = try XCTUnwrap(row["id"] as? String)
    XCTAssertEqual(try host.bytes(scope: "a", id: id), data)
    XCTAssertNil(try host.bytes(scope: "b", id: id))
    XCTAssertNil(row["app"])
    try host.ack(scope: "b", ids: [id])
    XCTAssertEqual(try producer.read(scope: "a").count, 1)
    try host.ack(scope: "a", ids: [id])
    try host.ack(scope: "a", ids: [id])
    XCTAssertTrue(try producer.read(scope: "a").isEmpty)
    let descriptor = try producer.begin(generation)
    XCTAssertEqual(try host.status()["access"] as? String, "active")
    close(descriptor)
    XCTAssertEqual(try host.status()["access"] as? String, "ready")
    try producer.append(data, generation: generation, at: at)
    try host.configure(scope: "b", enabled: true, interval: 60, background: true)
    try producer.append(data, generation: generation, at: at)
    XCTAssertTrue(try host.read(scope: "b").isEmpty)
    try host.configure(scope: "b", enabled: false, interval: 60, background: true)
    XCTAssertNil(try host.current())
  }

}

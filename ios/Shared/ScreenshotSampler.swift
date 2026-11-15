import CoreImage
import CoreMedia
import Darwin
import Foundation
import ImageIO

/// Called on the producer's serial sample queue.
final class ScreenshotSampler {
  private let store: ScreenshotStore
  let generation: UUID
  private var descriptor: Int32
  private let context = CIContext(options: [.cacheIntermediates: false])
  private var lastCapture: TimeInterval
  private var nextCheck: TimeInterval = 0

  init(store: ScreenshotStore, generation: UUID) throws {
    self.store = store
    self.generation = generation
    descriptor = try store.begin(generation)
    lastCapture = ProcessInfo.processInfo.systemUptime
  }

  deinit { close(descriptor) }

  func accept(_ sample: CMSampleBuffer, orientation: Int32 = 1) {
    let uptime = ProcessInfo.processInfo.systemUptime
    guard uptime >= nextCheck else { return }
    nextCheck = uptime + 1
    guard let c = try? store.current(), c.generation == generation,
          let since = c.backgroundSince, Date().timeIntervalSince(since) >= 1,
          uptime - lastCapture >= Double(c.interval),
          CMSampleBufferDataIsReady(sample), let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
    lastCapture = uptime
    let at = Date()
    autoreleasepool {
      let input = CIImage(cvPixelBuffer: buffer).oriented(forExifOrientation: orientation)
      let scale = min(1, 1440 / max(input.extent.width, input.extent.height))
      let image = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      guard let color = CGColorSpace(name: CGColorSpace.sRGB),
            let data = context.jpegRepresentation(of: image, colorSpace: color, options: [
              CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.72
            ]), data.count < 4 * 1024 * 1024 else { return }
      try? store.append(data, generation: generation, at: at)
    }
  }
}

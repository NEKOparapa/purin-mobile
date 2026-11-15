#if canImport(ScreenCaptureKit) && compiler(>=6.4)
import CoreMedia
import ScreenCaptureKit
import UIKit

@available(iOS 27.0, *)
final class ScreenCaptureSession: NSObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
  private let picker = SCContentSharingPicker.shared
  private let store: ScreenshotStore
  private var generation: UUID?
  private var stream: SCStream?
  private var sampler: ScreenshotSampler?

  init(store: ScreenshotStore) { self.store = store }

  func present(generation: UUID) {
    guard stream == nil else { return }
    if self.generation == nil { picker.add(self) }
    self.generation = generation
    var config = SCContentSharingPickerConfiguration()
    config.showsMicrophoneControl = false
    picker.defaultConfiguration = config
    picker.isActive = true
    picker.present()
  }

  private func stop() {
    let old = stream
    stream = nil
    sampler = nil
    generation = nil
    picker.remove(self)
    picker.isActive = false
    old?.stopCapture(completionHandler: { _ in })
  }

  func reconcile(generation: UUID?) {
    if self.generation != nil && generation != self.generation { stop() }
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
                            for selected: SCStream?) {
    DispatchQueue.main.async {
      guard let generation = self.generation, (try? self.store.current())?.generation == generation else { return }
      if let selected = selected, selected === self.stream {
        self.sampler = nil
        self.stream = nil
        selected.stopCapture(completionHandler: { _ in })
      }
      guard self.stream == nil else { return }
      do {
        let config = SCStreamConfiguration()
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        self.stream = stream
        stream.startCapture { error in
          DispatchQueue.main.async {
            guard self.stream === stream else { return }
            guard error == nil else { self.stop(); return }
            do { self.sampler = try ScreenshotSampler(store: self.store, generation: generation) }
            catch { self.stop() }
          }
        }
      } catch { self.stop() }
    }
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
    DispatchQueue.main.async { if self.stream == nil { self.stop() } }
  }

  func contentSharingPickerStartDidFailWithError(_ error: Error) {
    DispatchQueue.main.async { if self.stream == nil { self.stop() } }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { if self.stream === stream { self.stop() } }
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard self.stream === stream, type == .screen, UIApplication.shared.isProtectedDataAvailable,
          let frames = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]], let value = frames.first?[.status] as? Int,
          SCFrameStatus(rawValue: value) == .complete else { return }
    sampler?.accept(sampleBuffer)
  }
}
#endif

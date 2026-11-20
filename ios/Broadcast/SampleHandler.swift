import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
  private var sampler: ScreenshotSampler?
  private var stopTimer: DispatchSourceTimer?
  private var paused = false

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    do {
      let store = try ScreenshotStore()
      guard let config = try store.current() else { throw ScreenshotStore.Failure.disabled }
      sampler = try ScreenshotSampler(store: store, generation: config.generation)
      // A paused broadcast may get no video callbacks. Observe host revocation
      // independently so the system's broadcast also ends on terminal switch.
      let timer = DispatchSource.makeTimerSource(queue: .main)
      timer.schedule(deadline: .now() + 1, repeating: 1)
      timer.setEventHandler { [weak self] in
        guard (try? store.current())?.generation != config.generation else { return }
        self?.endDisabled()
      }
      stopTimer = timer
      timer.resume()
    } catch { endDisabled() }
  }

  private func endDisabled() {
    stopTimer?.cancel()
    finishBroadcastWithError(NSError(domain: "dev.wintermute.screenshots", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "定时截图已关闭或设备已切换。"]))
  }

  override func broadcastPaused() { paused = true }
  override func broadcastResumed() { paused = false }
  override func broadcastFinished() { stopTimer?.cancel(); sampler = nil }

  override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
    guard sampleBufferType == .video, !paused else { return }
    let rotation = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                   attachmentModeOut: nil) as? NSNumber
    sampler?.accept(sampleBuffer, orientation: rotation?.int32Value ?? 1)
  }
}

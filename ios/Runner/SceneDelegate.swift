import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    let island = (UIApplication.shared.delegate as? AppDelegate)?.island
    let remaining = contexts.filter { island?.open($0.url) != true }
    if !remaining.isEmpty { super.scene(scene, openURLContexts: Set(remaining)) }
  }

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let response = connectionOptions.notificationResponse {
      (UIApplication.shared.delegate as? AppDelegate)?.notices.open(response)
    }
  }
}

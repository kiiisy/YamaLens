import UIKit

@MainActor
final class YamaLensAppDelegate: NSObject, UIApplicationDelegate {
    private var backgroundSessionCompletionHandlers: [String: () -> Void] = [:]

    lazy var appContainer = AppContainer { [weak self] identifier in
        await self?.finishBackgroundSessionEvents(identifier: identifier)
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        backgroundSessionCompletionHandlers[identifier] = completionHandler
        // システムからのバックグラウンド起動でも、同じidentifierのURLSessionを再生成する。
        _ = appContainer
    }

    private func finishBackgroundSessionEvents(identifier: String) {
        guard let completionHandler = backgroundSessionCompletionHandlers.removeValue(
            forKey: identifier
        ) else {
            return
        }
        completionHandler()
    }
}

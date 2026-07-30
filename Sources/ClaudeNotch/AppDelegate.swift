import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var demoMode = false
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController()
        if demoMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.controller?.triggerTestAlert()
            }
        }
    }
}

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
delegate.demoMode = CommandLine.arguments.contains("--demo")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

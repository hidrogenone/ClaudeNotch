import AppKit
import ServiceManagement

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = StatusMonitor()
    private let notch = NotchAlertController()
    private let flasher = EdgeFlasher()
    private let hover = HoverStatusController()
    private let updates = UpdateChecker()
    private let menu = NSMenu()

    private var currentAlert: AlertInfo?
    private var testAlertActive = false

    override init() {
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateIcon(alert: nil)

        notch.onUserDismiss = { [weak self] in
            self?.flasher.stop()
            self?.hover.suppressed = false
        }

        monitor.onUpdate = { [weak self] summary, alert in
            guard let self else { return }
            self.hover.update(summary: summary)
            guard !self.testAlertActive else { return }
            self.apply(alert: alert)
        }
        monitor.start()
        updates.start()

        if !Settings.shared.didShowIntro {
            Settings.shared.didShowIntro = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.hover.showIntro()
            }
        }
    }

    private func apply(alert: AlertInfo?) {
        currentAlert = alert
        updateIcon(alert: alert)
        if let alert {
            // Presenting: keep the icon red but hold the drop-down and flash
            // until the next poll finds the screen private again.
            if QuietMode.isActive {
                flasher.stop()
                hover.suppressed = false
                return
            }
            let showing = notch.present(alert)
            hover.suppressed = showing
            if showing && Settings.shared.edgeFlashEnabled {
                flasher.start()
            } else if !showing {
                flasher.stop()
            }
        } else {
            notch.clear()
            flasher.stop()
            hover.suppressed = false
        }
    }

    private func updateIcon(alert: AlertInfo?) {
        guard let button = statusItem.button else { return }
        if alert == nil {
            let image = NSImage(systemSymbolName: "checkmark.seal", accessibilityDescription: "ClaudeNotch: all systems operational")
            image?.isTemplate = true
            button.image = image
        } else if let alert {
            // Minor trouble is a caution, not an emergency — amber vs red.
            let color: NSColor = impactRank(alert.impact) >= 2 ? .systemRed : .systemYellow
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "ClaudeNotch: incident active")?
                .withSymbolConfiguration(config)
            image?.isTemplate = false
            button.image = image
        }
        button.toolTip = alert?.title ?? "ClaudeNotch — Claude status: operational"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusText: String
        if let alert = currentAlert {
            statusText = "⚠️ \(alert.title)"
        } else if let summary = monitor.lastSummary {
            statusText = "✅ \(summary.status.description)"
        } else {
            statusText = "Fetching status…"
        }
        let header = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Monitored components ("models") submenu
        let componentsMenu = NSMenu()
        componentsMenu.autoenablesItems = false
        let components = monitor.lastSummary?.components ?? []
        if components.isEmpty {
            let placeholder = NSMenuItem(title: "Waiting for first fetch…", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            componentsMenu.addItem(placeholder)
        } else {
            for component in components {
                let title = component.status == "operational"
                    ? component.name
                    : "\(component.name) — \(humanComponentStatus(component.status))"
                let item = NSMenuItem(title: title, action: #selector(toggleComponent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = component.id
                item.state = Settings.shared.isMonitored(component.id) ? .on : .off
                componentsMenu.addItem(item)
            }
        }
        let componentsItem = NSMenuItem(title: "Monitored Components", action: nil, keyEquivalent: "")
        menu.addItem(componentsItem)
        menu.setSubmenu(componentsMenu, for: componentsItem)

        // Poll interval submenu
        let intervalMenu = NSMenu()
        intervalMenu.autoenablesItems = false
        let intervals: [(String, TimeInterval)] = [
            ("Every 30 seconds", 30),
            ("Every minute", 60),
            ("Every 2 minutes", 120),
            ("Every 5 minutes", 300),
        ]
        for (label, seconds) in intervals {
            let item = NSMenuItem(title: label, action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = Settings.shared.pollInterval == seconds ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Check Interval", action: nil, keyEquivalent: "")
        menu.addItem(intervalItem)
        menu.setSubmenu(intervalMenu, for: intervalItem)

        // Edge flash toggle
        let flashItem = NSMenuItem(title: "Flash Screen Edges on Incident", action: #selector(toggleEdgeFlash), keyEquivalent: "")
        flashItem.target = self
        flashItem.state = Settings.shared.edgeFlashEnabled ? .on : .off
        menu.addItem(flashItem)

        // Quiet-while-presenting toggle
        let quietItem = NSMenuItem(title: "Quiet While Screen Is Shared", action: #selector(toggleQuiet), keyEquivalent: "")
        quietItem.target = self
        quietItem.state = Settings.shared.quietWhenPresenting ? .on : .off
        menu.addItem(quietItem)

        menu.addItem(.separator())

        if let version = updates.availableVersion {
            let updateItem = NSMenuItem(title: "⬆ Update Available (v\(version))…", action: #selector(openLatestRelease), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        let testItem = NSMenuItem(title: "Test Alert", action: #selector(testAlert), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        let openItem = NSMenuItem(title: "Open status.claude.com", action: #selector(openStatusPage), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        if Bundle.main.bundleURL.pathExtension == "app" {
            let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            loginItem.target = self
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(loginItem)
        }

        let quitItem = NSMenuItem(title: "Quit ClaudeNotch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleComponent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Settings.shared.toggleMonitored(id)
        monitor.reevaluate()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        Settings.shared.pollInterval = seconds
        monitor.reschedule()
    }

    @objc private func toggleEdgeFlash() {
        Settings.shared.edgeFlashEnabled.toggle()
        if !Settings.shared.edgeFlashEnabled {
            flasher.stop()
        } else if currentAlert != nil {
            flasher.start()
        }
    }

    @objc private func toggleQuiet() {
        Settings.shared.quietWhenPresenting.toggle()
    }

    @objc private func openLatestRelease() {
        NSWorkspace.shared.open(UpdateChecker.latestReleaseURL)
    }

    @objc private func testAlert() {
        triggerTestAlert()
    }

    func triggerTestAlert() {
        testAlertActive = true
        hover.suppressed = true
        let fake = AlertInfo(
            title: "Elevated errors across many models",
            detail: "claude.ai · Claude API · Claude Code",
            impact: "major",
            url: StatusMonitor.statusPageURL
        )
        currentAlert = fake
        updateIcon(alert: fake)
        notch.present(fake)
        if Settings.shared.edgeFlashEnabled {
            flasher.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            self.testAlertActive = false
            self.hover.suppressed = false
            self.notch.clear()
            self.flasher.stop()
            self.monitor.reevaluate()
        }
    }

    @objc private func openStatusPage() {
        NSWorkspace.shared.open(StatusMonitor.statusPageURL)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ClaudeNotch: launch-at-login toggle failed: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

import AppKit
import SwiftUI

// MARK: - View model

final class HoverStatusModel: ObservableObject {
    @Published var summary: StatusSummary?
    @Published var visible = false
    @Published var topInset: CGFloat = 32
    @Published var lastUpdated: Date?
    /// Fires the celebration burst the first time the panel opens.
    @Published var confetti = false
    /// Measured round-trip to the Claude API; nil while unmeasured or failed.
    @Published var apiPingMs: Int?
    @Published var pingFailed = false
    var onOpen: (() -> Void)?
}

// MARK: - Controller

/// Shows a live status panel when the mouse hovers over the notch,
/// so you can check on Claude any time — not just during incidents.
final class HoverStatusController {
    static let panelWidth: CGFloat = 430
    // Tall enough that the card's rounded bottom never gets clipped, even
    // with the intro banner and an incident line on screen at once.
    static let panelHeight: CGFloat = 460

    /// True while the incident alert panel is down (hover would just duplicate it).
    var suppressed = false {
        didSet { if suppressed { forceHide() } }
    }

    private let model = HoverStatusModel()
    private var panel: NotchPanel?
    private var tickTimer: Timer?
    private var dwellStart: Date?

    // First-run tutorial: a floating badge under the notch that stays put
    // until the user actually hovers the notch, then celebrates with confetti.
    private var hintPanel: NotchPanel?
    private let hintModel = HintBadgeModel()
    private var tutorialActive = false
    /// Completion only counts after the cursor has been seen OUTSIDE the hot
    /// zone once — otherwise a cursor already parked under the notch (or an
    /// accidental brush at launch) finishes the tutorial instantly.
    private var tutorialArmed = false

    private var clickMonitor: Any?

    init() {
        model.onOpen = {
            NSWorkspace.shared.open(StatusMonitor.statusPageURL)
        }
        // Lightweight pointer polling: no accessibility permission needed,
        // no invisible window stealing clicks from the menu bar.
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        // Clicking the notch opens the panel instantly — the gesture people
        // try first, before they discover hovering.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self, !self.suppressed, !self.model.visible else { return }
            let zone = Self.hotZone(on: NotchAlertController.targetScreen())
            guard zone.contains(NSEvent.mouseLocation) else { return }
            if self.tutorialActive { self.completeTutorial() }
            self.show()
        }
    }

    func update(summary: StatusSummary?) {
        guard let summary else { return }
        model.summary = summary
        model.lastUpdated = Date()
    }

    /// First-launch tutorial: float a hint badge right under the notch and
    /// leave it there until the user hovers the notch for real. Completing
    /// the gesture is rewarded with a confetti burst inside the panel.
    func showTutorial() {
        tutorialActive = true
        tutorialArmed = false
        ensureHintPanel()
        hintPanel?.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.hintModel.visible = true
        }
    }

    private func completeTutorial() {
        tutorialActive = false
        Settings.shared.didShowIntro = true
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            model.confetti = true
        }
        hintModel.visible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.hintPanel?.orderOut(nil)
            self?.hintPanel = nil
        }
    }

    private func ensureHintPanel() {
        if hintPanel != nil { return }
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let screen = NotchAlertController.targetScreen()
        hintModel.topInset = max(screen.safeAreaInsets.top, 8)
        panel.contentView = NSHostingView(rootView: HintBadgeView(model: hintModel))
        let frame = screen.frame
        panel.setFrame(
            NSRect(x: frame.midX - 210, y: frame.maxY - 150, width: 420, height: 150),
            display: true
        )
        hintPanel = panel
    }

    /// One cheap unauthenticated request to the API host, timed. A 401 still
    /// proves DNS + TLS + the service answering, which is what latency means here.
    private func pingAPI() {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 5
        let started = Date()
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            DispatchQueue.main.async {
                guard let self else { return }
                if response != nil {
                    self.model.apiPingMs = ms
                    self.model.pingFailed = false
                } else {
                    self.model.apiPingMs = nil
                    self.model.pingFailed = true
                }
            }
        }.resume()
    }

    func forceHide() {
        dwellStart = nil
        guard model.visible else { return }
        model.visible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel?.orderOut(nil)
        }
    }

    private func tick() {
        guard !suppressed else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NotchAlertController.targetScreen()
        let zone = Self.hotZone(on: screen)

        if tutorialActive {
            if !zone.contains(mouse) {
                tutorialArmed = true
            } else if tutorialArmed {
                completeTutorial()
            }
        }

        if model.visible {
            let keepAlive = zone.insetBy(dx: -30, dy: 0)
                .union(panelFrame(on: screen).insetBy(dx: -24, dy: -24))
            if !keepAlive.contains(mouse) {
                forceHide()
            }
        } else if zone.contains(mouse) {
            if let start = dwellStart {
                // Short dwell so brushing past the top edge doesn't trigger it.
                if Date().timeIntervalSince(start) >= 0.15 {
                    show()
                }
            } else {
                dwellStart = Date()
            }
        } else {
            dwellStart = nil
        }
    }

    private func show() {
        ensurePanel()
        pingAPI()
        panel?.orderFrontRegardless()
        // Heavy double burst: two waves of three .levelChange hits — the
        // strongest pattern macOS exposes, stacked so it reads as a loud
        // mechanical "THUNK-THUNK" you can't miss.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        for delay in [0.055, 0.11, 0.26, 0.315, 0.37] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.model.visible = true
        }
    }

    private func ensurePanel() {
        if panel != nil {
            reposition()
            return
        }
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HoverStatusView(model: model))
        self.panel = panel
        reposition()
    }

    private func reposition() {
        guard let panel else { return }
        let screen = NotchAlertController.targetScreen()
        model.topInset = max(screen.safeAreaInsets.top, 8)
        panel.setFrame(panelFrame(on: screen), display: true)
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        return NSRect(
            x: frame.midX - Self.panelWidth / 2,
            y: frame.maxY - Self.panelHeight,
            width: Self.panelWidth,
            height: Self.panelHeight
        )
    }

    /// The notch area — or the top-center strip of the menu bar on Macs without one.
    static func hotZone(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top
        let height = inset > 0 ? inset : 24
        let width: CGFloat = inset > 0 ? 230 : 280
        return NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }
}

// MARK: - Tutorial badge

final class HintBadgeModel: ObservableObject {
    @Published var visible = false
    @Published var topInset: CGFloat = 32
}

/// Rounded pill floating just under the notch, gently bobbing, pointing up.
/// It never leaves until the user actually hovers the notch.
struct HintBadgeView: View {
    @ObservedObject var model: HintBadgeModel
    @State private var floating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: model.topInset + 16)
            HStack(spacing: 9) {
                Text("👆")
                    .font(.system(size: 15))
                    .offset(y: floating ? -2 : 1)
                Text("Hover the notch any time to check on Claude")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            colors: [Color.black, Color(white: 0.09)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.cyan.opacity(0.75), lineWidth: 1.2)
                    )
                    .shadow(color: .cyan.opacity(0.4), radius: 14, y: 4)
            )
            .offset(y: floating ? 7 : 0)
            .scaleEffect(model.visible ? 1 : 0.5, anchor: .top)
            .opacity(model.visible ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.6), value: model.visible)
            Spacer(minLength: 0)
        }
        .frame(width: 420, height: 150, alignment: .top)
        .onAppear {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

// MARK: - SwiftUI content

struct HoverStatusView: View {
    @ObservedObject var model: HoverStatusModel

    private var components: [StatusSummary.Component] { model.summary?.components ?? [] }

    private var hasIssues: Bool {
        components.contains { $0.status != "operational" }
            || !(model.summary?.incidents.isEmpty ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            card
                .offset(y: model.visible ? 0 : -(HoverStatusController.panelHeight + 60))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.visible)
            Spacer(minLength: 0)
        }
        .frame(
            width: HoverStatusController.panelWidth,
            height: HoverStatusController.panelHeight,
            alignment: .top
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: hasIssues ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(hasIssues ? Color.red : Color.green)
                Text(model.summary?.status.description ?? "Fetching status…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            if let incident = model.summary?.incidents.first {
                Text(incident.name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            ForEach(components, id: \.id) { component in
                HStack(spacing: 8) {
                    StatusDot(
                        color: Self.color(for: component.status),
                        troubled: component.status != "operational"
                    )
                    Text(component.name)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(Settings.shared.isMonitored(component.id) ? 0.9 : 0.4))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(humanComponentStatus(component.status))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Self.color(for: component.status).opacity(0.9))
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(pingColor)
                    .frame(width: 8, height: 8)
                Text("Claude API round-trip")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                Text(pingText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(pingColor.opacity(0.9))
                    .contentTransition(.numericText())
            }

            Text(footerText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, model.topInset + 10)
        .padding(.bottom, 16)
        .frame(width: HoverStatusController.panelWidth)
        .background(
            BottomRoundedRect(radius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color.black, Color(white: 0.07)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    BottomRoundedRect(radius: 24)
                        .stroke(
                            hasIssues ? Color.red.opacity(0.7) : Color.white.opacity(0.16),
                            lineWidth: 1.0
                        )
                )
                .shadow(
                    color: hasIssues ? Color.red.opacity(0.4) : Color.black.opacity(0.55),
                    radius: 20,
                    y: 8
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { model.onOpen?() }
        .pressable()
        .overlay(alignment: .top) {
            if model.confetti && model.visible {
                ConfettiBurst()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                            model.confetti = false
                        }
                    }
            }
        }
    }

    private var pingText: String {
        if model.pingFailed { return "unreachable" }
        guard let ms = model.apiPingMs else { return "measuring…" }
        return "\(ms) ms"
    }

    private var pingColor: Color {
        if model.pingFailed { return .red }
        guard let ms = model.apiPingMs else { return .gray }
        if ms < 400 { return .green }
        if ms < 1000 { return .yellow }
        return .orange
    }

    private var footerText: String {
        guard let updated = model.lastUpdated else { return "Waiting for first fetch…" }
        let seconds = max(0, Int(Date().timeIntervalSince(updated)))
        return "Updated \(seconds)s ago · Click to open status.claude.com"
    }

    /// Confetti burst from the top of the card — a small reward the first
    /// time someone completes the hover-the-notch tutorial.
    struct ConfettiBurst: View {
        struct Piece {
            let x: CGFloat
            let fall: CGFloat
            let size: CGFloat
            let spin: Double
            let delay: Double
            let duration: Double
            let color: Color

            static let palette: [Color] = [.red, .orange, .yellow, .green, .cyan, .pink, .purple]

            static func random() -> Piece {
                Piece(
                    x: .random(in: -180...180),
                    fall: .random(in: 150...330),
                    size: .random(in: 5...10),
                    spin: .random(in: -720...720),
                    delay: .random(in: 0...0.25),
                    duration: .random(in: 1.0...1.8),
                    color: palette.randomElement()!
                )
            }
        }

        private let pieces = (0..<28).map { _ in Piece.random() }
        @State private var fly = false

        var body: some View {
            ZStack {
                ForEach(pieces.indices, id: \.self) { i in
                    let p = pieces[i]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 0.62)
                        .rotationEffect(.degrees(fly ? p.spin : 0))
                        .offset(x: fly ? p.x : 0, y: fly ? p.fall : -6)
                        .opacity(fly ? 0 : 1)
                        .animation(.easeOut(duration: p.duration).delay(p.delay), value: fly)
                }
            }
            .allowsHitTesting(false)
            .onAppear { fly = true }
        }
    }

    /// Component dot; troubled ones emit a slow ripple so problems catch the eye.
    struct StatusDot: View {
        let color: Color
        let troubled: Bool
        @State private var ripple = false

        var body: some View {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay {
                    if troubled {
                        Circle()
                            .stroke(color.opacity(0.6), lineWidth: 1.5)
                            .scaleEffect(ripple ? 2.4 : 1.0)
                            .opacity(ripple ? 0 : 0.8)
                    }
                }
                .onAppear {
                    guard troubled,
                          !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                        ripple = true
                    }
                }
        }
    }

    static func color(for status: String) -> Color {
        switch status {
        case "operational": return .green
        case "degraded_performance": return .yellow
        case "partial_outage": return .orange
        case "major_outage": return .red
        case "under_maintenance": return .blue
        default: return .gray
        }
    }
}

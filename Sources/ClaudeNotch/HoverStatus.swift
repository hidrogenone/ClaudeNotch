import AppKit
import SwiftUI

// MARK: - View model

final class HoverStatusModel: ObservableObject {
    @Published var summary: StatusSummary?
    @Published var visible = false
    @Published var topInset: CGFloat = 32
    @Published var lastUpdated: Date?
    var onOpen: (() -> Void)?
}

// MARK: - Controller

/// Shows a live status panel when the mouse hovers over the notch,
/// so you can check on Claude any time — not just during incidents.
final class HoverStatusController {
    static let panelWidth: CGFloat = 430
    static let panelHeight: CGFloat = 330

    /// True while the incident alert panel is down (hover would just duplicate it).
    var suppressed = false {
        didSet { if suppressed { forceHide() } }
    }

    private let model = HoverStatusModel()
    private var panel: NotchPanel?
    private var tickTimer: Timer?
    private var dwellStart: Date?

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
    }

    func update(summary: StatusSummary?) {
        guard let summary else { return }
        model.summary = summary
        model.lastUpdated = Date()
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
        panel?.orderFrontRegardless()
        // Soft trackpad tick so opening the panel feels anchored to the notch.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
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
            BottomRoundedRect(radius: 22)
                .fill(Color.black)
                .overlay(
                    BottomRoundedRect(radius: 22)
                        .stroke(
                            hasIssues ? Color.red.opacity(0.7) : Color.white.opacity(0.18),
                            lineWidth: 1.5
                        )
                )
                .shadow(
                    color: hasIssues ? Color.red.opacity(0.4) : Color.black.opacity(0.5),
                    radius: 18,
                    y: 6
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { model.onOpen?() }
        .pressable()
    }

    private var footerText: String {
        guard let updated = model.lastUpdated else { return "Waiting for first fetch…" }
        let seconds = max(0, Int(Date().timeIntervalSince(updated)))
        return "Updated \(seconds)s ago · Click to open status.claude.com"
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
                    guard troubled else { return }
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

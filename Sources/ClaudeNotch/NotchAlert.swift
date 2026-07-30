import AppKit
import SwiftUI

// MARK: - View model

final class NotchViewModel: ObservableObject {
    @Published var alert: AlertInfo?
    @Published var visible = false
    @Published var topInset: CGFloat = 32
    var onDismiss: (() -> Void)?
    var onOpen: (() -> Void)?
}

// MARK: - Panel

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class NotchAlertController {
    static let panelWidth: CGFloat = 600
    static let panelHeight: CGFloat = 170

    /// Called when the user explicitly dismisses the alert (so the edge flash can stop too).
    var onUserDismiss: (() -> Void)?

    private var panel: NotchPanel?
    private let model = NotchViewModel()
    private var currentAlert: AlertInfo?
    private var dismissedAlertKey: String?

    init() {
        model.onDismiss = { [weak self] in self?.userDismiss() }
        model.onOpen = { [weak self] in
            guard let self else { return }
            if let url = self.currentAlert?.url {
                NSWorkspace.shared.open(url)
            }
            self.userDismiss()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
    }

    /// Shows the alert unless the user already dismissed this exact one.
    /// Returns true when the alert is on screen after the call.
    @discardableResult
    func present(_ alert: AlertInfo) -> Bool {
        if dismissedAlertKey == alert.key { return false }
        if currentAlert == alert, model.visible { return true }
        currentAlert = alert
        ensurePanel()
        model.alert = alert
        panel?.orderFrontRegardless()
        // Let the panel draw once in the hidden position before springing down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.model.visible = true
        }
        return true
    }

    /// The incident is over: retract and forget any dismissal.
    func clear() {
        currentAlert = nil
        dismissedAlertKey = nil
        retract()
    }

    private func userDismiss() {
        dismissedAlertKey = currentAlert?.key
        retract()
        onUserDismiss?()
    }

    private func retract() {
        guard model.visible else {
            panel?.orderOut(nil)
            return
        }
        model.visible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel?.orderOut(nil)
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
        panel.contentView = NSHostingView(rootView: NotchView(model: model))
        self.panel = panel
        reposition()
    }

    private func reposition() {
        guard let panel else { return }
        let screen = Self.targetScreen()
        model.topInset = max(screen.safeAreaInsets.top, 8)
        let frame = screen.frame
        let rect = NSRect(
            x: frame.midX - Self.panelWidth / 2,
            y: frame.maxY - Self.panelHeight,
            width: Self.panelWidth,
            height: Self.panelHeight
        )
        panel.setFrame(rect, display: true)
    }

    /// Prefer the screen that actually has a notch.
    static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

// MARK: - SwiftUI content

struct NotchView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            card
                .offset(y: model.visible ? 0 : -(NotchAlertController.panelHeight + 60))
                .animation(.spring(response: 0.55, dampingFraction: 0.8), value: model.visible)
            Spacer(minLength: 0)
        }
        .frame(width: NotchAlertController.panelWidth, height: NotchAlertController.panelHeight, alignment: .top)
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.red)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.alert?.title ?? "")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(model.alert?.detail ?? "")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
                Text("Click for details")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer(minLength: 8)

            Button(action: { model.onDismiss?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, model.topInset + 12)
        .padding(.bottom, 18)
        .frame(width: NotchAlertController.panelWidth)
        .background(
            BottomRoundedRect(radius: 24)
                .fill(Color.black)
                .overlay(
                    BottomRoundedRect(radius: 24)
                        .stroke(Color.red.opacity(0.75), lineWidth: 1.5)
                )
                .shadow(color: .red.opacity(0.45), radius: 20, y: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.onOpen?() }
    }
}

/// Rectangle rounded only at the bottom corners, so the panel looks like
/// the notch itself sliding down out of the bezel.
struct BottomRoundedRect: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

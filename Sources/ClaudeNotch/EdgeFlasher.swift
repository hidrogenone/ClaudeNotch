import AppKit
import SwiftUI

/// Pulsing red border drawn over the edges of every screen while an alert is active.
final class EdgeFlasher {
    private var windows: [NSWindow] = []

    var isActive: Bool { !windows.isEmpty }

    func start() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(rootView: EdgePulseView(notch: Self.notchCutout(on: screen)))
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func stop() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    /// Notch cutout in view coordinates (top-left origin), slightly padded so
    /// the glow hugs the outside of the camera housing instead of vanishing
    /// behind it. Nil on screens without a notch.
    private static func notchCutout(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return CGRect(
            x: left.maxX - screen.frame.minX - 2,
            y: 0,
            width: width + 4,
            height: screen.safeAreaInsets.top + 2
        )
    }
}

struct EdgePulseView: View {
    var notch: CGRect?
    @State private var pulse = false

    var body: some View {
        NotchBorderShape(notch: notch)
            .stroke(
                LinearGradient(
                    colors: [Color.red, Color(red: 1.0, green: 0.25, blue: 0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: StrokeStyle(lineWidth: 16, lineJoin: .round)
            )
            .blur(radius: 10)
            .opacity(pulse ? 0.9 : 0.12)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Screen border that detours around the notch, so the flash surrounds the
/// camera housing instead of running underneath it.
struct NotchBorderShape: Shape {
    var notch: CGRect?
    /// Half the stroke width — keeps the centered stroke inside the screen,
    /// matching the old strokeBorder look on straight edges.
    var inset: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: inset, dy: inset)
        guard let n = notch, n.width > 0,
              n.minX > r.minX + 20, n.maxX < r.maxX - 20 else {
            p.addRect(r)
            return p
        }
        let c: CGFloat = 9
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: n.minX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: n.minX, y: r.minY + c), control: CGPoint(x: n.minX, y: r.minY))
        p.addLine(to: CGPoint(x: n.minX, y: n.maxY - c))
        p.addQuadCurve(to: CGPoint(x: n.minX + c, y: n.maxY), control: CGPoint(x: n.minX, y: n.maxY))
        p.addLine(to: CGPoint(x: n.maxX - c, y: n.maxY))
        p.addQuadCurve(to: CGPoint(x: n.maxX, y: n.maxY - c), control: CGPoint(x: n.maxX, y: n.maxY))
        p.addLine(to: CGPoint(x: n.maxX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: n.maxX + c, y: r.minY), control: CGPoint(x: n.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

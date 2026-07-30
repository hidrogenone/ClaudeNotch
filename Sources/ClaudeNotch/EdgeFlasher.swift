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
            window.contentView = NSHostingView(rootView: EdgePulseView())
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func stop() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

struct EdgePulseView: View {
    @State private var pulse = false

    var body: some View {
        Rectangle()
            .strokeBorder(
                LinearGradient(
                    colors: [Color.red, Color(red: 1.0, green: 0.25, blue: 0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 16
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

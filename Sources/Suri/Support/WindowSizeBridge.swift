import AppKit
import SwiftUI

struct WindowSizeBridge: NSViewRepresentable {
    let minimumSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.minSize = minimumSize

        let currentFrame = window.frame
        let targetWidth = max(currentFrame.width, minimumSize.width)
        let targetHeight = max(currentFrame.height, minimumSize.height)
        guard targetWidth != currentFrame.width || targetHeight != currentFrame.height else {
            return
        }

        var targetFrame = currentFrame
        let maxY = currentFrame.maxY
        targetFrame.size = CGSize(width: targetWidth, height: targetHeight)
        targetFrame.origin.y = maxY - targetHeight

        if let visibleFrame = window.screen?.visibleFrame {
            targetFrame.origin.x = min(max(targetFrame.origin.x, visibleFrame.minX), visibleFrame.maxX - targetWidth)
            targetFrame.origin.y = min(max(targetFrame.origin.y, visibleFrame.minY), visibleFrame.maxY - targetHeight)
        }

        window.setFrame(targetFrame, display: true, animate: false)
    }
}

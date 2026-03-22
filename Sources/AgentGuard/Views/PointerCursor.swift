import SwiftUI
import AppKit

// Cursor-only view — passes all clicks through via hitTest returning nil.
// Uses resetCursorRects which is the proper AppKit way to set cursors.
struct PointerCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(PointerCursorRepresentable())
    }
}

private struct PointerCursorRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> PointerCursorView {
        PointerCursorView()
    }
    func updateNSView(_ nsView: PointerCursorView, context: Context) {}
}

private class PointerCursorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass all clicks through to the SwiftUI button underneath
        return nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

extension View {
    func pointerCursor() -> some View {
        modifier(PointerCursorModifier())
    }
}

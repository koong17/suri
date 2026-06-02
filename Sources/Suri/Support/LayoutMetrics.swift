import CoreGraphics

enum LayoutMetrics {
    static let minimumWindowSize = CGSize(width: 920, height: 600)
    static let defaultWindowSize = CGSize(width: 1_280, height: 800)

    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 300

    static let detailMinWidth: CGFloat = 340
    static let detailLeadingGutterWhenInspectorIsOpen: CGFloat = 16

    static let inspectorDefaultWidth = 340.0
    static let inspectorMinWidth = 280.0
    static let inspectorMaxWidth = 480.0
    static let inspectorResizeHandleWidth: CGFloat = 16
}

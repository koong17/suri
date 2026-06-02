import Foundation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case today
    case inbox
    case importantSlack
    case deadlines
    case followUps
    case sources
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "오늘"
        case .inbox:
            "확인할 일"
        case .importantSlack:
            "중요 Slack"
        case .deadlines:
            "임박한 기한"
        case .followUps:
            "후속 조치"
        case .sources:
            "연결된 소스"
        case .notes:
            "내 메모"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "sun.max"
        case .inbox:
            "tray"
        case .importantSlack:
            "exclamationmark.bubble"
        case .deadlines:
            "timer"
        case .followUps:
            "arrow.triangle.2.circlepath"
        case .sources:
            "point.3.connected.trianglepath.dotted"
        case .notes:
            "note.text"
        }
    }
}

struct SidebarSummary: Identifiable, Hashable {
    let item: SidebarItem
    let detail: String?

    var id: SidebarItem { item }
}

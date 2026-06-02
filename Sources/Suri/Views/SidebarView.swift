import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let summaries: [SidebarSummary]

    var body: some View {
        List(selection: $selection) {
            Section("업무") {
                ForEach(summaries.filter { workItems.contains($0.item) }) { summary in
                    SidebarRow(summary: summary)
                        .tag(summary.item as SidebarItem?)
                }
            }

            Section("소스") {
                ForEach(summaries.filter { sourceItems.contains($0.item) }) { summary in
                    SidebarRow(summary: summary)
                        .tag(summary.item as SidebarItem?)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: LayoutMetrics.sidebarMinWidth,
            ideal: LayoutMetrics.sidebarIdealWidth,
            max: LayoutMetrics.sidebarMaxWidth
        )
    }

    private var workItems: [SidebarItem] {
        [.today, .inbox, .importantSlack, .deadlines, .followUps]
    }

    private var sourceItems: [SidebarItem] {
        [.sources, .notes]
    }
}

private struct SidebarRow: View {
    let summary: SidebarSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.item.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.item.title)
                    .lineLimit(1)

                if let detail = summary.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

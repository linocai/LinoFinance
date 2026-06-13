import WidgetKit
import SwiftUI

// v2 widget extension — minimal placeholder bundle (P0 scaffolding only).
// Real liquid-glass widgets + App Group snapshot wiring land in Py.

@main
struct LinoFinanceV2WidgetsBundle: WidgetBundle {
    var body: some Widget {
        LinoFinanceV2PlaceholderWidget()
    }
}

struct LinoFinanceV2PlaceholderWidget: Widget {
    let kind = "LinoFinanceV2Placeholder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderProvider()) { _ in
            VStack(alignment: .leading) {
                Text("LinoFinance v2")
                    .font(.headline)
                Text("P0 占位")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("LinoFinance v2")
        .description("P0 占位 widget。")
        .supportedFamilies([.systemSmall])
    }
}

private struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

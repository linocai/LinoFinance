import Foundation
import WidgetKit

// V2WidgetSnapshot — Py ① App Group + ④ Widget.
//
// The app→widget data bridge. The v2 app writes a snapshot to the shared App
// Group UserDefaults after every `refreshAll()`; the v2 widget extension reads
// the same suite. This is a v2-local reimplementation of v1's
// `Core/WidgetSnapshot/WidgetSnapshotStore` — the struct *shape* and the App
// Group read/write mechanism are reused, but the writer reads v2's `AppModel`
// (DTOs) instead of v1's `AppEnvironment`/ViewModels.
//
// App Group id is `group.com.lino.linofinance.v2` (Py development id; Pz switches
// it back to `group.com.lino.linofinance` alongside the bundle id + aps env).
// The id lives in ONE constant (`V2WidgetSharing.appGroupID`) so the app side and
// the widget side reference the same string; the widget target — compiled
// separately — carries a verbatim copy of this constant + the struct (the plan
// sanctions "widget 内复制" for the separately-compiled extension).

enum V2WidgetSharing {
    static let appGroupID = "group.com.lino.linofinance.v2"
    static let snapshotKey = "linofinance.widget.snapshot"
}

/// Codable snapshot shared app→widget. Same shape as v1 so the widget views map
/// 1:1; ISO8601 dates so the app + widget JSON coders agree.
struct V2WidgetSnapshot: Codable, Equatable {
    struct CreditDue: Codable, Equatable {
        let accountName: String
        let dueDate: Date
        let amount: String
    }

    let netWorth: String
    let balance: String
    let creditLiability: String
    let thirtyDayNet: String
    let trend: [Double]
    let nextCreditDue: CreditDue?
    let pendingAIPlanCount: Int
    let updatedAt: Date
}

/// App-side writer. The widget extension has its own reader (it cannot link this
/// `WidgetCenter.reloadAllTimelines()` call path the same way, and keeps a verbatim
/// struct copy), so this type is app-only.
struct V2WidgetSnapshotStore {
    static let shared = V2WidgetSnapshotStore()

    private var defaults: UserDefaults {
        UserDefaults(suiteName: V2WidgetSharing.appGroupID) ?? .standard
    }

    func write(_ snapshot: V2WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: V2WidgetSharing.snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

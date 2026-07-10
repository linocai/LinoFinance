import SwiftUI

// Sidebar navigation model + the eight macOS destinations (HANDOFF §3 / §6).
//
// "记一笔" is NOT in this list — it is a separate prominent action button, not a
// nav row (plan §A / HANDOFF §2.6). Routing is not wired in P1; the showcase just
// toggles `selection` so the highlight bar can be seen.

enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case overview
    case accounts
    case cashFlow
    case ledger
    case reimbursements
    case cycles
    case reports
    case ai
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .accounts: "账户"
        case .cashFlow: "现金流"
        case .ledger: "流水"
        case .reimbursements: "报销"
        case .cycles: "周期"
        case .reports: "报表"
        case .ai: "AI"
        case .settings: "设置"
        }
    }

    /// SF Symbols per HANDOFF §6 (no emoji, no third-party glyphs).
    var systemImage: String {
        switch self {
        case .overview: "chart.pie"
        case .accounts: "creditcard"
        case .cashFlow: "arrow.left.arrow.right"
        case .ledger: "list.bullet"
        case .reimbursements: "arrow.uturn.left.circle"
        case .cycles: "arrow.triangle.2.circlepath"
        case .reports: "chart.bar"
        case .ai: "sparkles"
        case .settings: "gearshape"
        }
    }
}

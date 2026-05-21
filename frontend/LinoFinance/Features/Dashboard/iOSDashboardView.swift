#if os(iOS)
import SwiftUI

/// iOS Dashboard 整页重建 —— 对齐 HTML B 节：iPhone 26 mockup。
/// 自上而下 4 块：
///   1. Greeting Header（早上好 + 中文日期）
///   2. NetWorthHero（净资产 38pt + sparkline + 3 stats + 隐藏按钮）
///   3. TodayEntriesCard（今日记账列表）
///   4. AIMonthlyReportCard（AI 月报节选）
struct iOSDashboardView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greetingHeader

                if let summary = environment.dashboardViewModel.summary {
                    NetWorthHeroSection(
                        summary: summary,
                        future30Net: environment.reportsViewModel.bundle?.cashFlow.windows.first { $0.days == 30 }?.netCny,
                        dailyNet: environment.reportsViewModel.bundle?.cashFlow.dailyNetCny ?? []
                    )

                    TodayEntriesSection(
                        entries: todayEntries,
                        accounts: environment.accountsViewModel.accounts,
                        categories: environment.entriesViewModel.categories
                    )

                    if let memo = environment.aiMemoViewModel.memos.first {
                        AIMonthlyReportCard(
                            title: "AI 月报 · \(monthChinese(from: memo.periodStart))（节选）",
                            excerpt: excerpt(of: memo.summary),
                            expandAction: { environment.selectedModule = .aiMemo },
                            exportAction: { Task { /* hooked to export pipeline later */ } }
                        )
                    } else {
                        AIMonthlyReportCard(
                            title: "AI 月报 · 待生成",
                            excerpt: "下次月报生成后会在这里展示节选 + 一键导出。也可去 AI 工作台手动让模型生成。",
                            expandAction: { environment.selectedModule = .ai }
                        )
                    }
                } else if environment.dashboardViewModel.isLoading {
                    EmptyState(title: "正在加载总览数据", message: "请稍候。", systemImage: "network")
                        .padding(.top, 40)
                } else {
                    EmptyState(
                        title: "连接不到 API",
                        message: "请确认后端服务已启动，或检查域名 / API Token 配置。",
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "重试",
                        action: { Task { await environment.refreshPrimaryData() } }
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .moduleFrame()
        .task {
            try? await environment.dashboardViewModel.refresh()
            try? await environment.reportsViewModel.refresh()
            try? await environment.aiViewModel.refresh()
            try? await environment.aiMemoViewModel.refresh()
            try? await environment.accountsViewModel.refresh()
            try? await environment.entriesViewModel.refresh()
        }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greetingPhrase)，Lino")
                .font(.system(size: 26, weight: .semibold))
                .titleTracking()
                .foregroundStyle(FinanceTokens.Text.primary)
            Text(todayChinese)
                .font(.system(size: 13))
                .foregroundStyle(FinanceTokens.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 按当前小时切换问候语。
    /// 5-11 早上好 · 11-13 中午好 · 13-18 下午好 · 18-23 晚上好 · 其余 夜深了。
    private var greetingPhrase: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    private var todayEntries: [EntryDTO] {
        environment.entriesViewModel.entries
            .filter { Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var todayChinese: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日 · EEEE"
        return f.string(from: Date())
    }

    private func monthChinese(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月"
        return f.string(from: date)
    }

    private func excerpt(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxChars = 140
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars)) + "…"
    }
}

// MARK: - Hero

private struct NetWorthHeroSection: View {
    let summary: DashboardSummaryDTO
    let future30Net: DecimalValue?
    let dailyNet: [CashFlowDailyNetRowDTO]

    private var trendValues: [Double] {
        dailyNet.map { NSDecimalNumber(decimal: $0.netCny.value).doubleValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("净资产")
                        .font(FinanceTypography.sectionKicker)
                        .kickerTracking()
                        .foregroundStyle(FinanceTokens.Text.secondary)
                    PrivacyAmount(
                        value: FinanceFormatter.money(summary.netWorthCny),
                        font: FinanceTypography.heroNumber,
                        tint: FinanceTokens.Text.primary
                    )
                    StatusTag(title: trendLabel, style: trendStyle)
                }
                Spacer(minLength: 12)
                HideAmountButton()
            }

            if !trendValues.isEmpty {
                SparklineCanvasView(values: trendValues, tint: FinanceTokens.Brand.primary)
                    .frame(height: 56)
            }

            statsRow
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(strength: .strong, elevation: .soft)
    }

    private var trendLabel: String {
        let delta = trendValues.last ?? 0
        let formatted = String(format: "¥%.0f", abs(delta))
        let arrow = delta >= 0 ? "▲" : "▼"
        return "\(arrow) \(formatted) · 30 天净额"
    }

    private var trendStyle: StatusTag.Style {
        (trendValues.last ?? 0) >= 0 ? .income : .expense
    }

    @ViewBuilder
    private var statsRow: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            statTile(title: "余额合计", value: FinanceFormatter.money(summary.balanceTotalCny), tint: FinanceTokens.State.income)
            statTile(title: "信用负债", value: FinanceFormatter.money(summary.creditLiabilityTotalCny), tint: FinanceTokens.State.credit)
            statTile(
                title: future30Net == nil ? "30 天净额" : "未来 30 天",
                value: future30Net.map { FinanceFormatter.money($0) } ?? "暂无",
                tint: (future30Net?.value ?? 0) < 0 ? FinanceTokens.State.expense : FinanceTokens.State.income
            )
        }
    }

    private func statTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(FinanceTokens.Text.secondary)
            PrivacyAmount(
                value: value,
                font: .system(size: 13, weight: .semibold).monospacedDigit(),
                tint: tint
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FinanceTokens.Radius.md, style: .continuous)
                .fill(FinanceTokens.Surface.glass)
                .overlay {
                    RoundedRectangle(cornerRadius: FinanceTokens.Radius.md, style: .continuous)
                        .stroke(FinanceTokens.Stroke.hairline, lineWidth: 0.5)
                }
        )
    }
}

// MARK: - Today's entries

private struct TodayEntriesSection: View {
    let entries: [EntryDTO]
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("今日 · \(entries.count) 条")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FinanceTokens.Text.primary)
                Spacer()
                if !entries.isEmpty {
                    StatusTag(title: "AI 已自动分类", style: .ai)
                }
            }

            if entries.isEmpty {
                Text("今日还没有记录。点底部 + 一句话记账。")
                    .font(.system(size: 12))
                    .foregroundStyle(FinanceTokens.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().background(FinanceTokens.Stroke.soft)
                        }
                        EntryRowAdapter(entry: entry, accounts: accounts, categories: categories)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(strength: .strong, elevation: .soft)
    }
}

private struct EntryRowAdapter: View {
    let entry: EntryDTO
    let accounts: [AccountDTO]
    let categories: [CategoryDTO]

    private var primaryLine: EntryCategoryLineDTO? { entry.categoryLines.first }
    private var primaryMovement: AccountMovementDTO? { entry.accountMovements.first }

    private var category: CategoryDTO? {
        guard let id = primaryLine?.categoryId else { return nil }
        return categories.first(where: { $0.id == id })
    }

    private var account: AccountDTO? {
        guard let id = primaryMovement?.accountId else { return nil }
        return accounts.first(where: { $0.id == id })
    }

    private var iconSymbol: String {
        switch category?.type {
        case .income: return "arrow.down.left.circle"
        case .expense: return "arrow.up.right.circle"
        default: return entry.status == .confirmed ? "checkmark.circle" : "circle.dotted"
        }
    }

    private var iconTint: Color {
        switch category?.type {
        case .income: return FinanceTokens.State.income
        case .expense:
            return account?.type == .credit ? FinanceTokens.State.credit : FinanceTokens.State.expense
        default: return FinanceTokens.State.pending
        }
    }

    private var amountTint: Color { iconTint }

    private var amountPrefix: String {
        switch category?.type {
        case .income: return "+"
        case .expense: return "-"
        default: return ""
        }
    }

    var body: some View {
        let primaryAmount: String = primaryLine.map { line in
            amountPrefix + FinanceFormatter.money(line.amount, currency: line.currency)
        } ?? "—"
        let subtitle: String = "\((account?.name).map { "\($0) · " } ?? "")\(category?.name ?? "未分类") · \(timeShort(entry.date))"
        let statusText = entry.status == .confirmed ? "已确认" : entry.status.title

        AccountListRow(
            systemImage: iconSymbol,
            iconTint: iconTint,
            title: entry.title,
            subtitle: subtitle,
            amountPrimary: primaryAmount,
            amountSecondary: statusText,
            amountTint: amountTint
        )
    }

    private func timeShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
#endif

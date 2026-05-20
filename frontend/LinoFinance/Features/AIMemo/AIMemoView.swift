import SwiftUI

#if os(iOS)
import UIKit
#endif

struct AIMemoView: View {
    @Bindable var environment: AppEnvironment
    @State private var periodChoice: AIMemoPeriodChoice = .currentMonth
    @State private var customStart = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1)) ?? Date()
    @State private var customEnd = Date()
    @State private var selectedTone: AIMemoTone = .professional

    private var viewModel: AIMemoViewModel { environment.aiMemoViewModel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "AI 月报", subtitle: "可编辑、可换语气、可导出的月度财务故事")
                generationPanel
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error)
                }
                if let path = viewModel.lastExportPath {
                    DetailLine(title: "最近导出", value: path)
                }
                contentGrid
            }
            .padding(FinanceTokens.Spacing.page)
        }
        .moduleFrame()
        .task {
            try? await viewModel.refresh()
        }
    }

    private var generationPanel: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        periodControls
                        tonePicker
                        generateButton
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        periodControls
                        tonePicker
                        generateButton
                    }
                }
                if periodChoice == .custom {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            DatePicker("开始", selection: $customStart, displayedComponents: .date)
                            DatePicker("结束", selection: $customEnd, displayedComponents: .date)
                        }
                        VStack(alignment: .leading) {
                            DatePicker("开始", selection: $customStart, displayedComponents: .date)
                            DatePicker("结束", selection: $customEnd, displayedComponents: .date)
                        }
                    }
                }
            }
        }
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("周期")
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
            Picker("周期", selection: $periodChoice) {
                ForEach(AIMemoPeriodChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 240)
        }
    }

    private var tonePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("语气")
                .font(FinanceTypography.caption)
                .foregroundStyle(FinanceTokens.Text.secondary)
            Picker("语气", selection: $selectedTone) {
                ForEach(AIMemoTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 260)
        }
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            Label(viewModel.selectedMemo == nil ? "生成月报" : "重新生成", systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isLoading)
    }

    private var contentGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                memoList
                    .frame(width: 320)
                editor
            }
            VStack(alignment: .leading, spacing: 16) {
                memoList
                editor
            }
        }
    }

    private var memoList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("备忘录")
                .font(FinanceTypography.headline)
            if viewModel.isLoading && viewModel.memos.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if viewModel.memos.isEmpty {
                EmptyState(title: "暂无月报", message: "选择周期后生成第一篇 AI 财务故事。", systemImage: "doc.text.magnifyingglass")
            } else {
                ForEach(viewModel.memos) { memo in
                    AIMemoCard(
                        memo: memo,
                        isSelected: memo.id == viewModel.selectedMemo?.id
                    ) {
                        viewModel.select(memo)
                    }
                }
            }
        }
    }

    private var editor: some View {
        FinancePanel {
            VStack(alignment: .leading, spacing: 14) {
                if let memo = viewModel.selectedMemo {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(memo.periodTitle)
                                .font(FinanceTypography.headline)
                            HStack {
                                StatusTag(status: memo.status)
                                Text("更新 \(FinanceFormatter.mediumDate(memo.updatedAt))")
                                    .font(FinanceTypography.caption)
                                    .foregroundStyle(FinanceTokens.Text.secondary)
                            }
                        }
                        Spacer()
                        Toggle("预览", isOn: previewBinding)
                            .toggleStyle(.switch)
                    }
                    memoStats(memo)
                    if viewModel.isPreviewing {
                        markdownPreview(viewModel.draftSummary)
                    } else {
                        TextEditor(text: summaryBinding)
                            .font(.body)
                            .frame(minHeight: 320)
                            .scrollContentBackground(.hidden)
                            .background(FinanceTokens.Surface.raised)
                            .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.md))
                    }
                    editorActions(memo)
                } else {
                    EmptyState(title: "选择或生成一篇月报", message: "月报会保存为 draft，可编辑后发布或导出 PDF。", systemImage: "sparkles")
                }
            }
        }
    }

    private func memoStats(_ memo: AIMemoDTO) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ToolbarPill(title: "收入", value: memo.overviewValue("income_cny"), tint: FinanceTokens.State.income)
                ToolbarPill(title: "支出", value: memo.overviewValue("expense_cny"), tint: FinanceTokens.State.expense)
                ToolbarPill(title: "净额", value: memo.overviewValue("net_income_cny"), tint: FinanceTokens.Brand.primary)
            }
            VStack(spacing: 10) {
                ToolbarPill(title: "收入", value: memo.overviewValue("income_cny"), tint: FinanceTokens.State.income)
                ToolbarPill(title: "支出", value: memo.overviewValue("expense_cny"), tint: FinanceTokens.State.expense)
                ToolbarPill(title: "净额", value: memo.overviewValue("net_income_cny"), tint: FinanceTokens.Brand.primary)
            }
        }
    }

    private func markdownPreview(_ text: String) -> some View {
        ScrollView {
            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 320)
        .padding(12)
        .background(FinanceTokens.Surface.raised)
        .clipShape(RoundedRectangle(cornerRadius: FinanceTokens.Radius.md))
    }

    private func editorActions(_ memo: AIMemoDTO) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Button("保存") {
                    Task { try? await viewModel.saveSelected() }
                }
                Button("发布") {
                    Task { try? await viewModel.saveSelected(status: "published") }
                }
                Button("归档", role: .destructive) {
                    Task { try? await viewModel.archiveSelected() }
                }
                Spacer()
                Menu("让 AI 改语气") {
                    ForEach(AIMemoTone.allCases) { tone in
                        Button(tone.title) {
                            Task { await regenerate(memo: memo, tone: tone) }
                        }
                    }
                }
                Button {
                    export(memo: memo)
                } label: {
                    Label("导出 PDF", systemImage: "square.and.arrow.down")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("保存") { Task { try? await viewModel.saveSelected() } }
                    Button("发布") { Task { try? await viewModel.saveSelected(status: "published") } }
                    Button("归档", role: .destructive) { Task { try? await viewModel.archiveSelected() } }
                }
                Menu("让 AI 改语气") {
                    ForEach(AIMemoTone.allCases) { tone in
                        Button(tone.title) { Task { await regenerate(memo: memo, tone: tone) } }
                    }
                }
                Button {
                    export(memo: memo)
                } label: {
                    Label("导出 PDF", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    private func generate() async {
        let range = periodChoice.range(customStart: customStart, customEnd: customEnd)
        try? await viewModel.generate(start: range.start, end: range.end, tone: selectedTone)
    }

    private func regenerate(memo: AIMemoDTO, tone: AIMemoTone) async {
        try? await viewModel.generate(start: memo.periodStart, end: memo.periodEnd, tone: tone, status: memo.status)
    }

    private func export(memo: AIMemoDTO) {
        do {
            let url = try MonthlyMemoPDFExporter.export(memo: memo, summary: viewModel.draftSummary)
            viewModel.markExported(url)
#if os(iOS)
            UIPrintInteractionController.shared.printingItem = url
            UIPrintInteractionController.shared.present(animated: true)
#endif
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var previewBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isPreviewing },
            set: { viewModel.isPreviewing = $0 }
        )
    }

    private var summaryBinding: Binding<String> {
        Binding(
            get: { viewModel.draftSummary },
            set: { viewModel.draftSummary = $0 }
        )
    }
}

private struct AIMemoCard: View {
    let memo: AIMemoDTO
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FinancePanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(memo.periodTitle)
                            .font(.headline)
                            .foregroundStyle(FinanceTokens.Text.primary)
                        Spacer()
                        StatusTag(status: memo.status)
                    }
                    Text(memo.summary)
                        .font(.caption)
                        .foregroundStyle(FinanceTokens.Text.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    DetailLine(title: "置信度", value: memo.confidence.value.formatted(.number.precision(.fractionLength(2))))
                    DetailLine(title: "更新", value: FinanceFormatter.mediumDate(memo.updatedAt))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: FinanceTokens.Radius.lg)
                    .stroke(isSelected ? FinanceTokens.Brand.primary : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum AIMemoPeriodChoice: String, CaseIterable, Identifiable {
    case previousMonth
    case currentMonth
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousMonth: "上月"
        case .currentMonth: "本月"
        case .custom: "自定义"
        }
    }

    func range(customStart: Date, customEnd: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = Date()
        switch self {
        case .currentMonth:
            let interval = calendar.dateInterval(of: .month, for: today)!
            return (interval.start, calendar.date(byAdding: .day, value: -1, to: interval.end)!)
        case .previousMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: today)!
            let interval = calendar.dateInterval(of: .month, for: previous)!
            return (interval.start, calendar.date(byAdding: .day, value: -1, to: interval.end)!)
        case .custom:
            return customStart <= customEnd ? (customStart, customEnd) : (customEnd, customStart)
        }
    }
}

private extension AIMemoDTO {
    var periodTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: periodStart)
    }

    func overviewValue(_ key: String) -> String {
        guard case .object(let overview) = statsJson["overview"],
              let value = overview[key] else {
            return "¥0.00"
        }
        let text = value.displayText
        if let decimal = Decimal(string: text) {
            return FinanceFormatter.money(DecimalValue(decimal), currency: .cny)
        }
        return text
    }
}

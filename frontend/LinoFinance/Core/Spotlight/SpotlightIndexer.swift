import Foundation

#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SpotlightIndexer {
    static let shared = SpotlightIndexer()
    static let domainIdentifier = "com.lino.linofinance.items"

    @MainActor
    func index(environment: AppEnvironment) async {
        guard environment.isAPITokenConfigured else {
            await clear()
            return
        }

        let items = makeItems(environment: environment)
        guard !items.isEmpty else {
            return
        }

        do {
            try await replace(items)
        } catch {
            environment.lastErrorMessage = "Spotlight 索引失败：\(error.localizedDescription)"
        }
    }

    func clear() async {
        _ = try? await deleteDomain()
    }

    static func target(from userActivity: NSUserActivity) -> SpotlightTarget? {
        guard let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }
        return SpotlightTarget(uniqueIdentifier: uniqueIdentifier)
    }

    @MainActor
    private func makeItems(environment: AppEnvironment) -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []
        items += environment.accountsViewModel.accounts.map { account in
            makeItem(
                type: .account,
                id: account.id,
                title: account.name,
                description: "\(account.type.title) · \(account.currency.rawValue) · \(account.status.financeStatusTitle)",
                symbolName: account.type == .credit ? "creditcard.fill" : "wallet.pass.fill",
                keywords: [account.name, account.type.title, account.currency.rawValue]
            )
        }

        items += environment.entriesViewModel.entries.map { entry in
            makeItem(
                type: .entry,
                id: entry.id,
                title: entry.title,
                description: "\(entry.status.title) · \(FinanceFormatter.mediumDate(entry.date))",
                symbolName: "square.and.pencil",
                keywords: [entry.title, entry.status.title, entry.note ?? ""]
            )
        }

        items += environment.reimbursementsViewModel.claims.map { claim in
            makeItem(
                type: .reimbursement,
                id: claim.id,
                title: "报销 \(FinanceFormatter.money(claim.amount, currency: claim.currency))",
                description: "\(claim.status.financeStatusTitle) · \(FinanceFormatter.mediumDate(claim.expectedDate))",
                symbolName: "arrow.uturn.left.circle.fill",
                keywords: [claim.status.financeStatusTitle, claim.payer, claim.note ?? ""]
            )
        }

        items += environment.aiViewModel.plans.map { plan in
            makeItem(
                type: .aiPlan,
                id: plan.id,
                title: plan.sourceText,
                description: "\(plan.status.financeStatusTitle) · \(plan.riskLevel.financeStatusTitle)",
                symbolName: "sparkles",
                keywords: [plan.sourceText, plan.status.financeStatusTitle, plan.explanation ?? ""]
            )
        }

        return items
    }

    private func makeItem(
        type: SpotlightTarget.TargetType,
        id: String,
        title: String,
        description: String,
        symbolName: String,
        keywords: [String]
    ) -> CSSearchableItem {
        let target = SpotlightTarget(type: type, id: id)
        let attributes = CSSearchableItemAttributeSet(contentType: .data)
        attributes.displayName = title
        attributes.contentDescription = description
        attributes.relatedUniqueIdentifier = target.relatedIdentifier
        attributes.thumbnailData = SpotlightThumbnail.render(symbolName: symbolName)
        attributes.keywords = keywords.filter { !$0.isEmpty }
        let item = CSSearchableItem(
            uniqueIdentifier: target.uniqueIdentifier,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
        item.expirationDate = Date.distantFuture
        return item
    }

    private func replace(_ items: [CSSearchableItem]) async throws {
        try await deleteDomain()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteDomain() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

struct SpotlightTarget: Equatable {
    enum TargetType: String {
        case account
        case entry
        case reimbursement
        case aiPlan = "ai_plan"

        var module: FinanceModule {
            switch self {
            case .account: .accounts
            case .entry: .entries
            case .reimbursement: .reimbursements
            case .aiPlan: .ai
            }
        }
    }

    let type: TargetType
    let id: String

    init(type: TargetType, id: String) {
        self.type = type
        self.id = id
    }

    init?(uniqueIdentifier: String) {
        let parts = uniqueIdentifier.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              parts[0] == "linofinance",
              let type = TargetType(rawValue: parts[1]),
              !parts[2].isEmpty else {
            return nil
        }
        self.type = type
        self.id = parts[2]
    }

    var uniqueIdentifier: String {
        "linofinance.\(type.rawValue).\(id)"
    }

    var relatedIdentifier: String {
        "\(type.rawValue):\(id)"
    }
}

private enum SpotlightThumbnail {
    static func render(symbolName: String) -> Data? {
#if os(iOS)
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { _ in
            UIColor.systemGreen.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            let image = UIImage(systemName: symbolName, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            image?.draw(in: CGRect(x: 18, y: 18, width: 28, height: 28))
        }
#elseif os(macOS)
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 14, yRadius: 14).fill()
        if let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 28, weight: .semibold)) {
            NSColor.white.set()
            symbol.draw(in: NSRect(x: 18, y: 18, width: 28, height: 28))
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
#else
        return nil
#endif
    }
}

@MainActor
extension AppEnvironment {
    func handleSpotlightUserActivity(_ userActivity: NSUserActivity) async {
        guard let target = SpotlightIndexer.target(from: userActivity) else {
            return
        }
        selectedModule = target.type.module
        if needsFreshData(for: target) {
            await refreshPrimaryData()
        }
        inspectorSelection = selection(for: target) ?? .module(target.type.module)
    }

    private func needsFreshData(for target: SpotlightTarget) -> Bool {
        selection(for: target) == nil
    }

    private func selection(for target: SpotlightTarget) -> InspectorSelection? {
        switch target.type {
        case .account:
            accountsViewModel.accounts.first { $0.id == target.id }.map(InspectorSelection.account)
        case .entry:
            entriesViewModel.entries.first { $0.id == target.id }.map(InspectorSelection.entry)
        case .reimbursement:
            reimbursementsViewModel.claims.first { $0.id == target.id }.map(InspectorSelection.reimbursement)
        case .aiPlan:
            aiViewModel.plans.first { $0.id == target.id }.map(InspectorSelection.aiPlan)
        }
    }
}
#endif

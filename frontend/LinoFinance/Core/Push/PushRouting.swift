import Foundation

@MainActor
extension AppEnvironment {
    func handlePushNotificationTarget(type: String?, id: String?) async {
        guard let type, let id else { return }
        switch type {
        case "credit_statement_cycle":
            selectedModule = .credit
            if creditViewModel.cycles.first(where: { $0.id == id }) == nil {
                await refreshPrimaryData()
            }
            inspectorSelection = creditViewModel.cycles.first { $0.id == id }.map(InspectorSelection.creditCycle)
                ?? .module(.credit)
        case "reimbursement_claim":
            selectedModule = .reimbursements
            if reimbursementsViewModel.claims.first(where: { $0.id == id }) == nil {
                await refreshPrimaryData()
            }
            inspectorSelection = reimbursementsViewModel.claims.first { $0.id == id }.map(InspectorSelection.reimbursement)
                ?? .module(.reimbursements)
        case "ai_plan":
            selectedModule = .ai
            if aiViewModel.plans.first(where: { $0.id == id }) == nil {
                await refreshPrimaryData()
            }
            inspectorSelection = aiViewModel.plans.first { $0.id == id }.map(InspectorSelection.aiPlan)
                ?? .module(.ai)
        default:
            break
        }
    }
}

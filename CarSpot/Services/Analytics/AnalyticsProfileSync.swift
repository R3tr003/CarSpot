import Foundation
import SwiftData

/// Costruisce lo snapshot del giocatore per il profilo utente Mixpanel e lo passa al
/// servizio. Si chiama dopo login, salvataggio carta, riscatto, cambio nome e al ritorno
/// in primo piano. Conta con `fetchCount` (nessuna foto caricata) e non fa nulla senza
/// consenso.
@MainActor
enum AnalyticsProfileSync {
    static func refresh(in context: ModelContext) {
        let analytics = AppServices.analytics
        guard analytics.consent == .granted else { return }

        let player = PlayerStore.profile(context)
        let legendary = Rarity.leggendaria.rawValue
        let epic = Rarity.epica.rawValue

        let total = (try? context.fetchCount(FetchDescriptor<StoredCard>())) ?? 0
        let legendaryCount = (try? context.fetchCount(FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.rarityRaw == legendary }))) ?? 0
        let epicCount = (try? context.fetchCount(FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.rarityRaw == epic }))) ?? 0

        var oldest = FetchDescriptor<StoredCard>(sortBy: [SortDescriptor(\.capturedAt)])
        oldest.fetchLimit = 1
        let firstCapture = (try? context.fetch(oldest))?.first?.capturedAt

        analytics.updateProfile(AnalyticsProfile(
            level: player.level,
            xp: player.xp,
            cardsCount: total,
            legendaryCount: legendaryCount,
            epicCount: epicCount,
            streakDays: player.streak,
            hasRealName: AppServices.auth.personName != nil,
            firstCaptureAt: firstCapture
        ))
    }
}

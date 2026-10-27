import Foundation

/// Cattura ridotta ai soli dati che servono alla serie.
struct StreakCapture: Sendable {
    let capturedAt: Date
    let rarity: Rarity
    let isRepeat: Bool
}

/// Oggi fatto / da fare / in pericolo / persa.
enum StreakStatus: Sendable, Equatable { case active, pending, atRisk, lost }

struct StreakState: Sendable, Equatable {
    let count: Int
    let status: StreakStatus
}

/// Regole della serie: un giorno conta con una cattura non ripetizione; un giorno saltato
/// si salva solo catturando una Rara (o superiore) il giorno dopo.
enum StreakCalculator {
    static func state(captures: [StreakCapture], now: Date, calendar: Calendar) -> StreakState {
        var activeDays: Set<Date> = []
        var rareDays: Set<Date> = []
        for capture in captures where !capture.isRepeat {
            let day = calendar.startOfDay(for: capture.capturedAt)
            activeDays.insert(day)
            if capture.rarity != .comune { rareDays.insert(day) }
        }

        func shift(_ day: Date, _ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: day) ?? day
        }
        func active(_ day: Date) -> Bool { activeDays.contains(day) }
        func rare(_ day: Date) -> Bool { rareDays.contains(day) }

        // Giorni attivi andando indietro da `start`; un buco si salta solo se
        // il giorno dopo è Raro e quello prima è attivo.
        func chain(from start: Date) -> Int {
            var count = 0
            var day = start
            while true {
                if active(day) {
                    count += 1
                } else if !(rare(shift(day, 1)) && active(shift(day, -1))) {
                    break
                }
                day = shift(day, -1)
            }
            return count
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = shift(today, -1)
        let twoDaysAgo = shift(today, -2)

        if rare(today) || (active(today) && active(yesterday)) {
            return StreakState(count: chain(from: today), status: .active)
        }
        if active(today) {
            // Ieri saltato, oggi solo Comune: in pericolo se c'era una serie, altrimenti riparte da 1.
            return active(twoDaysAgo)
                ? StreakState(count: chain(from: twoDaysAgo), status: .atRisk)
                : StreakState(count: 1, status: .active)
        }
        if active(yesterday) {
            return StreakState(count: chain(from: yesterday), status: .pending)
        }
        if active(twoDaysAgo) {
            return StreakState(count: chain(from: twoDaysAgo), status: .atRisk)
        }
        return StreakState(count: 0, status: .lost)
    }
}

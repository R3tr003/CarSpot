import Testing
import Foundation
@testable import CarSpot

/// Serie di giorni: fuso Europe/Rome, oggi = 2026-10-25 18:00 (giorno del cambio d'ora).
struct StreakTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 18))!
    }

    /// Mezzogiorno di `daysAgo` giorni fa (via Calendar, non per secondi).
    private func capture(_ daysAgo: Int, _ rarity: Rarity = .comune, isRepeat: Bool = false) -> StreakCapture {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        return StreakCapture(capturedAt: noon, rarity: rarity, isRepeat: isRepeat)
    }

    private func state(_ captures: [StreakCapture]) -> StreakState {
        StreakCalculator.state(captures: captures, now: now, calendar: calendar)
    }

    @Test func nessunaCattura() {
        #expect(state([]) == StreakState(count: 0, status: .lost))
    }

    @Test func oggiFatto() {
        #expect(state([capture(0), capture(1), capture(2)]) == StreakState(count: 3, status: .active))
    }

    @Test func oggiDaFare() {
        #expect(state([capture(1), capture(2)]) == StreakState(count: 2, status: .pending))
    }

    @Test func inPericolo() {
        #expect(state([capture(2), capture(3), capture(4)]) == StreakState(count: 3, status: .atRisk))
    }

    @Test func salvataConRara() {
        let s = state([capture(0, .rara), capture(2), capture(3), capture(4)])
        #expect(s == StreakState(count: 4, status: .active))
    }

    @Test func soloComuneOggiRestaInPericolo() {
        let s = state([capture(0), capture(2), capture(3), capture(4)])
        #expect(s == StreakState(count: 3, status: .atRisk))
    }

    @Test func buchiDoppi() {
        #expect(state([capture(3), capture(4), capture(5)]) == StreakState(count: 0, status: .lost))
    }

    @Test func buchiPassatiSalvati() {
        // Oggi..9 giorni fa attivi (il più vecchio Raro), buco 10 giorni fa, poi 11 e 12.
        var captures = (0...8).map { capture($0) }
        captures.append(capture(9, .epica))
        captures += [capture(11), capture(12)]
        #expect(state(captures) == StreakState(count: 12, status: .active))
    }

    @Test func buchiPassatiNonSalvatiFermanoLaCatena() {
        // Stesso schema ma il giorno prima del buco è Comune: la catena si ferma lì.
        let captures = (0...9).map { capture($0) } + [capture(11), capture(12)]
        #expect(state(captures) == StreakState(count: 10, status: .active))
    }

    @Test func ripetizioniNonContano() {
        // Solo ripetizioni (anche Rare): nessun giorno attivo.
        #expect(state([capture(0, .rara, isRepeat: true), capture(1, isRepeat: true)])
                == StreakState(count: 0, status: .lost))
        // Una ripetizione Rara oggi non salva la serie in pericolo.
        let s = state([capture(0, .rara, isRepeat: true), capture(2), capture(3), capture(4)])
        #expect(s == StreakState(count: 3, status: .atRisk))
    }
}

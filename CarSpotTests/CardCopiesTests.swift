import Testing
import Foundation
@testable import CarSpot

/// Regole dei doppioni: stesso modello = stessa chiave, XP che cala a ogni copia.
struct CardCopiesTests {
    @Test func keyNormalizza() {
        #expect(CardCopies.key(make: "VW ", model: " Polo") == CardCopies.key(make: "vw", model: "polo"))
        #expect(CardCopies.key(make: "Alfa  Romeo", model: "Giulia") == CardCopies.key(make: "alfa romeo", model: "giulia"))
        #expect(CardCopies.key(make: "Fiat", model: "Panda") != CardCopies.key(make: "Fiat", model: "Punto"))
    }

    @Test func xpPrimaCopia() {
        #expect(CardCopies.xp(base: 20, copyNumber: 1) == 20)
    }

    @Test func xpDoppioniComune() {
        #expect((2...5).map { CardCopies.xp(base: 20, copyNumber: $0) } == [5, 2, 1, 0])
    }

    @Test func xpDoppioniLeggendaria() {
        #expect((2...9).map { CardCopies.xp(base: 260, copyNumber: $0) } == [65, 32, 16, 8, 4, 2, 1, 0])
    }

    @Test func xpMaiNegativo() {
        #expect(CardCopies.xp(base: 260, copyNumber: 60) == 0)
        #expect(CardCopies.xp(base: 260, copyNumber: 0) == 260)
    }

    @Test func copyNumberVuoto() {
        #expect(CardCopies.copyNumber(make: "VW", model: "Polo", capturedAt: .now, among: []) == 1)
    }

    @Test func copyNumberOrdine() {
        let now = Date.now
        let existing: [(make: String, model: String, capturedAt: Date)] = [
            ("Volkswagen", "Polo", now.addingTimeInterval(-300)),
            ("volkswagen", "polo ", now.addingTimeInterval(-200)),
            ("Fiat", "Panda", now.addingTimeInterval(-100)),
            ("Volkswagen", "Polo", now.addingTimeInterval(60)),
        ]
        #expect(CardCopies.copyNumber(make: "Volkswagen", model: "Polo", capturedAt: now, among: existing) == 3)
    }

    @Test func ripetizioneStessoPosto() {
        let now = Date.now
        let existing: [(make: String, model: String, area: String, capturedAt: Date)] = [
            ("Volkswagen", "Polo", "Porta Romana", now.addingTimeInterval(-3_600)),
        ]
        #expect(CardCopies.isRepeatByPlace(make: "volkswagen", model: "polo", area: "porta  romana",
                                           capturedAt: now, among: existing))
        // Altro quartiere, oppure oltre le 24 ore: auto diversa.
        #expect(!CardCopies.isRepeatByPlace(make: "Volkswagen", model: "Polo", area: "Brera",
                                            capturedAt: now, among: existing))
        #expect(!CardCopies.isRepeatByPlace(make: "Volkswagen", model: "Polo", area: "Porta Romana",
                                            capturedAt: now.addingTimeInterval(86_400), among: existing))
        #expect(!CardCopies.isRepeatByPlace(make: "Fiat", model: "Panda", area: "Porta Romana",
                                            capturedAt: now, among: existing))
    }

    @Test func conteggio() {
        let all: [(make: String, model: String)] = [("VW", "Polo"), ("vw", "POLO"), ("Fiat", "Panda")]
        #expect(CardCopies.count(make: "VW", model: "Polo", among: all) == 2)
        #expect(CardCopies.count(make: "Toyota", model: "Yaris", among: all) == 0)
    }
}

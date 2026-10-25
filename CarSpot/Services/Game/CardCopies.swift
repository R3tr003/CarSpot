import Foundation

/// Doppioni: quando un modello è già in collezione. Logica pura, gemella del trigger
/// server `private.award_card` (migration 0009): le costanti vanno cambiate in coppia.
enum CardCopies {
    /// Quota dell'XP pieno data alla seconda copia; dalla terza si dimezza ogni volta.
    static let duplicateShare = 0.25

    /// Chiave del modello: minuscole, spazi ai lati tolti e quelli interni ridotti a uno.
    static func key(make: String, model: String) -> String {
        "\(normalized(make))|\(normalized(model))"
    }

    /// XP per la copia numero `copyNumber` (1 = prima): pieno, poi 25%, 12%, 6%… fino a 0.
    static func xp(base: Int, copyNumber: Int) -> Int {
        guard copyNumber > 1 else { return base }
        let share = duplicateShare / pow(2, Double(copyNumber - 2))
        return max(0, Int((Double(base) * share).rounded(.down)))
    }

    /// Posizione (1-based) di una carta tra le copie dello stesso modello, contando solo
    /// quelle catturate prima di lei.
    static func copyNumber(make: String, model: String, capturedAt: Date,
                           among existing: [(make: String, model: String, capturedAt: Date)]) -> Int {
        let target = key(make: make, model: model)
        let earlier = existing.filter { $0.capturedAt < capturedAt && key(make: $0.make, model: $0.model) == target }
        return earlier.count + 1
    }

    /// Finestra in cui lo stesso modello nello stesso quartiere è "la stessa auto".
    static let repeatWindow: TimeInterval = 86_400

    /// Stessa auto già catturata: stesso modello, stesso quartiere, nelle 24 ore prima.
    /// Gemella del trigger server `private.mark_repeat`.
    static func isRepeatByPlace(make: String, model: String, area: String, capturedAt: Date,
                                among existing: [(make: String, model: String, area: String, capturedAt: Date)]) -> Bool {
        let target = key(make: make, model: model)
        let place = normalized(area)
        return existing.contains {
            $0.capturedAt < capturedAt
                && capturedAt.timeIntervalSince($0.capturedAt) <= repeatWindow
                && normalized($0.area) == place
                && key(make: $0.make, model: $0.model) == target
        }
    }

    /// Quante carte dello stesso modello ci sono in `among`.
    static func count(make: String, model: String, among all: [(make: String, model: String)]) -> Int {
        let target = key(make: make, model: model)
        return all.filter { key(make: $0.make, model: $0.model) == target }.count
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

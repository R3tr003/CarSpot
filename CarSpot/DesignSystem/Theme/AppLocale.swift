import Foundation

extension Locale {
    /// Lingua in cui gira l'app (italiano o inglese, secondo `Bundle.preferredLocalizations`),
    /// non quella del telefono: date e numeri devono concordare con i testi mostrati.
    static var app: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "it")
    }
}

import SwiftUI

/// Puntino di stato senza numero, in alto a destra di un'etichetta: rosso = da fare
/// (`CSColor.danger`), verde = novità (`CSColor.success`). Il numero, se serve, va
/// nell'etichetta di VoiceOver di chi lo usa.
struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: CSSize.statusDot, height: CSSize.statusDot)
            .accessibilityHidden(true)
    }
}

extension View {
    /// `StatusDot` in alto a destra, fuori dal contenuto: non lo copre e non lo sposta
    /// quando compare o sparisce (serve un po' di spazio libero a destra).
    func statusDot(_ color: Color?) -> some View {
        overlay(alignment: .topTrailing) {
            if let color {
                StatusDot(color: color)
                    .offset(x: CSSize.statusDot + 3, y: 1)
            }
        }
    }
}

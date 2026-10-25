import SwiftUI

/// Foil monocromo reattivo: una banda di luce diagonale del colore della rarità (più un
/// filo di bianco al centro) che scorre sulla carta quando la inclini. Niente arcobaleno.
/// `wash` aggiunge un velo uniforme del colore (foil su tutta la carta); `roll`/`pitch`
/// sono l'inclinazione normalizzata -1...1.
struct HolographicFoil: View {
    var color: Color
    var roll: Double
    var pitch: Double
    var strength: Double = 1
    var wash: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Riduci movimento: foil fermo, nessuna reazione all'inclinazione.
        let r = reduceMotion ? 0 : roll
        let p = reduceMotion ? 0 : pitch
        // Spostamento della banda lungo la diagonale.
        let shift = r * 0.5 + p * 0.25

        ZStack {
            if wash > 0 {
                color.opacity(wash * strength)
            }
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: color.opacity(0.14 * strength), location: 0.40),
                    .init(color: .white.opacity(0.30 * strength), location: 0.50),
                    .init(color: color.opacity(0.22 * strength), location: 0.58),
                    .init(color: .clear, location: 0.75)
                ],
                startPoint: UnitPoint(x: shift, y: shift),
                endPoint: UnitPoint(x: 1 + shift, y: 1 + shift)
            )
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        CSColor.base
        HolographicFoil(color: Rarity.leggendaria.color, roll: 0.3, pitch: 0, strength: 1, wash: 0.1)
            .frame(width: 240, height: 340)
            .background(CSColor.hero)
    }
}

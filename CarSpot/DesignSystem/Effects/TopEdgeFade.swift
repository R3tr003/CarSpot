import SwiftUI

extension View {
    /// Testata agganciata "senza fascia": il contenuto che scorre sparisce sotto i primi
    /// `hidden` punti e riappare sfumando nei successivi `fade`. Nessun colore di fondo:
    /// sotto si vede il pannello vero, qualunque sia. Spento con `active == false`.
    func topEdgeFade(hidden: CGFloat, fade: CGFloat = CSSpace.lg, active: Bool) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.black.opacity(active ? 0 : 1).frame(height: hidden)
                LinearGradient(colors: [.black.opacity(active ? 0 : 1), .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
                Color.black
            }
        }
    }
}

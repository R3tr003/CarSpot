import SwiftUI

/// Tipografia sobria stile Flighty: SF Pro per titoli e testo; SF Pro Rounded
/// solo per i numeri di gioco (livello, PE, statistiche), dove porta il tono "gioco".
/// Niente etichette in maiuscolo spaziato: le etichette sono testo normale, piccolo.
///
/// Dynamic Type: la `size` richiesta viene mappata sullo stile di testo di sistema
/// più vicino (34 → largeTitle, 22 → title2, 15 → subheadline…), quindi ogni testo
/// scala con le impostazioni di accessibilità. Minimo 11 pt (caption2).
enum CSFont {

    static func display(_ size: CGFloat) -> Font {
        .system(style(for: size), weight: .bold)
    }

    static func title(_ size: CGFloat = 22) -> Font {
        .system(style(for: size), weight: .semibold)
    }

    static func numeric(_ size: CGFloat) -> Font {
        .system(style(for: size), design: .rounded, weight: .bold).monospacedDigit()
    }

    static func body(_ size: CGFloat = 16) -> Font {
        .system(style(for: size), weight: .regular)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .system(style(for: size), weight: .medium)
    }

    /// Micro-etichetta sotto un numero ("PE", "giorni", "uniche"): la più piccola ammessa.
    static let micro: Font = .system(.caption2, weight: .medium)

    /// Stile di testo di sistema con la dimensione di default più vicina a `size`.
    static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 31...: .largeTitle      // 34
        case 25..<31: .title         // 28
        case 21..<25: .title2        // 22
        case 18.5..<21: .title3      // 20
        case 16.5..<18.5: .body      // 17
        case 15.5..<16.5: .callout   // 16
        case 14..<15.5: .subheadline // 15
        case 12.5..<14: .footnote    // 13
        case 11.5..<12.5: .caption   // 12
        default: .caption2           // 11
        }
    }
}

extension View {
    /// Etichetta di sezione: testo normale (niente maiuscolo spaziato), piccolo e
    /// secondario. Un colore diverso solo per dati o stato (avviso, rarità).
    func eyebrow(_ color: Color = CSColor.inkSecondary) -> some View {
        self
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(color)
    }
}

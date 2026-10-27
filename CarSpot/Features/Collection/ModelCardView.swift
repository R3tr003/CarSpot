import SwiftUI

/// Ombra delle auto da trovare e sagoma di ripiego: inchiostro leggero, leggibile sul fondo
/// delle carte (il solo `nested` su `surface` ha un contrasto di circa 1,2:1).
let albumSilhouette = CSColor.ink.opacity(0.13)

/// Pillola piccola ("Nuova", "×3", "2/5") condivisa da carta e dettaglio.
struct CountPill: View {
    let text: LocalizedStringKey
    var fill: Color = CSColor.nested
    var textColor: Color = CSColor.ink

    init(_ text: LocalizedStringKey, fill: Color = CSColor.nested, textColor: Color = CSColor.ink) {
        self.text = text
        self.fill = fill
        self.textColor = textColor
    }

    var body: some View {
        Text(text)
            .font(CSFont.micro)
            .monospacedDigit()
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .accessibilityHidden(true)
    }
}

/// Misure della carta modello.
private enum Metrics {
    static let aspect = 0.7
    static let gridPadding: CGFloat = 8
    static let dotSize: CGFloat = 8
    static let tiltX: CGFloat = 8
    static let tiltY: CGFloat = 6
    static let veil = 0.16
    static let imageShadow = 0.35
    static let nameScale: CGFloat = 0.85
}

/// Ombra della carta solo quando serve: le ombre (da trovare) restano piatte.
private extension View {
    @ViewBuilder func cardShadow(_ on: Bool, hero: Bool) -> some View {
        if on {
            shadow(color: .black.opacity(hero ? 0.5 : 0.3), radius: hero ? 20 : 10, y: hero ? 14 : 6)
        } else {
            self
        }
    }
}

/// Carta modello dell'album: l'immagine standard del catalogo sulla base della rarità
/// (trovata) oppure la sua ombra con il nome (da trovare). Mai le foto dell'utente.
/// `grid` = cella a 3 colonne; `hero` = carta grande del dettaglio.
struct ModelCardView: View {
    enum Style { case grid, hero }

    let entry: AlbumModelEntry
    var style: Style = .grid
    /// Inclinazione già effettiva (0 con Riduci movimento): serve solo a `hero`.
    var roll: Double = 0
    var pitch: Double = 0

    private var isHero: Bool { style == .hero }
    private var padding: CGFloat { isHero ? CSSpace.md : Metrics.gridPadding }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isHero ? CSRadius.card : CSRadius.sm, style: .continuous)
    }
    private var color: Color { entry.rarity.color }
    private var nameFont: Font { isHero ? CSFont.title(20) : CSFont.caption(12) }

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: CSSpace.xxs) {
                topRow
                artwork
                labels
            }
            .padding(padding)
        }
        .aspectRatio(Metrics.aspect, contentMode: .fit)
        // Proporzione fissa: il Dynamic Type è limitato.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .overlay {
            if entry.isFound {
                RarityFrame(rarity: entry.rarity, shape: shape, roll: roll, pitch: pitch, compact: !isHero)
            } else {
                shape.strokeBorder(CSColor.hairline, lineWidth: 1)
            }
        }
        .clipShape(shape)
        .cardShadow(entry.isFound, hero: isHero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    // MARK: Sfondo e immagine

    @ViewBuilder private var background: some View {
        if entry.isFound {
            ZStack {
                LinearGradient(colors: [CSColor.elevated, CSColor.surface],
                               startPoint: .top, endPoint: .bottom)
                // Velo della rarità, leggero e dall'alto: niente alone.
                LinearGradient(colors: [color.opacity(Metrics.veil), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
        } else {
            CSColor.surface
        }
    }

    /// Trovata: immagine con ombra a terra (glifo in colore rarità se manca l'immagine);
    /// da trovare: sagoma piatta.
    @ViewBuilder private var artwork: some View {
        let image = CatalogImageView(
            image: entry.image, bodyType: entry.bodyType, silhouette: !entry.isFound,
            maxPixel: isHero ? 700 : 400,
            tint: entry.isFound ? color.opacity(0.5) : albumSilhouette
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: isHero ? roll * Metrics.tiltX : 0, y: isHero ? pitch * Metrics.tiltY : 0)

        if entry.isFound && entry.image != nil {
            image.shadow(color: .black.opacity(Metrics.imageShadow),
                         radius: isHero ? 8 : 4, y: isHero ? 8 : 4)
        } else {
            image
        }
    }

    // MARK: Testi

    /// "Nuova" a sinistra, "×N" a destra; assente (senza altezza) quando non serve.
    @ViewBuilder private var topRow: some View {
        if entry.isFound && (entry.isNew || entry.copies > 1) {
            HStack(spacing: CSSpace.xxs) {
                if entry.isNew { CountPill("Nuova", fill: CSColor.ink, textColor: CSColor.inkInverse) }
                Spacer(minLength: 0)
                if entry.copies > 1 { CountPill("×\(entry.copies)") }
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.isFound {
                HStack(spacing: CSSpace.xxs) {
                    makeName
                    Spacer(minLength: 0)
                    if entry.versionsTotal > 1 {
                        CountPill("\(entry.versionsFound)/\(entry.versionsTotal)",
                                  textColor: CSColor.inkSecondary)
                            .layoutPriority(1)
                    }
                }
                name(CSColor.ink)
            } else {
                // Da trovare: pallino della rarità del catalogo accanto al nome.
                HStack(alignment: .firstTextBaseline, spacing: CSSpace.xxs) {
                    Circle()
                        .fill(color)
                        .frame(width: Metrics.dotSize, height: Metrics.dotSize)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    name(CSColor.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var makeName: some View {
        if isHero {
            Text(entry.makeName).eyebrow(color).lineLimit(1)
        } else {
            Text(entry.makeName)
                .font(CSFont.micro).fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func name(_ textColor: Color) -> some View {
        Text(entry.name)
            .font(nameFont)
            .fontWeight(isHero ? nil : .semibold)
            .foregroundStyle(textColor)
            .lineLimit(2)
            .minimumScaleFactor(Metrics.nameScale)
            .multilineTextAlignment(.leading)
    }

    // MARK: Accessibilità

    private var spokenLabel: String {
        var parts = ["\(entry.makeName) \(entry.name)", entry.rarity.localizedName]
        parts.append(entry.isFound ? String(localized: "trovata") : String(localized: "da trovare"))
        if entry.versionsTotal > 1 {
            parts.append(String(localized: "\(entry.versionsFound) versioni su \(entry.versionsTotal)"))
        }
        if entry.copies > 1 { parts.append(String(localized: "\(entry.copies) copie")) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    let image: CatalogImage? = nil
    HStack {
        ModelCardView(entry: AlbumModelEntry(
            id: "a", makeName: "Fiat", name: "Panda", bodyType: .utilitaria, rarity: .comune,
            isFound: true, copies: 2, isNew: true, versionsFound: 1, versionsTotal: 3, image: image))
        ModelCardView(entry: AlbumModelEntry(
            id: "b", makeName: "Ferrari", name: "296 GTB", bodyType: .sportiva, rarity: .leggendaria,
            isFound: false, copies: 0, isNew: false, versionsFound: 0, versionsTotal: 1, image: image))
    }
    .padding()
    .background(CSColor.panel)
}

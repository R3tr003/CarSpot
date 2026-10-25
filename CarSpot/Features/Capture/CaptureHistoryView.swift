import SwiftUI
import SwiftData
import ImageIO

/// Misure e tempi della cronologia.
private enum Metrics {
    static let thumbnailSize: CGFloat = 52
    static let thumbnailRadius: CGFloat = 10
    static let thumbnailBorder: CGFloat = 2
    /// Lato lungo della miniatura decodificata (52 pt a 3x).
    static let thumbnailPixels = 160
    static let rowPaddingH: CGFloat = CSSpace.sm + 2
    static let rowSpacing: CGFloat = CSSpace.sm
    /// I divisori partono dal testo, non dalla miniatura.
    static let dividerInset = rowPaddingH + thumbnailSize + rowSpacing
    static let rarityDot: CGFloat = 7
    static let repeatTagMaxWidth: CGFloat = 120
    /// Spazio in fondo per non finire sotto la tab bar.
    static let bottomInset: CGFloat = 130
    /// Velo "appena catturata": intensità iniziale, attesa (copre l'uscita della fotocamera) e durata.
    static let freshOpacity = 0.10
    static let freshDelay: Duration = .milliseconds(500)
    static let freshFade: TimeInterval = 2.5
}

/// Contenuto della tab Cattura: la cronologia di ogni scatto, dal più recente, raggruppata
/// per giorno. La fotocamera si apre dal bottone (o toccando la tab); chiudendola si resta qui.
/// A differenza della Collezione (una carta per modello) qui c'è ogni cattura, anche le
/// ripetizioni della stessa auto, che valgono 0 punti.
struct CaptureHistoryView: View {
    /// Apre la fotocamera (la presenta `RootShellView`).
    let onShoot: () -> Void
    /// `true` mentre la fotocamera è a schermo: serve a evidenziare le righe nate in quella sessione.
    let isCameraPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \StoredCard.capturedAt, order: .reverse) private var stored: [StoredCard]
    @Namespace private var zoomNamespace

    /// Righe da evidenziare dopo la chiusura della fotocamera e intensità del velo (1 → 0).
    @State private var cameraOpenedAt: Date?
    @State private var freshIDs: Set<UUID> = []
    @State private var freshStrength = 0.0
    @State private var fadeToken = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CSSpace.md) {
                    SheetHeader(title: "Cattura")
                    PrimaryButton(title: "Scatta una foto", icon: "camera.fill", action: onShoot)
                    if stored.isEmpty {
                        emptyState
                    } else {
                        let history = History(stored)
                        summary(history)
                        ForEach(history.days, id: \.day) { day in
                            section(day, ordinals: history.ordinals)
                        }
                    }
                }
                .padding(CSSpace.lg)
                .padding(.bottom, Metrics.bottomInset)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            // Sfondo trasparente: il colore del pannello arriva da `presentationBackground`.
            .containerBackground(.clear, for: .navigation)
            .scrollContentBackground(.hidden)
        }
        .onChange(of: isCameraPresented, initial: true) { _, presented in
            if presented {
                cameraOpenedAt = .now
            } else {
                markFresh()
            }
        }
        // Il velo svanisce una volta sola, dopo che la fotocamera è uscita di scena.
        .task(id: fadeToken) {
            guard !freshIDs.isEmpty else { return }
            try? await Task.sleep(for: Metrics.freshDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Metrics.freshFade)) { freshStrength = 0 }
        }
    }

    /// Alla chiusura della fotocamera evidenzia solo le carte salvate nella sessione appena
    /// finita: chiudendo senza salvare non c'è nulla da evidenziare.
    private func markFresh() {
        defer { cameraOpenedAt = nil }
        guard let since = cameraOpenedAt, !reduceMotion else { return }
        let ids = Set(stored.filter { $0.capturedAt >= since }.map(\.id))
        guard !ids.isEmpty else { return }
        freshIDs = ids
        freshStrength = 1
        fadeToken += 1
    }

    // MARK: - Riassunto e sezioni

    private func summary(_ history: History) -> some View {
        let relative = history.last.formatted(.relative(presentation: .named).locale(.app))
        return Text("^[\(history.cardCount) carta](inflect: true) · ^[\(history.modelCount) modello](inflect: true) · ultima cattura \(relative)")
            .font(CSFont.caption(12))
            .foregroundStyle(CSColor.inkSecondary)
            .monospacedDigit()
            .padding(.horizontal, CSSpace.xxs)
    }

    private func section(_ day: History.Day, ordinals: [UUID: Int]) -> some View {
        VStack(alignment: .leading, spacing: CSSpace.xs) {
            HStack {
                dayTitle(day.day).font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary)
                Spacer()
                Text("^[\(day.cards.count) cattura](inflect: true)").font(CSFont.caption(13)).foregroundStyle(CSColor.inkSecondary).monospacedDigit()
            }
            .padding(.horizontal, CSSpace.xxs)
            .padding(.top, CSSpace.sm)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Surface(.group, padding: nil) {
                VStack(spacing: 0) {
                    ForEach(Array(day.cards.enumerated()), id: \.element.id) { index, card in
                        if index > 0 { SurfaceDivider(inset: Metrics.dividerInset) }
                        NavigationLink {
                            CardDetailView(card: card.asSpotCard)
                                .navigationTransition(.zoom(sourceID: card.id, in: zoomNamespace))
                        } label: {
                            HistoryRow(card: card, ordinal: ordinals[card.id],
                                       namespace: zoomNamespace,
                                       freshness: freshIDs.contains(card.id) ? freshStrength : 0)
                        }
                        .buttonStyle(HistoryRowStyle())
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Text("Oggi") }
        if calendar.isDateInYesterday(day) { return Text("Ieri") }
        return Text(verbatim: day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.app)))
    }

    private var emptyState: some View {
        VStack(spacing: CSSpace.xs) {
            Text("Nessuna cattura")
                .font(CSFont.title(20)).foregroundStyle(CSColor.ink)
            Text("Ogni auto che fotografi compare qui, dalla più recente.")
                .font(CSFont.body(15)).foregroundStyle(CSColor.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, CSSpace.xl)
        .padding(.horizontal, CSSpace.lg)
    }

    // MARK: - Dati derivati

    /// Cronologia derivata dalle carte, calcolata una volta per render (non per riga).
    private struct History {
        struct Day { let day: Date; let cards: [StoredCard] }

        let days: [Day]
        /// "Nª copia del modello" al momento dello scatto, solo tra le carte non ripetute.
        let ordinals: [UUID: Int]
        let cardCount: Int
        let modelCount: Int
        let last: Date

        init(_ cards: [StoredCard]) {
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: cards) { calendar.startOfDay(for: $0.capturedAt) }
            days = grouped.keys.sorted(by: >).map { Day(day: $0, cards: grouped[$0] ?? []) }
            last = cards.first?.capturedAt ?? .now

            // Dalla più vecchia: ogni carta non ripetuta è la "n-esima" del suo modello
            // (stessa regola di `CardCopies.copyNumber`: conta le precedenti).
            var seen: [String: Int] = [:]
            var numbers: [UUID: Int] = [:]
            for card in cards.reversed() where !card.isRepeat {
                let key = CardCopies.key(make: card.make, model: card.model)
                let next = (seen[key] ?? 0) + 1
                seen[key] = next
                numbers[card.id] = next
            }
            ordinals = numbers
            cardCount = numbers.count
            modelCount = seen.count
        }
    }
}

// MARK: - Riga

private struct HistoryRow: View {
    let card: StoredCard
    /// Posizione tra le copie del modello; `nil` per le ripetizioni.
    let ordinal: Int?
    let namespace: Namespace.ID
    /// Intensità (0…1) del velo "appena catturata".
    let freshness: Double

    @Environment(SyncService.self) private var sync: SyncService?

    var body: some View {
        HStack(spacing: Metrics.rowSpacing) {
            HistoryThumbnail(photo: card.photo, color: card.rarity.color)
                .matchedTransitionSource(id: card.id, in: namespace)
                // Foto ripristinata dal cloud: si scarica solo quando la riga appare.
                .task(id: card.id) { await sync?.loadPhotoIfNeeded(cardId: card.id) }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.make)
                    .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                    .lineLimit(1)
                Text(card.model)
                    .font(CSFont.title(15)).foregroundStyle(CSColor.ink)
                    .lineLimit(1)
                Text(verbatim: place)
                    .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: CSSpace.xs)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(card.rarity.color).frame(width: Metrics.rarityDot, height: Metrics.rarityDot)
                    Text(card.rarity.displayName)
                        .font(CSFont.caption(12).weight(.bold))
                        .foregroundStyle(card.rarity.color)
                }
                tag
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Metrics.rowPaddingH)
        .padding(.vertical, CSSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.rarity.color.opacity(Metrics.freshOpacity * freshness))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Quartiere · ora" (senza quartiere, solo l'ora).
    private var place: String {
        let time = card.capturedAt.formatted(.dateTime.hour().minute().locale(.app))
        return card.spottedArea.isEmpty ? time : "\(card.spottedArea) · \(time)"
    }

    @ViewBuilder private var tag: some View {
        if let ordinal {
            Group {
                if ordinal == 1 { Text("Nuova") } else { Text("\(ordinal)ª") }
            }
            .font(CSFont.caption(12)).foregroundStyle(CSColor.inkSecondary).monospacedDigit()
            .accessibilityLabel(ordinal == 1 ? Text("Nuova") : Text("Copia numero \(ordinal)"))
        } else {
            Text("Già vista · nessun punto")
                .font(CSFont.caption(12)).foregroundStyle(CSColor.inkTertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(maxWidth: Metrics.repeatTagMaxWidth, alignment: .trailing)
        }
    }
}

/// Miniatura 52 pt con bordo interno 2 pt del colore della rarità.
private struct HistoryThumbnail: View {
    let photo: Data?
    let color: Color

    @State private var thumbnail: HistoryDecodedImage?

    private let shape = RoundedRectangle(cornerRadius: Metrics.thumbnailRadius, style: .continuous)

    var body: some View {
        Color.clear
            .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
            .background(CSColor.nested)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "car.fill")
                        .font(CSFont.title(17))
                        .foregroundStyle(CSColor.inkTertiary)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(color, lineWidth: Metrics.thumbnailBorder) }
            .task(id: photo?.count) {
                guard let photo else { thumbnail = nil; return }
                thumbnail = await decodeHistoryThumbnail(photo)
            }
    }
}

/// Immagine già decodificata, passabile tra isolation.
private struct HistoryDecodedImage: @unchecked Sendable {
    let image: CGImage
}

/// Decodifica ImageIO fuori dal main actor (~160 px per 52 pt a 3x, orientamento applicato).
@concurrent
private func decodeHistoryThumbnail(_ data: Data) async -> HistoryDecodedImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Metrics.thumbnailPixels
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return HistoryDecodedImage(image: cg)
}

/// Pressione di una riga in un gruppo: stessa resa di `CSPressStyle` (scala con molla senza
/// rimbalzo; solo attenuazione con Riduci movimento) più il fondo `nested`.
private struct HistoryRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background(pressed ? CSColor.nested : .clear)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(duration: 0.2, bounce: 0), value: pressed)
    }
}

#Preview {
    CaptureHistoryView(onShoot: {}, isCameraPresented: false)
        .background(CSColor.panel)
        .preferredColorScheme(.dark)
        .modelContainer(for: [StoredCard.self, PlayerProfile.self], inMemory: true)
}

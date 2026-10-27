import SwiftUI

/// Campo di ricerca a capsula con ✕ per svuotare. I suggerimenti li mostra `CollectionView`.
struct AlbumSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: CSSpace.sm) {
            Image(systemName: "magnifyingglass")
                .font(CSFont.body(16))
                .foregroundStyle(CSColor.inkTertiary)
                .accessibilityHidden(true)
            TextField("Cerca marca o modello", text: $text)
                .font(CSFont.body(16))
                .foregroundStyle(CSColor.ink)
                .focused(isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(CSFont.body(17))
                        .foregroundStyle(CSColor.inkTertiary)
                        .frame(width: CSSize.minTap, height: CSSize.minTap)
                        .contentShape(.rect)
                }
                .buttonStyle(CSPressStyle())
                .accessibilityLabel("Cancella la ricerca")
            }
        }
        .padding(.leading, CSSpace.md)
        .padding(.trailing, text.isEmpty ? CSSpace.md : 0)
        .frame(minHeight: CSSize.minTap)
        .background(Capsule().fill(CSColor.nested))
        .contentShape(Capsule())
        .onTapGesture { isFocused.wrappedValue = true }
    }
}

/// Fino a 5 suggerimenti sotto il campo: il tocco riempie la ricerca.
struct AlbumSuggestions: View {
    let items: [String]
    let onPick: (String) -> Void

    var body: some View {
        Surface(.group, padding: nil) {
            VStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    if item != items.first { SurfaceDivider(inset: CSSpace.md) }
                    Button { onPick(item) } label: {
                        HStack(spacing: CSSpace.sm) {
                            Image(systemName: "magnifyingglass")
                                .font(CSFont.caption(13))
                                .foregroundStyle(CSColor.inkTertiary)
                                .accessibilityHidden(true)
                            Text(item)
                                .font(CSFont.body(15))
                                .foregroundStyle(CSColor.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, CSSpace.md)
                        .frame(minHeight: CSSize.minTap)
                        .contentShape(.rect)
                    }
                    .buttonStyle(CSPressStyle())
                }
            }
        }
    }
}

/// Segmentato nativo Tutte / Trovate / Da trovare.
struct AlbumOwnershipPicker: View {
    let selection: Ownership
    let onChange: (Ownership) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var picker: some View {
        Picker("Mostra", selection: Binding(get: { selection }, set: onChange)) {
            ForEach(Ownership.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }

    var body: some View {
        // Con Dynamic Type da accessibilità il segmentato taglia i titoli: meglio un menu.
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}

/// Le quattro pillole a menu (Rarità, Carrozzeria, Paese, Epoca), in scorrimento orizzontale.
struct AlbumPillRow: View {
    let model: AlbumModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CSSpace.sm) {
                rarityPill
                bodyPill
                countryPill
                eraPill
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var rarityPill: some View {
        AlbumPill(title: "Rarità", value: model.filters.rarity?.localizedName,
                  onClear: { model.setRarity(nil) }) {
            ForEach(Rarity.allCases) { rarity in
                Button { model.setRarity(rarity) } label: { checked(rarity.localizedName, model.filters.rarity == rarity) }
            }
        }
    }

    private var bodyPill: some View {
        AlbumPill(title: "Carrozzeria", value: model.filters.bodyType?.localizedName,
                  onClear: { model.setBodyType(nil) }) {
            ForEach(BodyType.allCases, id: \.self) { body in
                Button { model.setBodyType(body) } label: { checked(body.localizedName, model.filters.bodyType == body) }
            }
        }
    }

    private var countryPill: some View {
        AlbumPill(title: "Paese", value: model.filters.country.map(Self.countryName),
                  onClear: { model.setCountry(nil) }) {
            ForEach(model.countries, id: \.self) { code in
                Button { model.setCountry(code) } label: { checked(Self.countryName(code), model.filters.country == code) }
            }
        }
    }

    private var eraPill: some View {
        AlbumPill(title: "Epoca", value: model.filters.era.map(AlbumEra.title),
                  onClear: { model.setEra(nil) }) {
            ForEach(AlbumEra.all, id: \.self) { era in
                Button { model.setEra(era) } label: { checked(AlbumEra.title(era), model.filters.era == era) }
            }
        }
    }

    private static func countryName(_ code: String) -> String {
        Locale.app.localizedString(forRegionCode: code) ?? code
    }

    @ViewBuilder private func checked(_ title: String, _ on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

/// Pillola a menu: da spenta "Rarità ⌄"; da accesa piena d'inchiostro con il valore e ✕.
struct AlbumPill<Items: View>: View {
    let title: LocalizedStringResource
    let value: String?
    let onClear: () -> Void
    @ViewBuilder let items: Items

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                items
            } label: {
                HStack(spacing: CSSpace.xxs) {
                    if let value {
                        Text(value)
                    } else {
                        Text(title)
                        Image(systemName: "chevron.down").font(CSFont.micro)
                    }
                }
                .font(CSFont.caption(13))
                .foregroundStyle(value == nil ? CSColor.inkSecondary : CSColor.inkInverse)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, CSSpace.md)
                .padding(.trailing, value == nil ? CSSpace.md : CSSpace.xs)
                .frame(minHeight: CSSize.minTap)
                .contentShape(Capsule())
            }
            .accessibilityLabel(Text(title))
            .accessibilityValue(value ?? "")
            if value != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(CSFont.micro)
                        .foregroundStyle(CSColor.inkInverse)
                        .frame(width: CSSize.minTap, height: CSSize.minTap)
                        .contentShape(.rect)
                }
                .buttonStyle(CSPressStyle())
                .accessibilityLabel("Togli il filtro \(String(localized: title))")
            }
        }
        .background(Capsule().fill(value == nil ? CSColor.nested : CSColor.ink))
        .sensoryFeedback(.selection, trigger: value)
    }
}

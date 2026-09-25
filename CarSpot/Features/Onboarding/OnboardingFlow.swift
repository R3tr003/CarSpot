import SwiftUI

/// Onboarding in stile Flighty/Wheelz: una pagina di intro statica (la macchina)
/// e poi pagine animate che raccontano cosa fa l'app. Allo "Skip" o all'ultima
/// pagina si arriva al login.
struct OnboardingFlow: View {
    var onFinished: () -> Void

    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        ZStack {
            // Sfondo: statico sulla prima pagina (la macchina), animato sulle altre.
            if page == 0 {
                AsphaltBackground(tint: Rarity.leggendaria.primary)
            } else {
                ZStack {
                    CSColor.base.ignoresSafeArea()
                    DottedBackdrop(tint: pageTint)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }

            VStack(spacing: 0) {
                // Skip in alto a destra.
                HStack {
                    Spacer()
                    Button("Salta") { onFinished() }
                        .font(CSFont.caption(14))
                        .foregroundStyle(CSColor.inkSecondary)
                        .padding(.trailing, CSSpace.lg)
                        .padding(.top, CSSpace.sm)
                        .opacity(page == pageCount - 1 ? 0 : 1)
                }

                TabView(selection: $page) {
                    IntroCarPage().tag(0)
                    StatsPage(active: page == 1).tag(1)
                    CollectionPage(active: page == 2).tag(2)
                    FriendsPage(active: page == 3).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: page)

                // Indicatore + CTA.
                VStack(spacing: CSSpace.lg) {
                    PageDots(count: pageCount, index: page, tint: pageTint)

                    PrimaryButton(
                        title: page == pageCount - 1 ? "Inizia la caccia" : "Avanti",
                        icon: page == pageCount - 1 ? "bolt.fill" : "arrow.right",
                        gradient: pageGradient
                    ) {
                        if page == pageCount - 1 {
                            onFinished()
                        } else {
                            withAnimation(.easeInOut(duration: 0.4)) { page += 1 }
                        }
                    }
                    .padding(.horizontal, CSSpace.xl)
                }
                .padding(.bottom, CSSpace.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageTint: Color {
        [Rarity.leggendaria, .rara, .epica, .rara][page].primary
    }
    private var pageGradient: [Color] {
        [Rarity.leggendaria, .rara, .epica, .rara][page].gradient
    }
}

// MARK: - Pagina 0 · Intro statica (la macchina)

private struct IntroCarPage: View {
    var body: some View {
        VStack(spacing: CSSpace.lg) {
            Spacer()
            ZStack {
                RadialGradient(
                    colors: [Rarity.leggendaria.primary.opacity(0.35), .clear],
                    center: .center, startRadius: 4, endRadius: 240
                )
                .frame(height: 320)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 132, weight: .black))
                    .foregroundStyle(Rarity.leggendaria.linearGradient)
                    .shadow(color: Rarity.leggendaria.primary.opacity(0.5), radius: 30, y: 12)
            }

            VStack(spacing: CSSpace.sm) {
                Text("CARSPOT").eyebrow(Rarity.leggendaria.primary)
                Text("Ogni auto è\nuna carta da prendere")
                    .font(CSFont.display(34))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CSColor.ink)
                Text("Fotografa le auto che incroci, scopri la loro rarità e costruisci la tua collezione.")
                    .font(CSFont.body(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CSColor.inkSecondary)
                    .padding(.horizontal, CSSpace.xl)
            }
            Spacer()
        }
    }
}

// MARK: - Pagina 1 · Statistiche animate

private struct StatsPage: View {
    var active: Bool
    var body: some View {
        OnboardingScaffold(
            eyebrow: "RICONOSCIMENTO",
            title: "Ogni scatto\nha le sue stats",
            subtitle: "Potenza, rarità ed esclusività vengono calcolate al volo da ogni avvistamento."
        ) {
            GlassPanel {
                VStack(spacing: CSSpace.md) {
                    if active {
                        StatBar(label: "Potenza", value: 92, tint: Rarity.leggendaria.primary)
                        StatBar(label: "Rarità", value: 78, tint: Rarity.epica.primary)
                        StatBar(label: "Esclusività", value: 64, tint: Rarity.rara.primary)
                    } else {
                        Color.clear.frame(height: 92)
                    }
                }
            }
            .padding(.horizontal, CSSpace.lg)
        }
    }
}

// MARK: - Pagina 2 · Collezione animata

private struct CollectionPage: View {
    var active: Bool
    @State private var appear = false
    var body: some View {
        OnboardingScaffold(
            eyebrow: "COLLEZIONE",
            title: "Riempi\nil tuo garage",
            subtitle: "Ogni carta entra nella tua collezione. Le leggendarie brillano con il foil olografico."
        ) {
            HStack(spacing: CSSpace.sm) {
                ForEach(Array(Rarity.allCases.enumerated()), id: \.offset) { i, r in
                    RoundedRectangle(cornerRadius: CSRadius.sm, style: .continuous)
                        .fill(r.linearGradient)
                        .frame(width: 64, height: 92)
                        .overlay(
                            Image(systemName: r.symbol)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.black.opacity(0.55))
                        )
                        .shadow(color: r.primary.opacity(0.5), radius: 12, y: 6)
                        .rotationEffect(.degrees(appear ? Double(i - 2) * 5 : 0))
                        .offset(y: appear ? 0 : 40)
                        .opacity(appear ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(i) * 0.08), value: appear)
                }
            }
        }
        .onChange(of: active, initial: true) { _, now in appear = now }
    }
}

// MARK: - Pagina 3 · Amici / mappa animata

private struct FriendsPage: View {
    var active: Bool
    @State private var appear = false
    var body: some View {
        OnboardingScaffold(
            eyebrow: "TERRITORIO",
            title: "Conquista\nil quartiere",
            subtitle: "Vedi dove sono stati fatti gli avvistamenti e sfida gli altri spotter sulla mappa."
        ) {
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) / 6 * .pi * 2
                    Circle()
                        .fill(Rarity.allCases[i % 4].linearGradient)
                        .frame(width: 46, height: 46)
                        .overlay(Image(systemName: "car.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.black.opacity(0.5)))
                        .offset(x: appear ? cos(angle) * 92 : 0, y: appear ? sin(angle) * 92 : 0)
                        .opacity(appear ? 1 : 0)
                        .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(Double(i) * 0.07), value: appear)
                }
                Circle()
                    .fill(CSColor.accent.gradient)
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: "mappin.and.ellipse").font(.system(size: 22, weight: .bold)).foregroundStyle(.black.opacity(0.6)))
                    .shadow(color: CSColor.accent.opacity(0.6), radius: 16)
            }
            .frame(height: 240)
        }
        .onChange(of: active, initial: true) { _, now in appear = now }
    }
}

// MARK: - Scaffold condiviso delle pagine animate

private struct OnboardingScaffold<Content: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: CSSpace.xl) {
            Spacer()
            content
            VStack(spacing: CSSpace.sm) {
                Text(eyebrow).eyebrow(CSColor.accent)
                Text(title)
                    .font(CSFont.display(32))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CSColor.ink)
                Text(subtitle)
                    .font(CSFont.body(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CSColor.inkSecondary)
                    .padding(.horizontal, CSSpace.xl)
            }
            Spacer()
        }
    }
}

// MARK: - Dots

private struct PageDots: View {
    var count: Int
    var index: Int
    var tint: Color
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? tint : CSColor.inkTertiary.opacity(0.5))
                    .frame(width: i == index ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4), value: index)
            }
        }
    }
}

#Preview {
    OnboardingFlow(onFinished: {})
}

import SwiftUI

/// Onboarding in stile Flighty/Wheelz: una pagina di intro statica (la macchina)
/// e poi pagine animate che raccontano cosa fa l'app. Allo "Skip" o all'ultima
/// pagina si arriva al login. L'ultima pagina chiede il consenso alle statistiche
/// anonime (GDPR): non si può saltare.
struct OnboardingFlow: View {
    var onFinished: () -> Void

    @State private var page = 0
    private let pageCount = 5
    private var consentPage: Int { pageCount - 1 }

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
                    Button("Salta") {
                        // Il consenso non si salta in silenzio: si va alla sua pagina.
                        withAnimation(.easeInOut(duration: 0.4)) { page = consentPage }
                    }
                    .font(CSFont.caption(14))
                    .foregroundStyle(CSColor.inkSecondary)
                    .padding(.trailing, CSSpace.lg)
                    .padding(.top, CSSpace.sm)
                    .opacity(page == consentPage ? 0 : 1)
                    .disabled(page == consentPage)
                }

                TabView(selection: $page) {
                    IntroCarPage().tag(0)
                    StatsPage(active: page == 1).tag(1)
                    CollectionPage(active: page == 2).tag(2)
                    FriendsPage(active: page == 3).tag(3)
                    ConsentPage().tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: page)

                // Indicatore + CTA.
                VStack(spacing: CSSpace.lg) {
                    PageDots(count: pageCount, index: page, tint: pageTint)

                    if page == consentPage {
                        VStack(spacing: CSSpace.sm) {
                            PrimaryButton(title: "Accetta", icon: "checkmark", gradient: pageGradient) {
                                finish(with: .granted)
                            }
                            GhostButton(title: "No, grazie") { finish(with: .denied) }
                        }
                        .padding(.horizontal, CSSpace.xl)
                    } else {
                        PrimaryButton(title: "Avanti", icon: "arrow.right", gradient: pageGradient) {
                            withAnimation(.easeInOut(duration: 0.4)) { page += 1 }
                        }
                        .padding(.horizontal, CSSpace.xl)
                    }
                }
                .padding(.bottom, CSSpace.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }

    private static let pageRarities: [Rarity] = [.leggendaria, .rara, .epica, .rara, .epica]
    private var pageTint: Color { Self.pageRarities[page].primary }
    private var pageGradient: [Color] { Self.pageRarities[page].gradient }

    /// Salva la scelta (solo ora può partire qualcosa verso Mixpanel) e chiude l'onboarding.
    private func finish(with consent: AnalyticsConsent) {
        AppServices.analytics.setConsent(consent)
        AppServices.analytics.track(.onboardingCompleted)
        onFinished()
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

// MARK: - Pagina 4 · Consenso statistiche anonime

private struct ConsentPage: View {
    var body: some View {
        OnboardingScaffold(
            eyebrow: "PRIVACY",
            title: "Ci aiuti a\nmigliorare CarSpot?",
            subtitle: "Raccogliamo statistiche anonime d'uso: quali schermate usi e quante carte raccogli per rarità. Puoi cambiare idea quando vuoi in Profilo."
        ) {
            GlassPanel {
                VStack(alignment: .leading, spacing: CSSpace.md) {
                    row("eye.slash.fill", "Mai foto, targhe o posizione")
                    row("globe.europe.africa.fill", "Dati conservati in Europa")
                    row("slider.horizontal.3", "Modificabile in ogni momento")
                }
            }
            .padding(.horizontal, CSSpace.lg)
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: CSSpace.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CSColor.accent)
                .frame(width: 24)
            Text(text)
                .font(CSFont.body(14))
                .foregroundStyle(CSColor.ink)
            Spacer(minLength: 0)
        }
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

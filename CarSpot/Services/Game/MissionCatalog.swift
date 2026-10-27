import Foundation

/// Posto che un modello occupa nella lista di un periodo.
enum MissionSlot: String, Sendable {
    case volume, extra, variety, style, list
}

/// Parametro scelto dal generatore per i modelli parametrici.
enum MissionParamKind: String, Sendable {
    case decade, make
}

/// Parametri di una missione parametrica (decennio o marca); viaggiano nel riscatto.
struct MissionParams: Codable, Sendable, Hashable {
    var decade: Int? = nil
    var make: String? = nil
}

/// Modello di missione: regola + obiettivi per ritmo + premio. Gemello della tabella
/// `mission_templates` (migration 0011): i valori si cambiano in coppia.
struct MissionTemplate: Sendable {
    let id: String
    let kind: MissionPeriodKind
    let slot: MissionSlot
    let icon: String
    let rule: MissionRule
    /// [occasionale, abituale, cacciatore]
    let goals: [Int]
    let rewardBase: Int
    let rewardPerUnit: Int
    let rewardMax: Int
    /// Stili a cui il modello piace di più; vuoto = nessuno.
    let styles: Set<PlayerStyle>
    let badge: Bool
    let param: MissionParamKind?

    func goal(for pace: MissionPace) -> Int {
        goals[min(pace.index, goals.count - 1)]
    }

    func reward(goal: Int) -> Int {
        min(rewardMax, rewardBase + rewardPerUnit * goal)
    }

    /// Regola con i parametri applicati: decennio d → anni d...d+9, marca → lista marche.
    func rule(with params: MissionParams?) -> MissionRule {
        var result = rule
        if param == .decade, let decade = params?.decade {
            result.yearFrom = decade
            result.yearTo = decade + 9
        }
        if param == .make, let make = params?.make {
            result.makes = [MissionText.norm(make)]
        }
        return result
    }

    func title(goal: Int, params: MissionParams?) -> String {
        let one = goal == 1
        switch id {
        case "d_cards", "w_cards":
            return one ? String(localized: "Cattura un'auto") : String(localized: "Cattura \(goal) auto")
        case "d_rare", "w_rare":
            return one ? String(localized: "Una Rara o superiore") : String(localized: "\(goal) Rare o superiori")
        case "d_epic", "w_epic":
            return one ? String(localized: "Un'Epica o superiore") : String(localized: "\(goal) Epiche o superiori")
        case "d_vintage", "w_vintage", "m_vintage":
            return one ? String(localized: "Un'auto prima del 1990") : String(localized: "\(goal) auto prima del 1990")
        case "d_newarea":
            return one ? String(localized: "In un quartiere nuovo") : String(localized: "In \(goal) quartieri nuovi")
        case "d_makes", "w_makes", "m_makes":
            return one ? String(localized: "Una marca") : String(localized: "\(goal) marche diverse")
        case "d_newmodel":
            return one ? String(localized: "Un modello che non hai") : String(localized: "\(goal) modelli che non hai")
        case "d_power":
            return one ? String(localized: "Un'auto con 80+ di potenza") : String(localized: "\(goal) auto con 80+ di potenza")
        case "w_areas", "m_areas":
            return one ? String(localized: "Un quartiere") : String(localized: "\(goal) quartieri diversi")
        case "w_newmodels", "m_newmodels":
            return one ? String(localized: "Un modello nuovo") : String(localized: "\(goal) modelli nuovi")
        case "w_decade":
            let decade = params?.decade ?? 1970
            let label = decade < 2000 ? "'\(String(format: "%02ld", decade % 100))" : "\(decade)"
            return one ? String(localized: "Un'auto degli anni \(label)") : String(localized: "\(goal) auto degli anni \(label)")
        case "w_make":
            let make = params?.make ?? "Porsche"
            return one ? String(localized: "Un'auto di \(make)") : String(localized: "\(goal) auto di \(make)")
        case "m_list_icons":
            return one ? String(localized: "Un'icona anni '80 e '90") : String(localized: "\(goal) icone anni '80 e '90")
        case "m_list_hothatch":
            return one ? String(localized: "Una piccola cattiva") : String(localized: "\(goal) piccole cattive")
        case "m_list_italian":
            return one ? String(localized: "Una sportiva italiana") : String(localized: "\(goal) sportive italiane")
        case "m_list_german":
            return one ? String(localized: "Una sportiva tedesca") : String(localized: "\(goal) sportive tedesche")
        case "m_legend":
            return one ? String(localized: "Una Leggendaria") : String(localized: "\(goal) Leggendarie")
        default:
            return id
        }
    }
}

/// Repertorio delle missioni personali (tabelle "Giorno", "Settimana", "Mese" della spec).
enum MissionCatalog {
    static func template(id: String) -> MissionTemplate? {
        pool.first { $0.id == id }
    }

    /// Slot di ogni periodo, nell'ordine di estrazione.
    static func slots(for kind: MissionPeriodKind) -> [MissionSlot] {
        switch kind {
        case .day: [.volume, .extra, .extra]
        case .week: [.volume, .variety, .style]
        case .month: [.list, .style]
        case .community: []
        }
    }

    static let pool: [MissionTemplate] = day + week + month

    // MARK: - Giorno

    private static let day: [MissionTemplate] = [
        MissionTemplate(id: "d_cards", kind: .day, slot: .volume, icon: "camera.fill",
                        rule: MissionRule(), goals: [1, 3, 6],
                        rewardBase: 40, rewardPerUnit: 20, rewardMax: 160,
                        styles: [], badge: false, param: nil),
        MissionTemplate(id: "d_rare", kind: .day, slot: .extra, icon: "diamond.fill",
                        rule: MissionRule(minRarity: .rara), goals: [1, 1, 2],
                        rewardBase: 60, rewardPerUnit: 40, rewardMax: 140,
                        styles: [.rarity], badge: false, param: nil),
        MissionTemplate(id: "d_epic", kind: .day, slot: .extra, icon: "hexagon.fill",
                        rule: MissionRule(minRarity: .epica), goals: [1, 1, 1],
                        rewardBase: 130, rewardPerUnit: 0, rewardMax: 130,
                        styles: [.rarity], badge: false, param: nil),
        MissionTemplate(id: "d_vintage", kind: .day, slot: .extra, icon: "clock.arrow.circlepath",
                        rule: MissionRule(yearTo: 1989), goals: [1, 1, 2],
                        rewardBase: 70, rewardPerUnit: 40, rewardMax: 150,
                        styles: [.vintage], badge: false, param: nil),
        MissionTemplate(id: "d_newarea", kind: .day, slot: .extra, icon: "mappin.and.ellipse",
                        rule: MissionRule(fresh: .area), goals: [1, 1, 2],
                        rewardBase: 60, rewardPerUnit: 40, rewardMax: 140,
                        styles: [.explorer], badge: false, param: nil),
        MissionTemplate(id: "d_makes", kind: .day, slot: .extra, icon: "square.stack.3d.up.fill",
                        rule: MissionRule(count: .makes), goals: [2, 2, 3],
                        rewardBase: 40, rewardPerUnit: 30, rewardMax: 130,
                        styles: [.generalist], badge: false, param: nil),
        MissionTemplate(id: "d_newmodel", kind: .day, slot: .extra, icon: "sparkles",
                        rule: MissionRule(count: .models, fresh: .model), goals: [1, 1, 2],
                        rewardBase: 60, rewardPerUnit: 40, rewardMax: 140,
                        styles: [.generalist], badge: false, param: nil),
        MissionTemplate(id: "d_power", kind: .day, slot: .extra, icon: "bolt.fill",
                        rule: MissionRule(minPower: 80), goals: [1, 1, 2],
                        rewardBase: 70, rewardPerUnit: 40, rewardMax: 150,
                        styles: [.brand], badge: false, param: nil),
    ]

    // MARK: - Settimana

    private static let week: [MissionTemplate] = [
        MissionTemplate(id: "w_cards", kind: .week, slot: .volume, icon: "camera.fill",
                        rule: MissionRule(), goals: [5, 15, 40],
                        rewardBase: 150, rewardPerUnit: 10, rewardMax: 500,
                        styles: [], badge: false, param: nil),
        MissionTemplate(id: "w_makes", kind: .week, slot: .variety, icon: "square.stack.3d.up.fill",
                        rule: MissionRule(count: .makes), goals: [3, 5, 8],
                        rewardBase: 150, rewardPerUnit: 30, rewardMax: 400,
                        styles: [], badge: false, param: nil),
        MissionTemplate(id: "w_areas", kind: .week, slot: .variety, icon: "map.fill",
                        rule: MissionRule(count: .areas), goals: [2, 4, 6],
                        rewardBase: 150, rewardPerUnit: 40, rewardMax: 400,
                        styles: [.explorer], badge: false, param: nil),
        MissionTemplate(id: "w_newmodels", kind: .week, slot: .variety, icon: "sparkles",
                        rule: MissionRule(count: .models, fresh: .model), goals: [2, 5, 10],
                        rewardBase: 150, rewardPerUnit: 30, rewardMax: 450,
                        styles: [], badge: false, param: nil),
        MissionTemplate(id: "w_rare", kind: .week, slot: .style, icon: "diamond.fill",
                        rule: MissionRule(minRarity: .rara), goals: [2, 4, 8],
                        rewardBase: 150, rewardPerUnit: 30, rewardMax: 400,
                        styles: [.rarity], badge: false, param: nil),
        MissionTemplate(id: "w_epic", kind: .week, slot: .style, icon: "hexagon.fill",
                        rule: MissionRule(minRarity: .epica), goals: [1, 2, 3],
                        rewardBase: 200, rewardPerUnit: 100, rewardMax: 500,
                        styles: [.rarity], badge: false, param: nil),
        MissionTemplate(id: "w_vintage", kind: .week, slot: .style, icon: "clock.arrow.circlepath",
                        rule: MissionRule(yearTo: 1989), goals: [1, 3, 5],
                        rewardBase: 150, rewardPerUnit: 50, rewardMax: 400,
                        styles: [.vintage], badge: false, param: nil),
        MissionTemplate(id: "w_decade", kind: .week, slot: .style, icon: "calendar",
                        rule: MissionRule(), goals: [1, 2, 3],
                        rewardBase: 200, rewardPerUnit: 80, rewardMax: 450,
                        styles: [.vintage], badge: false, param: .decade),
        MissionTemplate(id: "w_make", kind: .week, slot: .style, icon: "car.fill",
                        rule: MissionRule(), goals: [2, 4, 6],
                        rewardBase: 150, rewardPerUnit: 40, rewardMax: 400,
                        styles: [.brand], badge: false, param: .make),
    ]

    // MARK: - Mese

    private static let month: [MissionTemplate] = [
        MissionTemplate(id: "m_list_icons", kind: .month, slot: .list, icon: "star.fill",
                        rule: MissionRule(count: .models, models: [
                            "ferrari|f40", "ferrari|testarossa", "lamborghini|countach", "porsche|959",
                            "bmw|m1", "lancia|delta integrale", "audi|quattro",
                        ]), goals: [1, 1, 2],
                        rewardBase: 750, rewardPerUnit: 250, rewardMax: 1250,
                        styles: [.rarity, .vintage], badge: true, param: nil),
        MissionTemplate(id: "m_list_hothatch", kind: .month, slot: .list, icon: "flame.fill",
                        rule: MissionRule(count: .models, models: [
                            "volkswagen|golf gti", "abarth|595", "peugeot|205 gti", "renault|clio rs",
                            "ford|fiesta st", "honda|civic type r", "mini|cooper s",
                        ]), goals: [1, 2, 3],
                        rewardBase: 600, rewardPerUnit: 200, rewardMax: 1200,
                        styles: [.generalist, .explorer], badge: true, param: nil),
        MissionTemplate(id: "m_list_italian", kind: .month, slot: .list, icon: "flag.fill",
                        rule: MissionRule(count: .models, models: [
                            "alfa romeo|giulia quadrifoglio", "alfa romeo|4c", "maserati|mc20",
                            "lamborghini|huracan", "ferrari|296", "ferrari|roma",
                        ]), goals: [1, 1, 2],
                        rewardBase: 750, rewardPerUnit: 250, rewardMax: 1250,
                        styles: [.brand, .rarity], badge: true, param: nil),
        MissionTemplate(id: "m_list_german", kind: .month, slot: .list, icon: "flag.fill",
                        rule: MissionRule(count: .models, models: [
                            "porsche|911", "bmw|m3", "bmw|m4", "audi|rs", "mercedes-benz|amg",
                        ]), goals: [1, 2, 3],
                        rewardBase: 600, rewardPerUnit: 200, rewardMax: 1200,
                        styles: [.brand, .generalist], badge: true, param: nil),
        MissionTemplate(id: "m_newmodels", kind: .month, slot: .style, icon: "sparkles",
                        rule: MissionRule(count: .models, fresh: .model), goals: [8, 20, 50],
                        rewardBase: 600, rewardPerUnit: 15, rewardMax: 1500,
                        styles: [.generalist], badge: true, param: nil),
        MissionTemplate(id: "m_areas", kind: .month, slot: .style, icon: "map.fill",
                        rule: MissionRule(count: .areas), goals: [4, 8, 15],
                        rewardBase: 600, rewardPerUnit: 50, rewardMax: 1500,
                        styles: [.explorer], badge: true, param: nil),
        MissionTemplate(id: "m_legend", kind: .month, slot: .style, icon: "crown.fill",
                        rule: MissionRule(minRarity: .leggendaria), goals: [1, 1, 2],
                        rewardBase: 900, rewardPerUnit: 300, rewardMax: 1500,
                        styles: [.rarity], badge: true, param: nil),
        MissionTemplate(id: "m_vintage", kind: .month, slot: .style, icon: "clock.arrow.circlepath",
                        rule: MissionRule(yearTo: 1989), goals: [3, 8, 15],
                        rewardBase: 600, rewardPerUnit: 40, rewardMax: 1200,
                        styles: [.vintage], badge: true, param: nil),
        MissionTemplate(id: "m_makes", kind: .month, slot: .style, icon: "square.stack.3d.up.fill",
                        rule: MissionRule(count: .makes), goals: [6, 12, 20],
                        rewardBase: 600, rewardPerUnit: 40, rewardMax: 1400,
                        styles: [.brand, .generalist], badge: true, param: nil),
    ]
}

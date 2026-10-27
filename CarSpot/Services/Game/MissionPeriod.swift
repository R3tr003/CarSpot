import Foundation

enum MissionPeriodKind: String, Codable, Sendable, CaseIterable {
    case day, week, month, community
}

extension Calendar {
    /// Calendario delle missioni: gregoriano, settimana da lunedì, ora del telefono.
    static var missions: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = .current
        return calendar
    }
}

/// Periodo di una missione (giorno, settimana, mese di calendario o finestra di una comune).
struct MissionPeriod: Sendable, Hashable {
    let kind: MissionPeriodKind
    let start: Date
    /// Esclusiva.
    let end: Date
    /// "yyyy-MM-dd" nel fuso del calendario.
    let startKey: String
    /// Fine del periodo + 2 giorni di calendario: oltre, il riscatto è perso.
    let claimDeadline: Date

    init(kind: MissionPeriodKind, start: Date, end: Date, calendar: Calendar) {
        self.kind = kind
        self.start = start
        self.end = end
        self.startKey = Self.key(start, calendar: calendar)
        self.claimDeadline = calendar.date(byAdding: .day, value: 2, to: end) ?? end.addingTimeInterval(2 * 86_400)
    }

    /// Periodo personale (giorno, settimana, mese) che contiene `date`.
    static func containing(_ date: Date, kind: MissionPeriodKind, calendar: Calendar) -> MissionPeriod {
        let dayStart = calendar.startOfDay(for: date)
        switch kind {
        case .day, .community:
            let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            return MissionPeriod(kind: kind, start: dayStart, end: end, calendar: calendar)
        case .week:
            let weekday = calendar.component(.weekday, from: date)
            let offset = (weekday - calendar.firstWeekday + 7) % 7
            let start = calendar.date(byAdding: .day, value: -offset, to: dayStart) ?? dayStart
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
            return MissionPeriod(kind: kind, start: start, end: end, calendar: calendar)
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: parts) ?? dayStart
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(30 * 86_400)
            return MissionPeriod(kind: kind, start: start, end: end, calendar: calendar)
        }
    }

    /// Periodo subito prima (giorno, settimana, mese). Per le comuni non esiste: restituisce se stesso.
    func previous(calendar: Calendar) -> MissionPeriod {
        let before: Date?
        switch kind {
        case .day: before = calendar.date(byAdding: .day, value: -1, to: start)
        case .week: before = calendar.date(byAdding: .day, value: -7, to: start)
        case .month: before = calendar.date(byAdding: .month, value: -1, to: start)
        case .community: return self
        }
        return Self.containing(before ?? start.addingTimeInterval(-86_400), kind: kind, calendar: calendar)
    }

    /// Comune: date incluse "yyyy-MM-dd" → [startsOn 00:00, endsOn + 1 giorno 00:00). nil se non valide.
    static func community(startsOn: String, endsOn: String, calendar: Calendar) -> MissionPeriod? {
        guard let first = parse(startsOn, calendar: calendar),
              let last = parse(endsOn, calendar: calendar), last >= first,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
        return MissionPeriod(kind: .community, start: first, end: end, calendar: calendar)
    }

    /// Identità del riscatto: "week:2026-10-19|w_makes".
    func identity(_ missionId: String) -> String {
        "\(kind.rawValue):\(startKey)|\(missionId)"
    }

    // MARK: - Date

    private static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Mezzanotte locale di "yyyy-MM-dd"; nil se il formato o la data non esistono (es. 2026-02-31).
    private static func parse(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}

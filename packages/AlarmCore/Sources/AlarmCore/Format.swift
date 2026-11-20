import Foundation

public enum AlarmFormat {
    /// Compact Italian duration: "< 1 min", "45 min", "2 h 14 min", "3 g 4 h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let minutes = s / 60
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let restMin = minutes % 60
        if hours < 24 { return restMin == 0 ? "\(hours) h" : "\(hours) h \(restMin) min" }
        let days = hours / 24
        let restH = hours % 24
        return restH == 0 ? "\(days) g" : "\(days) g \(restH) h"
    }

    public static func percent(_ value: Double) -> String {
        let p = max(0, min(1, value)) * 100
        if p > 0 && p < 1 { return "< 1%" }
        return "\(Int(p.rounded()))%"
    }

    public static func hour(_ h: Int) -> String {
        String(format: "%02d:00", h)
    }

    /// CSV (semicolon separated, Excel-friendly in Italy) of the events.
    public static func csv(_ data: AlarmData, timeZone: TimeZone = .current) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.timeZone = timeZone
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func esc(_ s: String) -> String {
            if s.contains(";") || s.contains("\"") || s.contains("\n") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        var lines = ["Data;Casa;Comando;Zona;Esito;Origine;Messaggio"]
        for e in data.eventsNewestFirst {
            let house = data.houses.first { $0.id == e.houseID }?.name ?? "Casa eliminata"
            let zone = data.houses.first { $0.id == e.houseID }?.zone(e.zoneID)?.name ?? e.zoneName ?? ""
            lines.append([df.string(from: e.date), house, e.kind.label, zone, e.result.label, e.source.label, e.message].map(esc).joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

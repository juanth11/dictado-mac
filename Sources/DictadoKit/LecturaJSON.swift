import Foundation

// Lo común de las lecturas JSON del Centro (consumo, herramientas, automatizaciones, finanzas y noticias): campos tolerantes (un
// tipo que no es el esperado se trata como ausente, nunca como cero) y fechas ISO 8601 con o sin fracción de segundo.

enum LecturaJSON {
    static func objeto(_ datos: Data) -> [String: Any]? {
        guard let crudo = try? JSONSerialization.jsonObject(with: datos), let d = crudo as? [String: Any] else { return nil }
        if d["ok"] as? Bool == false { return nil }
        return d
    }

    static func texto(_ v: Any?) -> String? {
        guard let t = v as? String else { return nil }
        let limpio = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return limpio.isEmpty ? nil : limpio
    }

    static func entero(_ v: Any?) -> Int? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        return nil
    }

    static func decimal(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        return nil
    }

    static func booleano(_ v: Any?) -> Bool? {
        if let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
        return nil
    }

    static func fecha(_ iso: Any?) -> Date? {
        guard let iso = iso as? String, !iso.isEmpty else { return nil }
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime]
        if let d = a.date(from: iso) { return d }
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return a.date(from: iso)
    }

    /// "2026-11-16" como el inicio de ese día en la zona del calendario.
    static func dia(_ texto: String?, calendario: Calendar = .current) -> Date? {
        guard let texto, texto.count >= 10 else { return nil }
        let p = texto.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendario.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}

/// "hace 20 min", "hace 3 h", "hace 5 d": lo transcurrido hasta `ahora`, en palabras cortas.
public enum TextoTiempo {
    public static func hace(_ fecha: Date, _ ahora: Date) -> String {
        let s = Int(ahora.timeIntervalSince(fecha))
        if s < 60 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 48 * 3600 { return "hace \(s / 3600) h" }
        return "hace \(s / 86_400) d"
    }

    /// "16 nov" (con el calendario dado).
    public static func diaCorto(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.day, .month], from: fecha)
        return "\(c.day ?? 1) \(NombresFecha.mesesCortos[((c.month ?? 1) - 1) % 12].lowercased())"
    }

    /// "lun 16" para una fecha.
    public static func diaSemana(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.weekday, .day], from: fecha)
        return "\(NombresFecha.diasCortos[((c.weekday ?? 1) - 1) % 7].lowercased()) \(c.day ?? 1)"
    }

    /// "a las 5:30 a. m." no: la hora de 24 h, "05:30".
    public static func hora(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.hour, .minute], from: fecha)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

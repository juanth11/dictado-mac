import Foundation

/// Una tarea de la lista única del centro (`python3 -m centro tarea listar --json`).
public struct TareaCentro: Equatable, Sendable, Identifiable {
    public var id: Int
    public var texto: String
    public var origen: String
    public var ref: String?
    public var cita: String?
    /// AAAA-MM-DD.
    public var vence: String?
    public var estado: String
    /// ISO 8601; solo las cerradas la traen.
    public var cerrada: String?

    public init(id: Int, texto: String, origen: String = "manual", ref: String? = nil, cita: String? = nil, vence: String? = nil,
                estado: String = "abierta", cerrada: String? = nil) {
        self.id = id
        self.texto = texto
        self.origen = origen
        self.ref = ref
        self.cita = cita
        self.vence = vence
        self.estado = estado
        self.cerrada = cerrada
    }

    public var abierta: Bool { estado == "abierta" }
}

public enum TareasCentro {
    /// Lee lo que imprime `tarea listar --json`: una lista de objetos. Un objeto con `"ok": false` (el centro rechazó el
    /// comando) o cualquier cosa que no sea una lista devuelve nil; una tarea mal formada se salta y las demás siguen.
    public static func decodificar(_ datos: Data) -> [TareaCentro]? {
        guard let crudo = try? JSONSerialization.jsonObject(with: datos), let lista = crudo as? [[String: Any]] else { return nil }
        func texto(_ d: [String: Any], _ clave: String) -> String? {
            guard let t = d[clave] as? String else { return nil }
            let limpio = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return limpio.isEmpty ? nil : limpio
        }
        return lista.compactMap { d in
            let id = (d["id"] as? Int) ?? (d["id"] as? Double).map(Int.init)
            guard let id, let t = texto(d, "texto") else { return nil }
            return TareaCentro(id: id, texto: t, origen: texto(d, "origen") ?? "manual", ref: texto(d, "ref"), cita: texto(d, "cita"),
                               vence: texto(d, "vence"), estado: texto(d, "estado") ?? "abierta", cerrada: texto(d, "cerrada"))
        }
    }

    /// De dónde viene, en palabras: la reunión (su `ref`) o el canal.
    public static func origen(_ t: TareaCentro) -> String {
        if let ref = t.ref, !ref.isEmpty, t.origen == "reunion" { return ref }
        switch t.origen {
        case "reunion": return "Reunión"
        case "dictado": return "Dictado"
        case "telegram": return "Telegram"
        default: return "Manual"
        }
    }

    private static let cortos = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]

    /// "vence hoy", "vence mañana", "vence vie 20", "venció ayer", "venció hace 3 días"; nil si no tiene fecha.
    public static func vencimiento(_ vence: String?, ahora: Date, calendario: Calendar = .current) -> String? {
        guard let vence, let fecha = dia(vence, calendario: calendario) else { return nil }
        let hoy = calendario.startOfDay(for: ahora)
        let d = calendario.dateComponents([.day], from: hoy, to: fecha).day ?? 0
        switch d {
        case 0: return "vence hoy"
        case 1: return "vence mañana"
        case -1: return "venció ayer"
        case ..<(-1): return "venció hace \(-d) días"
        default:
            let c = calendario.dateComponents([.weekday, .day], from: fecha)
            return "vence \(cortos[(c.weekday ?? 1) - 1]) \(c.day ?? 0)"
        }
    }

    /// "Comité · vence mañana": el rótulo de la tarjeta.
    public static func rotulo(_ t: TareaCentro, ahora: Date, calendario: Calendar = .current) -> String {
        [origen(t), vencimiento(t.vence, ahora: ahora, calendario: calendario)].compactMap { $0 }.joined(separator: " · ")
    }

    /// Las abiertas primero las que vencen antes (las que no tienen fecha, al final), y por id.
    public static func ordenar(_ tareas: [TareaCentro]) -> [TareaCentro] {
        tareas.filter(\.abierta).sorted {
            switch ($0.vence, $1.vence) {
            case let (a?, b?): return a == b ? $0.id < $1.id : a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.id < $1.id
            }
        }
    }

    /// El día: cuántas quedan abiertas y cuántas se cerraron hoy como hechas (el dial "N de M").
    public static func resumenDelDia(_ tareas: [TareaCentro], ahora: Date, calendario: Calendar = .current) -> (hechas: Int, total: Int) {
        let abiertas = tareas.filter(\.abierta).count
        let hechas = tareas.filter { t in
            guard t.estado == "hecha", let c = t.cerrada, let f = ISO8601DateFormatter().date(from: c) ?? fechaSinZona(c, calendario) else { return false }
            return calendario.isDate(f, inSameDayAs: ahora)
        }.count
        return (hechas, hechas + abiertas)
    }

    private static func dia(_ s: String, calendario: Calendar) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendario.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// El centro escribe `2026-11-15T09:30:00` sin zona: se toma como hora local.
    private static func fechaSinZona(_ s: String, _ calendario: Calendar) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendario
        f.timeZone = calendario.timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }
}

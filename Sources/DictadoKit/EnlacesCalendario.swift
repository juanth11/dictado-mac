import Foundation

/// Textos y enlaces de la agenda: la disponibilidad lista para pegar y las URL de Google Calendar.
public enum FormatoHuecos {
    private static let dias = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    private static let diasCortos = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                                "octubre", "noviembre", "diciembre"]

    /// "3:00" y "p. m." por separado (formato de 12 horas; 12:00 es p. m., 0:30 es "12:30 a. m.").
    public static func hora(_ fecha: Date, calendario: Calendar = .current) -> (texto: String, periodo: String) {
        let c = calendario.dateComponents([.hour, .minute], from: fecha)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        return ("\(h12):" + (m < 10 ? "0\(m)" : "\(m)"), h < 12 ? "a. m." : "p. m.")
    }

    /// "3:00-4:30 p. m." o, si cruza el mediodía, "11:00 a. m.-1:00 p. m.".
    public static func rango(_ i: Intervalo, calendario: Calendar = .current) -> String {
        let a = hora(i.inicio, calendario: calendario), b = hora(i.fin, calendario: calendario)
        return a.periodo == b.periodo ? "\(a.texto)-\(b.texto) \(b.periodo)" : "\(a.texto) \(a.periodo)-\(b.texto) \(b.periodo)"
    }

    /// "mar 3:00-4:30 p. m." (o "hoy 3:00-4:30 p. m." si es hoy respecto a `ahora`).
    public static func corto(_ i: Intervalo, ahora: Date, calendario: Calendar = .current) -> String {
        let dia = calendario.isDate(i.inicio, inSameDayAs: ahora)
            ? "hoy" : diasCortos[calendario.component(.weekday, from: i.inicio) - 1]
        return "\(dia) \(rango(i, calendario: calendario))"
    }

    /// "martes 18 de 3:00 a 4:30 p. m." / "miércoles 19 de 11:00 a. m. a 1:00 p. m.".
    public static func enFrase(_ i: Intervalo, calendario: Calendar = .current) -> String {
        let a = hora(i.inicio, calendario: calendario), b = hora(i.fin, calendario: calendario)
        let dia = dias[calendario.component(.weekday, from: i.inicio) - 1] + " \(calendario.component(.day, from: i.inicio))"
        let horas = a.periodo == b.periodo ? "\(a.texto) a \(b.texto) \(b.periodo)" : "\(a.texto) \(a.periodo) a \(b.texto) \(b.periodo)"
        return "\(dia) de \(horas)"
    }

    /// El texto para pegar en un correo o chat: los primeros `maximo` huecos.
    public static func disponibilidad(_ huecos: [Intervalo], maximo: Int = 5, calendario: Calendar = .current) -> String {
        guard !huecos.isEmpty, maximo > 0 else { return "No tengo disponibilidad en los próximos días laborales." }
        let texto = "Tengo disponibilidad: " + huecos.prefix(maximo).map { enFrase($0, calendario: calendario) }.joined(separator: "; ")
        return texto.hasSuffix(".") ? texto : texto + "."  // "p. m." ya termina en punto
    }

    /// "mar 18 de noviembre".
    public static func dia(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.weekday, .day, .month], from: fecha)
        return "\(diasCortos[(c.weekday ?? 1) - 1]) \(c.day ?? 0) de \(meses[(c.month ?? 1) - 1])"
    }
}

public enum EnlacesCalendario {
    private static let permitidos = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func codificar(_ texto: String) -> String {
        texto.addingPercentEncoding(withAllowedCharacters: permitidos) ?? ""
    }

    /// "20261117T200000Z": la fecha en UTC, que Google convierte a tu zona sin ambigüedad.
    static func utc(_ fecha: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fecha)
        func dos(_ n: Int?) -> String { let v = n ?? 0; return v < 10 ? "0\(v)" : "\(v)" }
        return "\(c.year ?? 0)" + dos(c.month) + dos(c.day) + "T" + dos(c.hour) + dos(c.minute) + dos(c.second) + "Z"
    }

    /// La página de "nuevo evento" de Google Calendar con la franja y el título ya puestos. No crea nada: solo la abre.
    public static func nuevoEvento(inicio: Date, duracionMin: Int = 30, titulo: String = "Reunión", cuenta: String? = nil,
                                   invitados: [String] = [], detalles: String? = nil) -> URL? {
        let fin = inicio.addingTimeInterval(Double(max(1, duracionMin)) * 60)
        var url = "https://calendar.google.com/calendar/render?action=TEMPLATE&dates=\(utc(inicio))/\(utc(fin))&text=\(codificar(titulo))"
        let correos = invitados.filter { $0.contains("@") }
        if !correos.isEmpty { url += "&add=" + correos.map(codificar).joined(separator: ",") }
        if let detalles, !detalles.isEmpty { url += "&details=\(codificar(detalles))" }
        if let cuenta, cuenta.contains("@") { url += "&authuser=\(codificar(cuenta))" }
        return URL(string: url)
    }

    /// La vista de un día: https://calendar.google.com/calendar/r/day/2026/11/17
    public static func dia(_ fecha: Date, calendario: Calendar = .current, cuenta: String? = nil) -> URL? {
        let c = calendario.dateComponents([.year, .month, .day], from: fecha)
        var url = "https://calendar.google.com/calendar/r/day/\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
        if let cuenta, cuenta.contains("@") { url += "?authuser=\(codificar(cuenta))" }
        return URL(string: url)
    }

    /// El enlace directo a un evento de Google: `eid` es base64 sin relleno de "<id del evento> <correo del calendario>".
    /// Solo se arma cuando el UID que da Calendario es el de Google ("<id>@google.com") y se conoce el correo del
    /// calendario; con cualquier otro UID (eventos importados, otros servidores) devuelve nil y se abre el día.
    public static func eventoGoogle(uid: String?, calendario: String?, cuenta: String? = nil) -> URL? {
        guard let uid, uid.lowercased().hasSuffix("@google.com"), let calendario, calendario.contains("@"), !calendario.contains(" ")
        else { return nil }
        let id = String(uid.dropLast("@google.com".count))
        guard !id.isEmpty, !id.contains(" ") else { return nil }
        let eid = Data("\(id) \(calendario)".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var url = "https://calendar.google.com/calendar/event?eid=\(eid)"
        if let cuenta, cuenta.contains("@") { url += "&authuser=\(codificar(cuenta))" }
        return URL(string: url)
    }
}

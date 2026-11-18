import Foundation

// La lógica pura de la sección Hoy del Centro (la vista de la mañana): qué sección abre el Centro según la hora, si un archivo del día es de hoy,
// qué correos se muestran y cuántos faltan, cómo se dice "hace 3 h", a qué bandeja de Gmail lleva el botón y en qué momento está cada cita.
// La vista (SwiftUI) solo dibuja lo que esto decide.

public enum HoyCentro {
    /// Antes del mediodía (hora local) el Centro abre en Hoy; después, en la sección de siempre.
    public static func abreEnHoy(ahora: Date, calendario: Calendar = .current) -> Bool {
        calendario.component(.hour, from: ahora) < 12
    }

    /// ¿Esa fecha ("2026-11-16", o una marca ISO que empiece por ella) es el día de `ahora`? Nil o vacío: no.
    public static func esDeHoy(_ fechaIso: String?, ahora: Date, calendario: Calendar = .current) -> Bool {
        guard let dia = fechaIso?.prefix(10), dia.count == 10 else { return false }
        let c = calendario.dateComponents([.year, .month, .day], from: ahora)
        return String(dia) == String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "de hoy", "de ayer", "de hace 3 días" para un archivo que trae su día (nil si no se sabe o es del futuro).
    public static func frescura(dia: Date?, ahora: Date, calendario: Calendar = .current) -> String? {
        guard let dia else { return nil }
        let d = calendario.dateComponents([.day], from: calendario.startOfDay(for: dia), to: calendario.startOfDay(for: ahora)).day ?? 0
        if d < 0 { return nil }
        if d == 0 { return "de hoy" }
        return d == 1 ? "de ayer" : "de hace \(d) días"
    }

    // MARK: Correos

    public struct Correo: Equatable, Sendable {
        public var de: String
        public var asunto: String
        public var fecha: Date?
        public var sinLeer: Bool
        public var enlace: String?

        public init(de: String, asunto: String, fecha: Date? = nil, sinLeer: Bool = false, enlace: String? = nil) {
            self.de = de
            self.asunto = asunto
            self.fecha = fecha
            self.sinLeer = sinLeer
            self.enlace = enlace
        }
    }

    /// Los correos que caben: primero los sin leer, y dentro de cada grupo el más reciente primero (los sin fecha, al final). `faltan` = los que
    /// la lectura dice que hay (`total`, que puede ser mayor que la lista) y no se muestran.
    public static func correosAMostrar(_ lista: [Correo], total: Int?, maximo: Int) -> (visibles: [Correo], faltan: Int) {
        let ordenados = lista.enumerated().sorted { a, b in
            if a.element.sinLeer != b.element.sinLeer { return a.element.sinLeer }
            switch (a.element.fecha, b.element.fecha) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
        let visibles = Array(ordenados.prefix(max(0, maximo)))
        return (visibles, max(0, max(total ?? 0, lista.count) - visibles.count))
    }

    /// "ahora", "hace 12 min", "hace 3 h", "ayer", "hace 3 d".
    public static func hace(_ fecha: Date, ahora: Date) -> String {
        let s = Int(ahora.timeIntervalSince(fecha))
        if s < 60 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 24 * 3600 { return "hace \(s / 3600) h" }
        if s < 48 * 3600 { return "ayer" }
        return "hace \(s / 86_400) d"
    }

    /// A dónde lleva "Abrir Gmail": la bandeja de la MISMA cuenta de los enlaces de los correos (`…/mail/u/2/#inbox`); sin enlaces, la bandeja a secas.
    public static func enlaceBandeja(_ enlaces: [String?]) -> String {
        let base = "https://mail.google.com/mail/"
        for e in enlaces.compactMap({ $0 }) {
            guard e.hasPrefix(base), let marca = e.range(of: "/mail/u/") else { continue }
            let resto = e[marca.upperBound...]
            if let fin = resto.firstIndex(where: { $0 == "/" || $0 == "#" || $0 == "?" }), fin != resto.startIndex {
                return base + "u/" + resto[resto.startIndex..<fin] + "/#inbox"
            }
        }
        return base + "#inbox"
    }

    // MARK: Agenda

    public struct Cita: Equatable, Sendable {
        public var titulo: String
        public var inicio: Date
        public var fin: Date
        public var todoElDia: Bool
        public var lugar: String?
        public var videollamada: Bool
        public var invitados: Int

        public init(titulo: String, inicio: Date, fin: Date, todoElDia: Bool = false, lugar: String? = nil, videollamada: Bool = false, invitados: Int = 0) {
            self.titulo = titulo
            self.inicio = inicio
            self.fin = fin
            self.todoElDia = todoElDia
            self.lugar = lugar
            self.videollamada = videollamada
            self.invitados = invitados
        }
    }

    public enum Momento: Equatable, Sendable { case paso, enCurso, luego }

    /// Si ya pasó, está pasando o falta.
    public static func momento(_ c: Cita, ahora: Date) -> Momento {
        if c.fin <= ahora { return .paso }
        return c.inicio <= ahora ? .enCurso : .luego
    }

    /// "Unirse" aparece desde 10 minutos antes y mientras dura la reunión, y solo si hay enlace (la misma regla de la isla, pero con el reloj del Centro).
    public static func puedeUnirse(inicio: Date, fin: Date, conEnlace: Bool, ahora: Date) -> Bool {
        conEnlace && inicio.timeIntervalSince(ahora) <= 10 * 60 && fin > ahora
    }

    /// Las citas de HOY (las que empiezan el día de `ahora`; las de todo el día aparte) en orden de hora. Sin duplicados por título y hora.
    public static func delDia(_ citas: [Cita], ahora: Date, calendario: Calendar = .current) -> (conHora: [Cita], todoElDia: [Cita]) {
        var vistas = Set<String>()
        let hoy = citas.filter { calendario.isDate($0.inicio, inSameDayAs: ahora) }.filter {
            vistas.insert("\($0.titulo)|\($0.inicio.timeIntervalSince1970)|\($0.todoElDia)").inserted
        }
        return (hoy.filter { !$0.todoElDia }.sorted { ($0.inicio, $0.titulo) < ($1.inicio, $1.titulo) }, hoy.filter(\.todoElDia).sorted { $0.titulo < $1.titulo })
    }

    /// "Reunión · 3 invitados", "Videollamada", "Oficina"… la segunda línea de una cita (vacía si no hay nada que decir).
    public static func detalle(_ c: Cita) -> String {
        var p: [String] = []
        if let l = c.lugar?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { p.append(l) }
        if c.invitados > 0 { p.append(c.invitados == 1 ? "1 invitado" : "\(c.invitados) invitados") }
        if c.videollamada && p.isEmpty { p.append("Videollamada") }
        return p.joined(separator: " · ")
    }
}

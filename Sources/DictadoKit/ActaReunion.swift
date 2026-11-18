import Foundation

// Las notas de reunión que el sistema ya genera (`_inbox/reunion-*.md`, de Dictado o de Meet), leídas para el Centro. Solo
// lectura de un texto: el frontmatter (`date`, `source`, `reunion`…), el resumen de arriba y las secciones `## Decisiones`,
// `## Pendientes` (con la cita en la línea de abajo), `## Descartado` y `## Correo de seguimiento (borrador)`. Lo demás
// (la bitácora, la transcripción) se ignora. Tolerante: una sección que falta o una línea rara no tumban la nota.

public struct ActaReunion: Equatable, Sendable, Identifiable {
    public enum Fuente: String, Sendable {
        case dictado, meet, otra

        public var nombre: String {
            switch self {
            case .dictado: return "Dictado"
            case .meet: return "Meet"
            case .otra: return "Notas"
            }
        }
    }

    /// Un pendiente de la nota: `- [ ] Tú · qué · cuándo · si: gatillo` y, en la línea de abajo, `> «cita»`.
    public struct Tarea: Equatable, Sendable {
        public var texto: String
        public var cuando: String?
        public var gatillo: String?
        public var cita: String?
        public var hecha: Bool
        public var dueno: String

        /// Es del dueño del sistema: su nombre (`Dueno.nombre`), "Tú" o sin dueño claro ("¿?"), como filtra `Pendientes`.
        public var esMia: Bool {
            Dueno.esMio(dueno)
        }
    }

    /// El nombre del archivo.
    public var id: String
    public var titulo: String
    public var fecha: Date?
    public var fuente: Fuente
    public var resumen: String
    public var decisiones: [String]
    public var tareas: [Tarea]
    public var descartado: [String]
    /// El texto del borrador del correo de seguimiento, sin la cerca de código. nil si la nota no trae uno.
    public var correo: String?
    /// Si el calendario tenía otro nombre para esa hora.
    public var evento: String?
    /// La ruta de la transcripción completa (`transcripcion:` del frontmatter), si la nota la trae.
    public var transcripcion: String? = nil

    /// Tus pendientes (los de otros que se hayan colado no cuentan).
    public var tareasMias: [Tarea] { tareas.filter(\.esMia) }
    public var cuentaTareas: Int { tareasMias.count }
}

public enum LectorActa {
    /// Las primeras `maximo` frases del resumen (para que la nota no se vuelva un muro de texto). Si el texto ya cabe, se devuelve igual.
    public static func frases(_ texto: String, maximo: Int = 3) -> String {
        let limpio = texto.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        var corte: [String] = []
        var actual = ""
        for c in limpio {
            actual.append(c)
            if ".!?".contains(c) {
                corte.append(actual.trimmingCharacters(in: .whitespaces))
                actual = ""
            }
        }
        let resto = actual.trimmingCharacters(in: .whitespaces)
        if !resto.isEmpty { corte.append(resto) }
        return corte.count <= maximo ? limpio : corte.prefix(maximo).joined(separator: " ")
    }

    /// Interpreta el texto de una nota. nil si no es una nota de reunión (sin título y sin nada que mostrar).
    public static func interpretar(_ texto: String, archivo: String) -> ActaReunion? {
        let (meta, cuerpo) = frontmatter(texto)
        var titulo = meta["reunion"] ?? ""
        var secciones: [(nombre: String, lineas: [String])] = [("", [])]
        var enCerca = false
        for linea in cuerpo.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if linea.trimmingCharacters(in: .whitespaces).hasPrefix("```") { enCerca.toggle() }
            if !enCerca, linea.hasPrefix("## ") {
                secciones.append((String(linea.dropFirst(3)).trimmingCharacters(in: .whitespaces), []))
                continue
            }
            if !enCerca, linea.hasPrefix("# ") {
                if titulo.isEmpty { titulo = String(linea.dropFirst(2)).replacingOccurrences(of: "Notas · ", with: "").trimmingCharacters(in: .whitespaces) }
                continue
            }
            secciones[secciones.count - 1].lineas.append(linea)
        }
        func seccion(_ prefijo: String) -> [String]? {
            secciones.first { $0.nombre.lowercased().hasPrefix(prefijo.lowercased()) }?.lineas
        }
        func vinetas(_ lineas: [String]?) -> [String] {
            (lineas ?? []).compactMap { l in
                let t = l.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("- ") else { return nil }
                let v = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
        }

        var evento: String?
        var parrafos: [String] = []
        var actual: [String] = []
        func cerrar() {
            let p = actual.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !p.isEmpty {
                if p.hasPrefix("A esa hora el calendario tenía «"), let a = p.firstIndex(of: "«"), let b = p.firstIndex(of: "»"), a < b {
                    evento = String(p[p.index(after: a)..<b])
                } else {
                    parrafos.append(p)
                }
            }
            actual = []
        }
        for l in secciones[0].lineas {
            if l.trimmingCharacters(in: .whitespaces).isEmpty { cerrar() } else { actual.append(l.trimmingCharacters(in: .whitespaces)) }
        }
        cerrar()
        // El aviso de "Sin resumen automático (…)" no es un resumen: se deja vacío para que la vista diga que no hay.
        let resumen = parrafos.filter { !$0.hasPrefix("Sin resumen automático") }.joined(separator: "\n\n")

        let tareas = leerTareas(seccion("Pendientes") ?? [])
        let decisiones = vinetas(seccion("Decisiones"))
        let descartado = vinetas(seccion("Descartado"))
        let correo = seccion("Correo de seguimiento").flatMap(cercaDeCodigo)
        guard !titulo.isEmpty || !resumen.isEmpty || !tareas.isEmpty else { return nil }
        let origen = (meta["source"] ?? "").lowercased()
        let fuente: ActaReunion.Fuente = origen.hasPrefix("dictado") ? .dictado : (origen.hasPrefix("meet") ? .meet : .otra)
        return ActaReunion(id: archivo, titulo: titulo.isEmpty ? archivo : titulo, fecha: meta["date"].flatMap(fecha), fuente: fuente, resumen: resumen,
                           decisiones: decisiones, tareas: tareas, descartado: descartado, correo: correo, evento: evento ?? meta["evento"],
                           transcripcion: meta["transcripcion"].flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Las más recientes primero; las que no traen fecha, al final.
    public static func ordenar(_ actas: [ActaReunion]) -> [ActaReunion] {
        actas.sorted { a, b in
            switch (a.fecha, b.fecha) {
            case let (x?, y?): return x == y ? a.id > b.id : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id > b.id
            }
        }
    }

    // MARK: Piezas

    static func frontmatter(_ texto: String) -> ([String: String], String) {
        guard texto.hasPrefix("---"), let fin = texto.range(of: "\n---", range: texto.index(texto.startIndex, offsetBy: 3)..<texto.endIndex) else { return ([:], texto) }
        var meta: [String: String] = [:]
        for linea in texto[texto.index(texto.startIndex, offsetBy: 3)..<fin.lowerBound].split(separator: "\n") {
            guard let dos = linea.firstIndex(of: ":") else { continue }
            meta[String(linea[..<dos]).trimmingCharacters(in: .whitespaces)] = String(linea[linea.index(after: dos)...]).trimmingCharacters(in: .whitespaces)
        }
        return (meta, String(texto[fin.upperBound...]))
    }

    /// `2026-11-16T14:45-05:00` (el formato de las notas) o con segundos.
    static func fecha(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for formato in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"] {
            f.dateFormat = formato
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func leerTareas(_ lineas: [String]) -> [ActaReunion.Tarea] {
        var salida: [ActaReunion.Tarea] = []
        for linea in lineas {
            let t = linea.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(">"), !salida.isEmpty {
                var cita = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
                if cita.hasPrefix("«") { cita.removeFirst() }
                if cita.hasSuffix("»") { cita.removeLast() }
                if salida[salida.count - 1].cita == nil, !cita.isEmpty { salida[salida.count - 1].cita = cita }
                continue
            }
            let hecha = t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ")
            guard t.hasPrefix("- [ ] ") || hecha else { continue }
            var partes = t.dropFirst(6).components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard partes.count >= 2 else { continue }
            let dueno = partes.removeFirst()
            if let ultima = partes.last, ultima.hasPrefix("("), ultima.hasSuffix(")") { partes.removeLast() }
            let gatillo = partes.first { $0.lowercased().hasPrefix("si:") }.map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            partes.removeAll { $0.lowercased().hasPrefix("si:") }
            guard let que = partes.first else { continue }
            salida.append(ActaReunion.Tarea(texto: que, cuando: partes.dropFirst().first, gatillo: gatillo, cita: nil, hecha: hecha, dueno: dueno))
        }
        return salida
    }

    /// El contenido de la primera cerca de código de la sección (entre las líneas con ```), sin los espacios de los bordes.
    private static func cercaDeCodigo(_ lineas: [String]) -> String? {
        var dentro = false
        var cuerpo: [String] = []
        for l in lineas {
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if dentro { break }
                dentro = true
                continue
            }
            if dentro { cuerpo.append(l) }
        }
        let texto = cuerpo.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return texto.isEmpty ? nil : texto
    }

    // MARK: Formato

    /// "lun 16 nov · 2:45 p. m." (en la zona del calendario dado).
    public static func cuando(_ fecha: Date?, calendario: Calendar = .current) -> String {
        guard let fecha else { return "Sin fecha" }
        let c = calendario.dateComponents([.weekday, .day, .month, .hour, .minute], from: fecha)
        let h = c.hour ?? 0
        let hora12 = h % 12 == 0 ? 12 : h % 12
        return "\(NombresFecha.diasCortos[((c.weekday ?? 1) - 1) % 7].lowercased()) \(c.day ?? 1) \(NombresFecha.mesesCortos[((c.month ?? 1) - 1) % 12].lowercased())"
            + " · \(hora12):\(String(format: "%02d", c.minute ?? 0)) \(h < 12 ? "a. m." : "p. m.")"
    }
}

import Foundation

/// El formulario "Nueva reunión": qué se pide y por qué camino se crea. Nada se crea aquí: solo se decide, se valida y se arma
/// el enlace; quien guarda es la app, y solo al tocar Guardar.
public struct NuevaReunion: Equatable, Sendable {
    public enum Camino: Equatable, Sendable {
        /// Sin invitados ni Meet: se crea en Calendario (EventKit), en el calendario elegido.
        case local
        /// Con invitados o con Meet: EventKit no los puede crear en una cuenta de Google; se abre Google Calendar con todo puesto.
        case google
        /// Con invitados o Meet pero el calendario no es de Google: se crea local y se avisa que los invitados no se envían.
        case localSinInvitados
    }

    public var titulo: String
    public var inicio: Date
    public var duracionMin: Int
    /// El calendario elegido (id de EventKit) y si es de una cuenta de Google.
    public var calendarioID: String?
    public var calendarioEsGoogle: Bool
    /// Los correos como los escribió la persona (separados por coma, espacio, punto y coma o salto de línea).
    public var invitadosTexto: String
    public var conMeet: Bool
    /// Calendario de solo lectura o sin acceso completo: no se puede crear local.
    public var puedeCrearLocal: Bool

    public init(titulo: String = "", inicio: Date, duracionMin: Int = 30, calendarioID: String? = nil, calendarioEsGoogle: Bool = false,
                invitadosTexto: String = "", conMeet: Bool = false, puedeCrearLocal: Bool = true) {
        self.titulo = titulo
        self.inicio = inicio
        self.duracionMin = duracionMin
        self.calendarioID = calendarioID
        self.calendarioEsGoogle = calendarioEsGoogle
        self.invitadosTexto = invitadosTexto
        self.conMeet = conMeet
        self.puedeCrearLocal = puedeCrearLocal
    }

    public static let duraciones = [15, 30, 45, 60, 90, 120]

    public var fin: Date { inicio.addingTimeInterval(Double(max(5, duracionMin)) * 60) }

    /// Correos válidos, sin repetir y en minúsculas.
    public var invitados: [String] { Self.correos(invitadosTexto).validos }

    /// Lo que se escribió y no parece un correo.
    public var invalidos: [String] { Self.correos(invitadosTexto).invalidos }

    public var tituloFinal: String {
        let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Reunión" : t
    }

    /// Por dónde se va a guardar, para mostrarlo antes de tocar Guardar.
    public var camino: Camino {
        let pideGoogle = !invitados.isEmpty || conMeet
        if !pideGoogle { return puedeCrearLocal ? .local : .google }
        return calendarioEsGoogle || !puedeCrearLocal ? .google : .localSinInvitados
    }

    public var avisoDelCamino: String {
        switch camino {
        case .local: return "Se crea aquí, en tu Calendario."
        case .google: return "Se abre Google Calendar con todo puesto; ahí guardas."
        case .localSinInvitados: return "Se crea aquí, en tu Calendario; los invitados y Meet no se envían desde este calendario."
        }
    }

    public var botonGuardar: String {
        switch camino {
        case .local, .localSinInvitados: return "Guardar"
        case .google: return "Abrir en Google"
        }
    }

    /// Qué falta para poder guardar; vacío si está bien.
    public var problemas: [String] {
        var p: [String] = []
        if duracionMin < 5 { p.append("La duración es muy corta.") }
        if !invalidos.isEmpty { p.append("Revisa el correo: " + invalidos.joined(separator: ", ")) }
        return p
    }

    public var valida: Bool { problemas.isEmpty }

    /// Google Calendar con título, franja, invitados (`add`) y la nota de Meet ya puestos. Google no deja pedir la
    /// videollamada por enlace: se deja dicho en la descripción para activarla con un clic ahí.
    public func enlaceGoogle(cuenta: String? = nil) -> URL? {
        EnlacesCalendario.nuevoEvento(inicio: inicio, duracionMin: duracionMin, titulo: tituloFinal, cuenta: cuenta,
                                      invitados: invitados, detalles: conMeet ? "Agrega la videollamada de Google Meet." : nil)
    }

    /// Separa lo escrito en correos válidos y otros trozos.
    public static func correos(_ texto: String) -> (validos: [String], invalidos: [String]) {
        let separadores = CharacterSet(charactersIn: ",;\n\t ")
        var validos: [String] = [], invalidos: [String] = []
        for t in texto.components(separatedBy: separadores).map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>")) }) where !t.isEmpty {
            let c = t.lowercased()
            if esCorreo(c) { if !validos.contains(c) { validos.append(c) } } else if !invalidos.contains(t) { invalidos.append(t) }
        }
        return (validos, invalidos)
    }

    static func esCorreo(_ c: String) -> Bool {
        let partes = c.split(separator: "@", omittingEmptySubsequences: false)
        guard partes.count == 2, !partes[0].isEmpty, partes[0].count <= 64 else { return false }
        let dominio = partes[1].split(separator: ".", omittingEmptySubsequences: false)
        return dominio.count >= 2 && dominio.allSatisfy { !$0.isEmpty } && (dominio.last?.count ?? 0) >= 2
            && !c.contains("..") && c.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }
}

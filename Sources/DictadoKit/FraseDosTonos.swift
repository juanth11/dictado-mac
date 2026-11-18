import Foundation

/// El tono de un tramo de frase: el dato va pleno, el enlace ("con", "· libre hasta") al 55 %, y el acento toma el color de
/// la pieza (en Agentes, el número de pendientes).
public enum TonoFrase: Equatable, Sendable {
    case dato, enlace, acento
}

public struct SegmentoFrase: Equatable, Sendable {
    public var texto: String
    public var tono: TonoFrase

    public init(_ texto: String, _ tono: TonoFrase) {
        self.texto = texto
        self.tono = tono
    }
}

public enum Frase {
    /// Arma la frase: descarta lo vacío, une los tramos seguidos del mismo tono y pone un espacio entre tramos (salvo
    /// antes de una coma, un punto o un cierre). Dato y enlace se alternan dentro de una misma línea de texto.
    public static func armar(_ partes: [(String, TonoFrase)]) -> [SegmentoFrase] {
        var salida: [SegmentoFrase] = []
        for (crudo, tono) in partes {
            if crudo == "\n" {   // salto de línea explícito: el dato y el enlace se reparten en líneas
                if !salida.isEmpty, salida.last?.texto != "\n" { salida.append(SegmentoFrase("\n", .enlace)) }
                continue
            }
            let texto = crudo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { continue }
            let pegado = texto.first.map { ",.;:)!?".contains($0) } ?? false
            let trasSalto = salida.last?.texto.hasSuffix("\n") == true
            if var ultimo = salida.last, ultimo.tono == tono, !trasSalto {
                ultimo.texto += (pegado ? "" : " ") + texto
                salida[salida.count - 1] = ultimo
            } else if !salida.isEmpty, !pegado, !trasSalto {
                // El espacio va con el tramo que sigue para que no se pierda al cambiar de tono.
                salida.append(SegmentoFrase(" " + texto, tono))
            } else {
                salida.append(SegmentoFrase(texto, tono))
            }
        }
        if salida.last?.texto == "\n" { salida.removeLast() }
        return salida
    }

    /// La frase como texto corrido (accesibilidad y pruebas).
    public static func texto(_ segmentos: [SegmentoFrase]) -> String {
        segmentos.map(\.texto).joined()
    }

    /// "3:00": hora en doce horas, sin a. m./p. m. (como en la maqueta de Aurora).
    public static func hora(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.hour, .minute], from: fecha)
        let h = (c.hour ?? 0) % 12
        return String(format: "%d:%02d", h == 0 ? 12 : h, c.minute ?? 0)
    }
}

/// Una reunión reducida a lo que dice el lanzador.
public struct ReunionBreve: Equatable, Sendable, Identifiable {
    public var id: String
    public var titulo: String
    public var inicio: Date
    public var fin: Date
    /// Con quién es, si hay invitados ("Fabián").
    public var invitado: String?
    /// Cuántas personas en total (tú incluido); 0 si no hay invitados.
    public var personas: Int
    /// Bloquea horas libres (los eventos marcados como "libre" no).
    public var ocupado: Bool

    public init(id: String, titulo: String, inicio: Date, fin: Date, invitado: String? = nil, personas: Int = 0, ocupado: Bool = true) {
        self.id = id
        self.titulo = titulo
        self.inicio = inicio
        self.fin = fin
        self.invitado = invitado
        self.personas = personas
        self.ocupado = ocupado
    }
}

public struct ResumenAgenda: Equatable, Sendable {
    public var frase: [SegmentoFrase]
    /// Hasta dos: la que está en curso o la próxima, y la siguiente.
    public var proximas: [ReunionBreve]
}

/// Las frases de los widgets del lanzador.
public enum FrasesLanzador {
    /// "3:00 con Fabián / libre hasta entonces" (en dos líneas). En curso: "Comité hasta 4:00". Mañana: "Mañana 9:00 con Fabián".
    public static func agenda(_ reuniones: [ReunionBreve], ahora: Date, config: ConfigHuecos = .porOmision,
                              calendario: Calendar = .current) -> ResumenAgenda {
        let vigentes = reuniones.filter { $0.fin > ahora }.sorted { $0.inicio < $1.inicio }
        guard let primera = vigentes.first else {
            return ResumenAgenda(frase: Frase.armar([("Agenda", .dato), ("libre", .enlace)]), proximas: [])
        }
        let proximas = Array(vigentes.prefix(2))
        if primera.inicio <= ahora {
            return ResumenAgenda(frase: Frase.armar([(primera.titulo, .dato), ("hasta", .enlace),
                                                     (Frase.hora(primera.fin, calendario: calendario), .dato)]), proximas: proximas)
        }
        var partes: [(String, TonoFrase)] = [(etiquetaHora(primera.inicio, ahora: ahora, calendario: calendario), .dato)]
        if let con = primera.invitado, !con.isEmpty {
            partes += [("con", .enlace), (con, .dato)]
        } else {
            partes.append((primera.titulo, .dato))
        }
        if let libre = textoLibre(vigentes, primera: primera, ahora: ahora, config: config, calendario: calendario) {
            partes += [("\n", .enlace), (libre, .enlace)]
        }
        return ResumenAgenda(frase: Frase.armar(partes), proximas: proximas)
    }

    /// "3 trabajando / 2 esperan tu sí" (en dos líneas). `sesiones` = cuántas hay abiertas (con 0, no hay nada que contar).
    public static func agentes(trabajando: Int, esperan: Int, sesiones: Int) -> [SegmentoFrase] {
        switch (trabajando > 0, esperan > 0) {
        case (true, true):
            return Frase.armar([("\(trabajando)", .dato), ("trabajando", .enlace), ("\n", .enlace), ("\(esperan)", .acento),
                                (esperan == 1 ? "espera tu sí" : "esperan tu sí", .enlace)])
        case (true, false):
            return Frase.armar([("\(trabajando)", .dato), ("trabajando", .enlace), ("\n", .enlace), ("nadie espera tu sí", .enlace)])
        case (false, true):
            return Frase.armar([("\(esperan)", .acento), (esperan == 1 ? "espera tu sí" : "esperan tu sí", .enlace)])
        case (false, false):
            return sesiones > 0 ? Frase.armar([("Todo", .dato), ("en calma", .enlace)])
                                : Frase.armar([("Sin sesiones", .dato), ("abiertas", .enlace)])
        }
    }

    private static func etiquetaHora(_ inicio: Date, ahora: Date, calendario: Calendar) -> String {
        let hora = Frase.hora(inicio, calendario: calendario)
        if calendario.isDate(inicio, inSameDayAs: ahora) { return hora }
        if let manana = calendario.date(byAdding: .day, value: 1, to: ahora), calendario.isDate(inicio, inSameDayAs: manana) {
            return "Mañana " + hora
        }
        return NombresFecha.diasCortos[(calendario.component(.weekday, from: inicio) - 1) % 7] + " " + hora
    }

    /// Dice lo libre que estás ahora, con los huecos de la agenda (`Huecos`): hasta la reunión o el resto del día.
    private static func textoLibre(_ vigentes: [ReunionBreve], primera: ReunionBreve, ahora: Date, config: ConfigHuecos,
                                   calendario: Calendar) -> String? {
        let ocupados = vigentes.filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) }
        var uno = config
        uno.diasHorizonte = 1
        guard let hueco = Huecos.libres(ocupados: ocupados, desde: ahora, config: uno, calendario: calendario).first,
              calendario.isDate(hueco.inicio, inSameDayAs: ahora),
              hueco.inicio <= ahora.addingTimeInterval(Double(max(config.redondeoMin, 1)) * 60) else { return nil }
        if abs(hueco.fin.timeIntervalSince(primera.inicio)) < 1 { return "libre hasta entonces" }
        if !calendario.isDate(primera.inicio, inSameDayAs: ahora) { return "hoy libre" }
        return nil
    }
}

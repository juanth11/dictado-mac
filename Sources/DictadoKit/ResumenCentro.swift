import Foundation

/// La línea de resumen que abre cada sección del Centro (Tablero, Consumo, Herramientas, Automatizaciones): una frase con las cifras en su
/// contexto (el dato pleno, las palabras de enlace al 55 %), no una tira de cifras gigantes con etiqueta chica. Solo arma el texto.
public enum ResumenCentro {
    private typealias Parte = (String, TonoFrase)

    /// "a, b y c": cada grupo es un tramo de la frase; se separan con comas y una "y" antes del último.
    private static func unir(_ grupos: [[Parte]]) -> [Parte] {
        var salida: [Parte] = []
        for (i, g) in grupos.enumerated() {
            if i > 0 { salida.append(i == grupos.count - 1 ? ("y", .enlace) : (",", .enlace)) }
            salida.append(contentsOf: g)
        }
        return salida
    }

    /// "7 sesiones, 9,4 h de agentes y 190 M tokens hoy, con US$ 39,17 de costo equivalente y US$ 135,92 en 7 días". Lo que no se sabe no se dice.
    public static func tablero(_ c: CifrasHoy) -> [SegmentoFrase] {
        var grupos: [[Parte]] = []
        if let n = c.sesiones { grupos.append([("\(n)", .dato), (n == 1 ? "sesión" : "sesiones", .enlace)]) }
        if let s = c.segundos {
            let h = HistorialCentro.horas(s)
            grupos.append([("\(h.numero) \(h.unidad)", .dato), ("de agentes", .enlace)])
        }
        if let t = c.tokens {
            let k = HistorialCentro.tokens(t)
            grupos.append([("\(k.numero) \(k.unidad)", .dato)])
        }
        var partes = unir(grupos)
        if !grupos.isEmpty { partes.append(("hoy", .enlace)) }
        let hoy = c.costoHoy.map { v -> String in let k = HistorialCentro.costo(v); return "\(k.unidad) \(k.numero)" }
        let semana = c.costoSemana.map { v -> String in let k = HistorialCentro.costo(v); return "\(k.unidad) \(k.numero)" }
        switch (hoy, semana) {
        case (let h?, let s?):
            if grupos.isEmpty {
                partes += [("Costo equivalente:", .enlace), (h, .dato), ("hoy y", .enlace), (s, .dato), ("en 7 días", .enlace)]
            } else {
                partes += [(", con", .enlace), (h, .dato), ("de costo equivalente y", .enlace), (s, .dato), ("en 7 días", .enlace)]
            }
        case (let h?, nil):
            partes += grupos.isEmpty ? [("Costo equivalente:", .enlace), (h, .dato), ("hoy", .enlace)] : [(", con", .enlace), (h, .dato), ("de costo equivalente", .enlace)]
        case (nil, let s?):
            partes += grupos.isEmpty ? [("Costo equivalente:", .enlace), (s, .dato), ("en 7 días", .enlace)] : [(", con", .enlace), (s, .dato), ("de costo equivalente en 7 días", .enlace)]
        case (nil, nil): break
        }
        return Frase.armar(partes)
    }

    /// "Claude Code: US$ 41 hoy, US$ 493 en 7 días y US$ 2.003 en 30 días. Hermes: US$ 0,53 en 30 días". Cada fuente que falta se calla.
    public static func consumo(claudeCode: (hoy: String, sieteDias: String, treintaDias: String)?, hermes30: String?) -> [SegmentoFrase] {
        var p: [Parte] = []
        if let c = claudeCode {
            p += [("Claude Code:", .dato), (c.hoy, .dato), ("hoy,", .enlace), (c.sieteDias, .dato), ("en 7 días y", .enlace), (c.treintaDias, .dato),
                  ("en 30 días", .enlace)]
        }
        if let h = hermes30 {
            if claudeCode != nil { p.append((".", .enlace)) }
            p += [("Hermes:", .dato), (h, .dato), ("en 30 días", .enlace)]
        }
        return Frase.armar(p)
    }

    /// "12 MCP activos (3 sin uso), 48 skills activas (7 sin uso), 20 en reserva y 6 de 9 plugins activos". Lo que no se usa va en el acento.
    public static func herramientas(mcpActivos: Int, mcpSinUso: Int, skillsActivas: Int, skillsSinUso: Int, enReserva: Int,
                                    pluginsActivos: Int, pluginsInstalados: Int) -> [SegmentoFrase] {
        func con(_ n: Int, _ rotulo: String, sinUso: Int) -> [Parte] {
            var g: [Parte] = [("\(n)", .dato), (rotulo, .enlace)]
            if sinUso > 0 { g.append(("(\(sinUso) sin uso)", .acento)) }
            return g
        }
        let grupos: [[Parte]] = [
            con(mcpActivos, mcpActivos == 1 ? "MCP activo" : "MCP activos", sinUso: mcpSinUso),
            con(skillsActivas, skillsActivas == 1 ? "skill activa" : "skills activas", sinUso: skillsSinUso),
            [("\(enReserva)", .dato), ("en reserva", .enlace)],
            [("\(pluginsActivos)", .dato), ("de \(pluginsInstalados)", .enlace), (pluginsActivos == 1 ? "plugin activo" : "plugins activos", .enlace)],
        ]
        return Frase.armar(unir(grupos))
    }

    /// "3 piden atención, 14 al día, 2 sin dato y 1 apagada". Lo que pide atención va en el acento (y lo dice con palabras).
    public static func automatizaciones(_ r: ResumenAutomatizaciones) -> [SegmentoFrase] {
        var grupos: [[Parte]] = []
        if r.pidenAtencion > 0 { grupos.append([("\(r.pidenAtencion)", .acento), (r.pidenAtencion == 1 ? "pide atención" : "piden atención", .acento)]) }
        if r.alDia > 0 { grupos.append([("\(r.alDia)", .dato), ("al día", .enlace)]) }
        if r.sinDato > 0 { grupos.append([("\(r.sinDato)", .dato), ("sin dato", .enlace)]) }
        if r.apagado > 0 { grupos.append([("\(r.apagado)", .dato), (r.apagado == 1 ? "apagada" : "apagadas", .enlace)]) }
        guard !grupos.isEmpty else { return Frase.armar([("Nada programado", .enlace)]) }
        return Frase.armar(unir(grupos))
    }
}

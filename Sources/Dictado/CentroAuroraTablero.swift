import AppKit
import DictadoKit
import SwiftUI

// Sección Tablero del Centro: lo mismo que la isla (decisiones, trabajo en marcha, lo que terminó), en grande, y debajo la historia de
// la semana. Arriba, una frase con las cifras en su contexto: sesiones, horas, tokens y costo equivalente de hoy y de los últimos 7 días.
// Fuente: el documento `tablero` y `corrida listar` del centro. Sin centro, lo que ven directo las sesiones de Claude.

/// Un contenedor que se desplaza en la app y, en los renders (donde ImageRenderer no dibuja ScrollView), solo recorta.
struct DesplazableAurora<Contenido: View>: View {
    let simulado: Bool
    var ejes: Axis.Set = .vertical
    @ViewBuilder var contenido: () -> Contenido

    var body: some View {
        if simulado {
            // El color transparente fija el tamaño (lo que propone el padre) y el contenido solo se dibuja encima, recortado.
            Color.clear.overlay(alignment: .topLeading) { contenido() }.clipped()
        } else {
            ScrollView(ejes, showsIndicators: false) { contenido().frame(maxWidth: .infinity, alignment: .topLeading) }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// "hace 20 min" respecto a `ahora` (el reloj del Centro): así lo que se ve no depende de cuándo se dibuja.
func haceDesde(_ fecha: Date, _ ahora: Date) -> String {
    let s = Int(ahora.timeIntervalSince(fecha))
    if s < 60 { return "ahora" }
    if s < 3600 { return "hace \(s / 60) min" }
    if s < 48 * 3600 { return "hace \(s / 3600) h" }
    return "hace \(s / 86_400) d"
}

struct TableroAurora: View {
    let datos: DatosCentro
    let nav: NavegacionAurora
    let simulado: Bool

    private static let altoColumna: CGFloat = 336
    private static let altoHistorial: CGFloat = 388

    var body: some View {
        let ahora = datos.reloj.ahora
        let tablero = datos.tablero.vigente(ahora: ahora)
        let historial = datos.historial.corridas
        DesplazableAurora(simulado: simulado) {
            VStack(spacing: AuroraCentro.separacion) {
                tira(historial: historial, tablero: tablero, ahora: ahora)
                HStack(alignment: .top, spacing: AuroraCentro.separacion) {
                    esperan(tablero: tablero, ahora: ahora)
                    trabajando(tablero: tablero, ahora: ahora)
                    termino(tablero: tablero, historial: historial, ahora: ahora)
                }
                historialVista(historial: historial, tablero: tablero, ahora: ahora)
            }
        }
    }

    // MARK: La línea de resumen

    private func cifras(_ historial: [CorridaTablero]?, ahora: Date) -> CifrasHoy {
        if historial != nil { return HistorialCentro.cifras(historial, ahora: ahora) }
        // Sin historial solo se sabe lo que ven directo las sesiones de Claude.
        let c = datos.claude
        return CifrasHoy(sesiones: c.sesiones.isEmpty ? nil : c.sesiones.count, segundos: nil, tokens: c.tokensHoy > 0 ? c.tokensHoy : nil, costoHoy: nil, costoSemana: nil)
    }

    private func tira(historial: [CorridaTablero]?, tablero: Tablero?, ahora: Date) -> some View {
        ResumenAurora(segmentos: ResumenCentro.tablero(cifras(historial, ahora: ahora))) {
            if tablero == nil { avisoSinTablero.frame(width: 340) }
        }
    }

    /// El rótulo quieto de cuando el Tablero no está: qué falta y de dónde sale lo que se ve.
    private var avisoSinTablero: some View {
        VStack(alignment: .leading, spacing: 4) {
            RotuloPieza(datos.tablero.disponible ? "Tablero sin respuesta" : "Tablero no configurado", color: AuroraCentro.suave, grande: true)
            Text("Se ven las sesiones de Claude abiertas en este Mac.").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Columnas

    private func columna<C: View>(_ titulo: String, cuenta: Int, tono: Color, @ViewBuilder cuerpo: @escaping () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RotuloPieza(titulo, color: tono, grande: true)
                if cuenta > 0 { Text("\(cuenta)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.85)) }
                Spacer(minLength: 0)
            }
            .frame(height: 20)
            DesplazableAurora(simulado: simulado) {
                VStack(spacing: 8) { cuerpo() }
            }
            .frame(height: Self.altoColumna)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(titulo), \(cuenta)")
    }

    private func vacia(_ titulo: String, _ detalle: String) -> some View {
        TarjetaVidrioGrande(alto: 112) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).font(AuroraCentro.tituloTarjeta).foregroundStyle(.white.opacity(0.9))
                Text(detalle).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func esperan(tablero: Tablero?, ahora: Date) -> some View {
        let decisiones = tablero?.decisiones ?? []
        let sesiones = datos.claude.esperando
        return columna("Esperan tu sí", cuenta: decisiones.count + sesiones.count, tono: TonoAura.espera.rotulo) {
            ForEach(decisiones) { d in
                TarjetaDecisionGrande(decision: d, ahora: ahora, ocupada: datos.tablero.respondiendo.contains(d.id)) { opcion in datos.tablero.responder(d, opcion) }
            }
            ForEach(sesiones) { s in TarjetaSesionEspera(sesion: s, ahora: ahora) }
            if decisiones.isEmpty && sesiones.isEmpty { vacia("Nada espera tu sí", "Cuando un agente te pregunte algo, aparece aquí con sus opciones.") }
        }
    }

    private func trabajando(tablero: Tablero?, ahora: Date) -> some View {
        let corridas = (tablero?.enCurso ?? []).filter { $0.estado == .trabajando || $0.estado == .espera }
        let sesiones = tablero == nil ? datos.claude.sesiones.filter { $0.estado == .trabajando } : []
        return columna("Trabajando", cuenta: corridas.count + sesiones.count, tono: TonoAura.trabaja.rotulo) {
            ForEach(corridas) { c in
                TarjetaCorridaGrande(corrida: c, ahora: ahora, destino: DestinoCorrida.de(c, sesiones: datos.claude.sesiones))
            }
            ForEach(sesiones) { s in TarjetaSesionTrabaja(sesion: s, ahora: ahora) }
            if corridas.isEmpty && sesiones.isEmpty { vacia("Nada en marcha", "Los agentes que estén trabajando se ven aquí, con su tiempo y su costo.") }
        }
    }

    private func termino(tablero: Tablero?, historial: [CorridaTablero]?, ahora: Date) -> some View {
        let corridas = tablero == nil && historial == nil ? [] : HistorialCentro.terminadasDesdeAnoche(tablero: tablero, historial: historial, ahora: ahora)
        let sesiones = tablero == nil ? datos.claude.sesiones.filter { $0.estado == .lista } : []
        return columna("Terminó", cuenta: corridas.count + sesiones.count, tono: AuroraCentro.suave) {
            ForEach(corridas) { c in
                TarjetaTerminadaGrande(corrida: c, ahora: ahora, destino: DestinoCorrida.de(c, sesiones: datos.claude.sesiones))
            }
            ForEach(sesiones) { s in TarjetaSesionLista(sesion: s) }
            if corridas.isEmpty && sesiones.isEmpty { vacia("Nada terminó aún", "Lo que termine hoy y desde anoche queda aquí, con su resumen.") }
        }
    }

    // MARK: Historial

    private func historialVista(historial: [CorridaTablero]?, tablero: Tablero?, ahora: Date) -> some View {
        HStack(alignment: .top, spacing: AuroraCentro.separacion) {
            if let historial {
                let dias = HistorialCentro.dias(historial, ahora: ahora)
                let elegido = dias.indices.contains(nav.dia) ? nav.dia : 0
                TarjetaVidrioGrande(alto: Self.altoHistorial) {
                    VStack(alignment: .leading, spacing: 8) {
                        RotuloPieza("Historial · últimos 7 días", color: AuroraCentro.suave, grande: true)
                        VStack(spacing: 2) {
                            ForEach(Array(dias.enumerated()), id: \.element.id) { i, d in
                                FilaElegibleAurora(elegida: i == elegido, accion: { nav.dia = i }, radio: 12, vertical: 5) { FilaDiaHistorial(dia: d) }
                                    .accessibilityLabel(d.etiqueta + ": \(d.corridas.count) corridas")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                TarjetaVidrioGrande(alto: Self.altoHistorial) {
                    DetalleDia(dia: dias[elegido], ahora: ahora, sesiones: datos.claude.sesiones, simulado: simulado)
                }
                .frame(width: 440)
            } else {
                TarjetaVidrioGrande(alto: 150) {
                    VStack(alignment: .leading, spacing: 8) {
                        RotuloPieza("Historial", color: AuroraCentro.suave, grande: true)
                        Text(datos.tablero.disponible ? "El Tablero no respondió" : "El historial llega con el Tablero")
                            .font(AuroraCentro.tituloTarjeta)
                        Text("Cuando el Tablero responda, aquí se ve la semana, día por día, con lo que hizo cada agente.")
                            .font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Historial: una fila por día y el detalle del elegido

private func colorEstado(_ e: CorridaTablero.Estado) -> Color {
    switch e {
    case .termino: return AuroraCentro.azulBloque
    case .fallo: return Color(hex: 0xFFC24A)
    case .trabajando, .espera: return Color(hex: 0xC8D6FF)
    }
}

struct FilaDiaHistorial: View {
    let dia: DiaHistorial

    var body: some View {
        HStack(spacing: 12) {
            Text(dia.etiqueta).font(.system(size: 15, weight: dia.esHoy ? .bold : .semibold)).frame(width: 66, alignment: .leading)
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(Array(dia.barra.enumerated()), id: \.offset) { _, s in
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(colorEstado(s.estado))
                            .frame(width: max(4, g.size.width * s.fraccion - 2))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .background { Capsule().fill(Color.white.opacity(0.06)).frame(height: 10) }
            }
            .frame(height: 14)
            Text(dia.corridas.isEmpty ? "—" : "\(dia.corridas.count)").font(AuroraCentro.cuerpo).monospacedDigit().frame(width: 26, alignment: .trailing)
            Text(dia.segundos > 0 ? "\(HistorialCentro.horas(dia.segundos).numero) \(HistorialCentro.horas(dia.segundos).unidad)" : "").font(AuroraCentro.cuerpo)
                .foregroundStyle(AuroraCentro.resumen).monospacedDigit().frame(width: 64, alignment: .trailing)
            Text(dia.tokens.map { "\(HistorialCentro.tokens($0).numero) \(HistorialCentro.tokens($0).unidad.replacingOccurrences(of: " tokens", with: ""))" } ?? "")
                .font(AuroraCentro.cuerpo).foregroundStyle(AuroraCentro.resumen).monospacedDigit().frame(width: 62, alignment: .trailing)
            Text(dia.costoUSD.map { "US$ " + HistorialCentro.costo($0).numero } ?? "").font(AuroraCentro.cuerpo)
                .foregroundStyle(AuroraCentro.resumen).monospacedDigit().frame(width: 92, alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.vertical, 0)
        .frame(height: 24)
    }
}

struct DetalleDia: View {
    let dia: DiaHistorial
    let ahora: Date
    let sesiones: [SesionesClaude.Sesion]
    let simulado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(dia.esHoy ? "Hoy" : dia.etiqueta).font(AuroraCentro.tituloTarjeta)
                Text(dia.fecha).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
                Spacer(minLength: 0)
                Text(dia.corridas.isEmpty ? "" : (dia.corridas.count == 1 ? "1 corrida" : "\(dia.corridas.count) corridas"))
                    .font(AuroraCentro.cuerpo).foregroundStyle(AuroraCentro.suave)
            }
            if dia.corridas.isEmpty {
                Text("Sin corridas este día.").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
                Spacer(minLength: 0)
            } else {
                DesplazableAurora(simulado: simulado) {
                    VStack(spacing: 2) {
                        ForEach(dia.corridas) { c in FilaCorrida(corrida: c, ahora: ahora, destino: DestinoCorrida.de(c, sesiones: sesiones)) }
                    }
                }
                .desvanecerAbajo(28)
            }
        }
    }
}

struct FilaCorrida: View {
    let corrida: CorridaTablero
    let ahora: Date
    let destino: DestinoCorrida?
    @State private var encima = false

    private var detalle: String {
        var partes: [String] = []
        if let p = corrida.proyecto { partes.append(p) }
        if let i = corrida.inicio {
            let fin = corrida.fin ?? ahora
            let h = HistorialCentro.horas(max(0, fin.timeIntervalSince(i)))
            partes.append("\(h.numero) \(h.unidad)")
        }
        if let t = corrida.tokens { let k = HistorialCentro.tokens(t); partes.append("\(k.numero) \(k.unidad)") }
        if let c = corrida.costoUSD { partes.append("US$ " + HistorialCentro.costo(c).numero) }
        return partes.joined(separator: " · ")
    }

    var body: some View {
        let contenido = HStack(spacing: 12) {
            Circle().fill(colorEstado(corrida.estado)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(corrida.titulo).font(AuroraCentro.cuerpo).lineLimit(1)
                Text(detalle).font(.system(size: 13, weight: .regular)).foregroundStyle(AuroraCentro.suave).lineLimit(1)
            }
            Spacer(minLength: 0)
            if corrida.estado == .fallo { ChipAurora(texto: "No terminó", color: Color(hex: 0xFFC24A)) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(encima && destino != nil ? 0.08 : 0)) }
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        if let destino {
            Button { destino.abrir() } label: { contenido }.buttonStyle(PulsadoAurora())
                .help("Abrir «\(corrida.titulo)»")
                .accessibilityLabel("Abrir «\(corrida.titulo)». \(detalle)")
        } else {
            contenido.accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Tarjetas de las columnas

/// Una decisión abierta: aura roja, la pregunta, el encargo del que viene y un botón por opción (el mismo camino que la isla).
struct TarjetaDecisionGrande: View {
    let decision: DecisionTablero
    let ahora: Date
    let ocupada: Bool
    let responder: (String) -> Void

    private static func corta(_ t: String) -> String { t.count > 24 ? String(t.prefix(23)) + "…" : t }

    var body: some View {
        let creada = EstadoCentro.fecha(decision.creada)
        TarjetaAuraGrande(tono: .espera) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Espera tu decisión" + (creada.map { " · " + haceDesde($0, ahora) } ?? ""), color: TonoAura.espera.rotulo, grande: true)
                Text(decision.pregunta).font(AuroraCentro.tituloTarjeta).tracking(-0.2).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                if let encargo = decision.encargoTitulo {
                    Text(encargo).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(1).padding(.top, 2)
                }
                Spacer(minLength: 6)
                FlujoAura(espacio: 8) {
                    ForEach(Array(decision.respuestasPosibles.prefix(4).enumerated()), id: \.offset) { i, opcion in
                        BotonAura(Self.corta(opcion), estilo: i == 0 ? .lleno : .vidrio, grande: true,
                                  ayuda: "Responder «\(opcion)»: \(decision.pregunta)") { responder(opcion) }
                    }
                }
                .opacity(ocupada ? 0.5 : 1)
                .allowsHitTesting(!ocupada)
            }
        }
    }
}

/// Una sesión de Claude que pide tu permiso: Responder abre justo esa sesión.
struct TarjetaSesionEspera: View {
    let sesion: SesionesClaude.Sesion
    let ahora: Date

    var body: some View {
        TarjetaAuraGrande(tono: .espera) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Espera tu respuesta · " + haceDesde(sesion.desde, ahora), color: TonoAura.espera.rotulo, grande: true)
                Text(sesion.nombre).font(AuroraCentro.tituloTarjeta).tracking(-0.2).lineLimit(1).padding(.top, 4)
                Text(Tiempo.sesion(sesion)).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                Spacer(minLength: 6)
                HStack {
                    BotonAura("Responder", estilo: .lleno, grande: true, ayuda: "Abrir la sesión «\(sesion.nombre)» para responder") { SesionesClaude.abrir(sesion) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Una corrida en marcha: aura azul, su título, proyecto, cuánto lleva, tokens y el costo equivalente. Toda la tarjeta abre la sesión.
struct TarjetaCorridaGrande: View {
    let corrida: CorridaTablero
    let ahora: Date
    let destino: DestinoCorrida?

    var body: some View {
        let t = HistorialCentro.horas(max(0, ahora.timeIntervalSince(corrida.inicio ?? ahora)))
        let tokens = corrida.tokens.map { n -> String in let k = HistorialCentro.tokens(n); return "\(k.numero) \(k.unidad)" }
        let costo = corrida.costoUSD.map { "US$ " + HistorialCentro.costo($0).numero + " equiv." }
        let contenido = TarjetaAuraGrande(tono: .trabaja) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Trabajando" + (corrida.proyecto.map { " · " + $0 } ?? ""), color: TonoAura.trabaja.rotulo, grande: true)
                Text(corrida.titulo).font(AuroraCentro.tituloTarjeta).tracking(-0.2).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                Spacer(minLength: 4)
                HStack(alignment: .bottom, spacing: 16) {
                    if corrida.inicio != nil { Cifra(numero: t.numero, unidad: t.unidad, tamano: 38, peso: .ultraLight) }
                    VStack(alignment: .leading, spacing: 0) {
                        if let tokens { Text(tokens).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(1) }
                        if let costo { Text(costo).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    BokehAurora().frame(width: 70).padding(.bottom, 4)
                }
            }
        }
        if let destino {
            Button { destino.abrir() } label: { contenido }.buttonStyle(PulsadoAurora())
                .help("Abrir «\(corrida.titulo)»")
                .accessibilityLabel("Abrir «\(corrida.titulo)», trabajando desde hace \(t.numero) \(t.unidad)")
        } else {
            contenido.accessibilityElement(children: .combine)
        }
    }
}

/// Una sesión de Claude que trabaja (cuando no hay Tablero): el tiempo que lleva y qué hace ahora.
struct TarjetaSesionTrabaja: View {
    let sesion: SesionesClaude.Sesion
    let ahora: Date

    var body: some View {
        let t = HistorialCentro.horas(max(0, ahora.timeIntervalSince(sesion.desde)))
        Button { SesionesClaude.abrir(sesion) } label: {
            TarjetaAuraGrande(tono: .trabaja) {
                VStack(alignment: .leading, spacing: 0) {
                    RotuloPieza("Trabajando · " + (sesion.host == nil ? "terminal" : "Claude"), color: TonoAura.trabaja.rotulo, grande: true)
                    Text(sesion.nombre).font(AuroraCentro.tituloTarjeta).tracking(-0.2).lineLimit(2).padding(.top, 4)
                    Spacer(minLength: 4)
                    HStack(alignment: .bottom, spacing: 16) {
                        Cifra(numero: t.numero, unidad: t.unidad, tamano: 38, peso: .ultraLight)
                        Text(sesion.actividad.isEmpty ? "Trabajando…" : sesion.actividad).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(1)
                        Spacer(minLength: 0)
                        BokehAurora().frame(width: 70).padding(.bottom, 4)
                    }
                }
            }
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel("Abrir la sesión «\(sesion.nombre)», trabajando desde hace \(t.numero) \(t.unidad)")
    }
}

/// Lo que terminó: tarjeta oscura con el resumen y Ver.
struct TarjetaTerminadaGrande: View {
    let corrida: CorridaTablero
    let ahora: Date
    let destino: DestinoCorrida?

    var body: some View {
        let fallo = corrida.estado == .fallo
        let resumen = corrida.resumen ?? [corrida.proyecto, corrida.costoUSD.map { "US$ " + HistorialCentro.costo($0).numero + " equiv." }].compactMap { $0 }.joined(separator: " · ")
        TarjetaVidrioGrande {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza((fallo ? "No terminó" : "Lista") + " · " + haceDesde(corrida.fin ?? corrida.inicio ?? ahora, ahora)
                            + (corrida.proyecto.map { " · " + $0 } ?? ""), color: fallo ? TonoAura.alerta.rotulo : AuroraCentro.suave, grande: true)
                Text(corrida.titulo).font(AuroraCentro.tituloTarjeta).tracking(-0.2).lineLimit(1).padding(.top, 4)
                Text(resumen).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                Spacer(minLength: 4)
                HStack {
                    if let destino { BotonAura("Ver", estilo: .oscuro, grande: true, ayuda: "Abrir «\(corrida.titulo)»") { destino.abrir() } }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Una sesión de Claude lista (cuando no hay Tablero).
struct TarjetaSesionLista: View {
    let sesion: SesionesClaude.Sesion

    var body: some View {
        TarjetaVidrioGrande {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Lista · " + Tiempo.hace(sesion.desde), color: AuroraCentro.suave, grande: true)
                Text(sesion.nombre).font(AuroraCentro.tituloTarjeta).tracking(-0.2).lineLimit(1).padding(.top, 4)
                if !sesion.resumen.isEmpty {
                    Text(sesion.resumen).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
                Spacer(minLength: 4)
                HStack {
                    BotonAura("Ver", estilo: .oscuro, grande: true, ayuda: "Abrir la sesión «\(sesion.nombre)»") { SesionesClaude.abrir(sesion) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

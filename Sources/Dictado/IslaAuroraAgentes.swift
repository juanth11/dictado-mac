import AppKit
import DictadoKit
import SwiftUI

// Pestaña Agentes: una tarjeta de aura por sesión de Claude Code o agente remoto, con el color de su estado (te espera:
// rojo; trabaja: azul; alerta de un agente remoto: ámbar; lista o en calma: oscura). Solo lleva las acciones que la app
// sabe hacer hoy: abrir o responder la sesión en Claude (los enlaces `claude://`) y abrir el día de un agente remoto.
// Aprobar o elegir entre opciones no existen todavía (la app solo lee ~/.claude), así que no hay botones para eso.

struct AgentesAurora: View {
    let estado: EstadoIsla
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let simulado: Bool
    let acciones: AccionesIsla
    var tablero: TableroIsla?
    var ahora = Date()

    private enum Elemento: Identifiable {
        case sesion(SesionesClaude.Sesion)
        case agente(AgentesRemotos.Agente)

        var id: String {
            switch self {
            case .sesion(let s): return "s" + s.id
            case .agente(let a): return "a" + a.id
            }
        }

        /// Lo que pide tu respuesta primero, luego las alertas, lo que trabaja, lo que está quieto y lo que terminó.
        var prioridad: Int {
            switch self {
            case .sesion(let s): return s.estado == .esperando ? 0 : (s.estado == .trabajando ? 2 : 4)
            case .agente(let a): return a.estado == .alerta || a.estado == .caido || !a.alertas.isEmpty ? 1 : 3
            }
        }
    }

    /// El Tablero vigente, si hay: con él, el trabajo y lo terminado salen de sus corridas y las sesiones de Claude solo aportan
    /// las que piden tu permiso (el Tablero no las ve).
    private var delTablero: Tablero? { tablero?.vigente(ahora: ahora) }

    private func elementos(_ t: Tablero?) -> [Elemento] {
        let sesiones = t == nil ? claude.sesiones : claude.sesiones.filter { $0.estado == .esperando }
        let todos = sesiones.map(Elemento.sesion) + agentes.agentes.map(Elemento.agente)
        return todos.enumerated().sorted { ($0.element.prioridad, $0.offset) < ($1.element.prioridad, $1.offset) }.map(\.element)
    }

    var body: some View {
        if let nombre = estado.agenteAbierto, let agente = agentes.agentes.first(where: { $0.nombre == nombre }) {
            TarjetaOscura {
                DetalleAgente(agente: agente, consultando: agentes.consultando) { estado.agenteAbierto = nil }
            }
        } else {
            GeometryReader { g in
                if simulado {
                    fila(g.size.width).clipped()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) { fila(g.size.width) }
                        .scrollClipDisabled(false)
                }
            }
        }
    }

    private func fila(_ ancho: CGFloat) -> some View {
        let t = delTablero
        let resto = elementos(t)
        return HStack(spacing: AuroraNotch.separacion) {
            if let t {
                ForEach(t.decisiones) { d in
                    TarjetaDecisionAura(decision: d, ocupada: tablero?.respondiendo.contains(d.id) == true) { opcion in tablero?.responder(d, opcion) }
                }
            }
            ForEach(resto.filter { $0.prioridad <= 1 }) { e in tarjeta(e) }
            if let t {
                ForEach(t.enCurso.filter { $0.estado == .trabajando || $0.estado == .espera }) { c in
                    TarjetaCorridaAura(corrida: c, ahora: ahora, destino: DestinoCorrida.de(c, sesiones: claude.sesiones))
                }
            }
            // Las sesiones sin Tablero: la que trabaja va grande y las demás en la pila de filas.
            let sesionesResto: [SesionesClaude.Sesion] = resto.filter { $0.prioridad > 1 }.compactMap { if case .sesion(let s) = $0 { return s } else { return nil } }
            let reparto = PilaAgentes.repartir(sesionesResto.map { $0.estado == .trabajando ? .trabaja : ($0.estado == .esperando ? .espera : .lista) })
            if let g = reparto.grande { TarjetaSesionAura(sesion: sesionesResto[g]) }
            if !reparto.pila.isEmpty { PilaSesionesAura(sesiones: reparto.pila.map { sesionesResto[$0] }, ahora: ahora) }
            ForEach(resto.filter { e in e.prioridad > 1 && { if case .agente = e { return true } else { return false } }() }) { e in tarjeta(e) }
            if let t {
                ForEach(TableroCentro.terminadas(t)) { c in
                    TarjetaTerminadaAura(corrida: c, ahora: ahora, destino: DestinoCorrida.de(c, sesiones: claude.sesiones))
                }
            }
            ForEach(tablero?.encargosNuevos ?? []) { e in TarjetaEncargoPendiente(encargo: e) }
            NuevoEncargo(acciones: acciones, conTablero: t != nil || tablero?.disponible == true)
        }
        .frame(minWidth: ancho, alignment: .leading)
    }

    @ViewBuilder private func tarjeta(_ e: Elemento) -> some View {
        switch e {
        case .sesion(let s): TarjetaSesionAura(sesion: s)
        case .agente(let a): TarjetaAgenteRemoto(agente: a) { estado.agenteAbierto = a.nombre }
        }
    }
}

// MARK: - Sesión de Claude Code

struct TarjetaSesionAura: View {
    let sesion: SesionesClaude.Sesion

    private var minutos: Int { max(0, Int(-sesion.desde.timeIntervalSinceNow) / 60) }

    var body: some View {
        switch sesion.estado {
        case .esperando: espera
        case .trabajando: trabaja
        case .lista: lista
        }
    }

    private func abrir() { SesionesClaude.abrir(sesion) }

    /// Te espera: el aura roja, lo que pide y Responder (abre justo esa sesión en Claude, en la pregunta o el permiso).
    private var espera: some View {
        TarjetaAura(tono: .espera, ancho: AuroraNotch.anchoAgente) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    ChispaViva(modo: .espera, lado: 14)
                    RotuloPieza("Espera tu respuesta · " + Tiempo.hace(sesion.desde), color: TonoAura.espera.rotulo)
                }
                Text(sesion.nombre).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(2).padding(.top, 2).help(sesion.nombre)
                Spacer(minLength: 4)
                Text(Tiempo.sesion(sesion)).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    BotonAura("Responder", estilo: .lleno, ayuda: "Abrir la sesión «\(sesion.nombre)» para responder", accion: abrir)
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }
        }
    }

    /// Trabaja: el aura azul con lo único medido de verdad: cuánto lleva, cuánto contexto usa y qué hace ahora; la cifra
    /// fina es el tiempo y las luces desenfocadas, que está pensando. Toda la tarjeta abre la sesión.
    private var trabaja: some View {
        Button(action: abrir) {
            TarjetaAura(tono: .trabaja, ancho: AuroraNotch.anchoAgente) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            RotuloPieza("Trabajando · " + (sesion.host == nil ? "terminal" : "Claude"), color: TonoAura.trabaja.rotulo)
                            Text(sesion.nombre).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        // El anillo se llena con el contexto (de 0 a 1 M de tokens); la chispa gira mientras trabaja.
                        Dial(lado: 44, valor: min(1, Double(sesion.contexto) / 1_000_000), colores: [.white.opacity(0.8), .white], marcas: 30, anillo: 4,
                             brillo: 0.2, destello: false) { ChispaViva(modo: .trabaja, lado: 18) }
                            .accessibilityLabel("Contexto: \(Tiempo.tokens(sesion.contexto)) tokens")
                    }
                    Spacer(minLength: 4)
                    Text(sesion.actividad.isEmpty ? "Trabajando…" : sesion.actividad)
                        .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(1)
                    if sesion.contexto > 0 {
                        Text("Contexto " + Tiempo.tokens(sesion.contexto)).font(AuroraNotch.fila).foregroundStyle(.white.opacity(0.6)).padding(.top, 2)
                    }
                    HStack(spacing: 8) {
                        Cifra(numero: "\(minutos)", unidad: "min", tamano: 30, peso: .ultraLight)
                        BokehAurora()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .buttonStyle(PulsadoAurora())
        .help("Abrir la sesión")
        .accessibilityLabel("Abrir la sesión «\(sesion.nombre)», trabajando desde hace \(minutos) minutos")
    }

    /// Terminó: oscura, con lo que dijo al final y Ver.
    private var lista: some View {
        TarjetaOscura(ancho: AuroraNotch.anchoAgente) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Lista · " + Tiempo.hace(sesion.desde))
                Text(sesion.nombre).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(2).padding(.top, 2)
                Spacer(minLength: 4)
                if !sesion.resumen.isEmpty {
                    Text(sesion.resumen).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    BotonAura("Ver", estilo: .oscuro, ayuda: "Abrir la sesión «\(sesion.nombre)»", accion: abrir)
                    Spacer(minLength: 0)
                    if sesion.contexto > 0 { Contexto(tokens: sesion.contexto) }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Agente remoto

/// Un agente fuera del Mac: con alerta o caído, el aura ámbar o roja; si no, oscura con su resumen. Ver abre su día.
struct TarjetaAgenteRemoto: View {
    let agente: AgentesRemotos.Agente
    let ver: () -> Void

    private var alerta: Bool { agente.estado == .alerta || agente.estado == .caido || !agente.alertas.isEmpty }

    var body: some View {
        if alerta {
            let tono = agente.estado == .caido ? TonoAura.espera : TonoAura.alerta
            TarjetaAura(tono: tono, ancho: AuroraNotch.anchoAgente) { contenido(tono: tono) }
        } else {
            TarjetaOscura(ancho: AuroraNotch.anchoAgente) { contenido(tono: nil) }
        }
    }

    private func contenido(tono: TonoAura?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RotuloPieza((agente.estado == .caido ? "No responde" : (alerta ? "Alerta" : "Agente")) + " · " + Tiempo.hace(agente.actualizado ?? Date()),
                        color: tono?.rotulo ?? AuroraNotch.sutil)
            Text(agente.nombre).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(1).padding(.top, 2).help(agente.nombre)
            Spacer(minLength: 4)
            Text(agente.error ?? agente.alertas.first ?? agente.resumen)
                .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                BotonAura("Ver", estilo: tono == nil ? .oscuro : .lleno, ayuda: "Ver el día de «\(agente.nombre)»", accion: ver)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Nuevo encargo

/// La última tarjeta: la onda de dictado (la misma `Prisma`, quieta) y cómo dar un encargo con la voz.
struct NuevoEncargo: View {
    let acciones: AccionesIsla
    /// El Tablero del centro está configurado: dictar aquí crea un encargo en él.
    var conTablero = false
    /// Estado quieto para la onda: en reposo no hay voz y la forma no cambia.
    private static let quieto: EstadoHUD = {
        let h = EstadoHUD()
        h.fase = .resultado
        h.estilo = .prisma
        return h
    }()

    var body: some View {
        TarjetaOscura(ancho: nil) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Nuevo encargo")
                GeometryReader { g in   // la onda ocupa el ancho de la tarjeta (se dibuja grande y se escala)
                    let escala: CGFloat = 0.46
                    Prisma(estado: Self.quieto, t: 1.4)
                        .frame(width: g.size.width / escala, height: 54 / escala)
                        .scaleEffect(escala)
                        .frame(width: g.size.width, height: 56)
                }
                .frame(height: 56)
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(conTablero ? "Dilo y queda como encargo en el Tablero." : "Mantén ⌥ Espacio y dilo. Con ⇧, queda como idea en tu inbox.")
                    .font(AuroraNotch.fila).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                HStack(spacing: 4) {
                    BotonAura("Dictar", icono: "mic.fill", estilo: .oscuro, ayuda: "Dictar un encargo ahora",
                              accion: conTablero ? acciones.dictarEncargo : acciones.dictar)
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }
        }
        .frame(minWidth: 212)
    }
}

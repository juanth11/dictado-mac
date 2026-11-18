import AppKit
import DictadoKit
import Observation
import SwiftUI

// El Tablero en la isla: el registro único del trabajo de los agentes (`python3 -m centro tablero --json`). Este archivo tiene el
// modelo (`TableroIsla`, con el mismo mecanismo que `TareasIsla`: la carpeta del centro, el proceso fuera del hilo principal y un
// tope de tiempo) y las tarjetas de la pestaña Agentes: decisiones, corridas en marcha y lo que terminó. Si el centro no está
// configurado o falla, todo vuelve a lo de siempre (las sesiones de Claude vistas directo) y nunca se muestra un error.

@MainActor @Observable
final class TableroIsla {
    private(set) var tablero: Tablero?
    private(set) var leido: Date?
    private(set) var cargando = false
    /// ¿Está configurado el centro? (se vuelve a mirar en cada lectura; en las vistas se usa el último valor).
    private(set) var disponible: Bool
    /// Los encargos creados al dictar en esta sesión de la app (el Tablero solo lista corridas y decisiones): tarjetas pendientes.
    private(set) var encargosNuevos: [EncargoTablero] = []
    /// Decisiones cuya respuesta va en camino (el botón queda quieto).
    private(set) var respondiendo: Set<Int> = []

    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private var ultimaPeticion: Date?

    nonisolated static let limiteIndexar: TimeInterval = 25
    nonisolated static let limiteLeer: TimeInterval = 8
    nonisolated static let limiteOrden: TimeInterval = 10

    init(vivo: Bool = true) {
        self.vivo = vivo
        disponible = vivo && TareasIsla.carpetaCentro != nil
    }

    /// El Tablero si la última lectura sigue vigente; si no, nil (las vistas usan lo que ven directo).
    func vigente(ahora: Date = Date()) -> Tablero? {
        guard let tablero, let leido, ahora.timeIntervalSince(leido) <= TableroCentro.vigencia else { return nil }
        return tablero
    }

    /// De dónde sale lo que se ve: el Tablero (vigente) o las sesiones de Claude.
    func deTablero(ahora: Date = Date()) -> Bool { vigente(ahora: ahora) != nil }

    nonisolated private static func correr(_ argumentos: [String], en carpeta: URL, limite: TimeInterval) -> (datos: Data, error: String?) {
        CentroStore.correr(URL(fileURLWithPath: "/usr/bin/python3"), ["-m", "centro"] + argumentos, limite: limite, carpeta: carpeta)
    }

    // MARK: Leer

    /// Indexa las sesiones de los últimos dos días y pide el tablero (fuera del hilo principal, con tope de tiempo). Como mucho
    /// una vez por minuto; lo llaman solo las vistas que lo muestran (pestaña Agentes, Inicio, la pieza de agentes del Dock).
    func refrescar(forzar: Bool = false) {
        guard vivo, !cargando else { return }
        guard let carpeta = TareasIsla.carpetaCentro else {
            disponible = false
            tablero = nil
            leido = nil
            return
        }
        disponible = true
        guard forzar || TableroCentro.tocaPedir(ultima: ultimaPeticion, ahora: Date()) else { return }
        ultimaPeticion = Date()
        cargando = true
        Task.detached(priority: .userInitiated) {
            _ = Self.correr(["corridas-indexar", "--dias", "2", "--json"], en: carpeta, limite: Self.limiteIndexar)
            let r = Self.correr(["tablero", "--json"], en: carpeta, limite: Self.limiteLeer)
            let nuevo = r.error == nil ? TableroCentro.decodificar(r.datos) : nil
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cargando = false
                if let nuevo {
                    self.tablero = nuevo
                    self.leido = Date()
                } else {
                    self.tablero = nil   // falló: de vuelta a lo que se ve directo, sin tarjeta de error
                    self.leido = nil
                }
            }
        }
    }

    // MARK: Cambiar

    /// Responde una decisión abierta: sale de la lista al instante, corre `decision responder <id> <opción>` y vuelve a leer.
    func responder(_ d: DecisionTablero, _ opcion: String) {
        guard vivo, !respondiendo.contains(d.id), let carpeta = TareasIsla.carpetaCentro else { return }
        respondiendo.insert(d.id)
        if var t = tablero {
            t.decisiones.removeAll { $0.id == d.id }
            t.conteos.esperanTuSi = max(0, t.conteos.esperanTuSi - 1)
            tablero = t
        }
        Task.detached(priority: .userInitiated) {
            _ = Self.correr(TableroCentro.argumentosRespuesta(decision: d.id, respuesta: opcion), en: carpeta, limite: Self.limiteOrden)
            await MainActor.run { [weak self] in
                self?.respondiendo.remove(d.id)
                self?.refrescar(forzar: true)   // si el centro no la aceptó, la decisión vuelve sola
            }
        }
    }

    /// Crea el encargo de un dictado (`encargo nuevo … --origen dictado --json`). `alTerminar(true)` si el centro lo creó; con
    /// false el llamador conserva lo dictado de otra forma (como una idea).
    func crearEncargo(_ texto: String, alTerminar: @escaping @MainActor (Bool) -> Void) {
        guard vivo, let carpeta = TareasIsla.carpetaCentro else {
            alTerminar(false)
            return
        }
        let argumentos = TableroCentro.argumentosEncargo(texto)
        Task.detached(priority: .userInitiated) {
            let r = Self.correr(argumentos, en: carpeta, limite: Self.limiteOrden)
            let encargo = r.error == nil ? TableroCentro.decodificarEncargo(r.datos) : nil
            await MainActor.run { [weak self] in
                if let encargo {
                    self?.encargosNuevos.removeAll { $0.id == encargo.id }
                    self?.encargosNuevos.insert(encargo, at: 0)
                    if let n = self?.encargosNuevos.count, n > 3 { self?.encargosNuevos.removeLast(n - 3) }
                    self?.refrescar(forzar: true)
                }
                alTerminar(encargo != nil)
            }
        }
    }

    /// Para los renders: lo que se muestra, sin leer nada.
    func fijar(_ t: Tablero?, encargos: [EncargoTablero] = [], leido: Date = Date()) {
        tablero = t
        self.leido = t == nil ? nil : leido
        disponible = t != nil
        encargosNuevos = encargos
    }
}

/// Lo que trabaja y lo que espera tu sí, de una sola cuenta para la isla compacta, Inicio y el Dock: del Tablero si hay una
/// lectura vigente (a las decisiones abiertas se suman las sesiones que piden tu permiso y los agentes remotos con alerta, que
/// el Tablero no ve); si no, de lo que se ve directo.
@MainActor
struct CuentasAgentes {
    let trabajando: Int
    let esperan: Int
    let deTablero: Bool

    static func de(claude: SesionesClaude, agentes: AgentesRemotos?, tablero: TableroIsla?, ahora: Date = Date()) -> CuentasAgentes {
        let remotos = agentes?.agentes.filter { $0.estado == .alerta || $0.estado == .caido }.count ?? 0
        let vivas = claude.esperando.count + remotos
        let c = TableroCentro.cuentas(tablero: tablero?.vigente(ahora: ahora), leido: tablero?.leido, ahora: ahora,
                                      directoTrabajando: claude.trabajando, directoEsperan: vivas, esperanVivas: vivas)
        return CuentasAgentes(trabajando: c.trabajando, esperan: c.esperan, deTablero: c.deTablero)
    }
}

// MARK: - La pestaña, con el Tablero

/// Un salto de línea para los botones de una decisión: se acomodan en filas del ancho de la tarjeta.
struct FlujoAura: Layout {
    var espacio: CGFloat = 6

    private func filas(_ ancho: CGFloat, _ subvistas: Subviews) -> (posiciones: [CGPoint], tamano: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, altoFila: CGFloat = 0, maxX: CGFloat = 0
        var puntos: [CGPoint] = []
        for s in subvistas {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > ancho { x = 0; y += altoFila + espacio; altoFila = 0 }
            puntos.append(CGPoint(x: x, y: y))
            x += t.width + espacio
            altoFila = max(altoFila, t.height)
            maxX = max(maxX, x - espacio)
        }
        return (puntos, CGSize(width: maxX, height: y + altoFila))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        filas(proposal.width ?? .infinity, subviews).tamano
    }

    func placeSubviews(in marco: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = filas(marco.width, subviews)
        for (s, p) in zip(subvistas(subviews), r.posiciones) {
            s.place(at: CGPoint(x: marco.minX + p.x, y: marco.minY + p.y), proposal: .unspecified)
        }
    }

    private func subvistas(_ s: Subviews) -> [LayoutSubview] { Array(s) }
}

/// Una decisión abierta: aura roja con la pregunta, el encargo del que viene y un botón por opción (o Sí / No).
struct TarjetaDecisionAura: View {
    let decision: DecisionTablero
    let ocupada: Bool
    let responder: (String) -> Void

    private static func corta(_ t: String) -> String { t.count > 22 ? String(t.prefix(21)) + "…" : t }

    var body: some View {
        TarjetaAura(tono: .espera, ancho: AuroraNotch.anchoAgente) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Espera tu decisión", color: TonoAura.espera.rotulo)
                Text(decision.pregunta).font(AuroraNotch.tituloTarea).lineLimit(3).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                if let encargo = decision.encargoTitulo {
                    Text(encargo).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(1).padding(.top, 4)
                }
                Spacer(minLength: 4)
                FlujoAura(espacio: 6) {
                    ForEach(Array(decision.respuestasPosibles.prefix(4).enumerated()), id: \.offset) { i, opcion in
                        BotonAura(Self.corta(opcion), estilo: i == 0 ? .lleno : .vidrio, ayuda: "Responder «\(opcion)»: \(decision.pregunta)") { responder(opcion) }
                    }
                }
                .opacity(ocupada ? 0.5 : 1)
                .allowsHitTesting(!ocupada)
            }
        }
    }
}

/// Dónde se abre una corrida: su sesión de Claude si sigue viva en el Mac, o su enlace.
enum DestinoCorrida {
    case sesion(SesionesClaude.Sesion)
    case enlace(URL)

    @MainActor static func de(_ c: CorridaTablero, sesiones: [SesionesClaude.Sesion]) -> DestinoCorrida? {
        if let s = c.sesion, let viva = sesiones.first(where: { $0.id == s }) { return .sesion(viva) }
        if let url = c.enlace { return .enlace(url) }
        return nil
    }

    @MainActor func abrir() {
        switch self {
        case .sesion(let s): SesionesClaude.abrir(s)
        case .enlace(let url): NSWorkspace.shared.open(url)
        }
    }
}

/// Una corrida en marcha: aura azul con su título, proyecto, cuánto lleva, tokens y el costo equivalente (si lo hay).
struct TarjetaCorridaAura: View {
    let corrida: CorridaTablero
    let ahora: Date
    let destino: DestinoCorrida?

    var body: some View {
        let tiempo = TableroCentro.transcurrido(desde: corrida.inicio, hasta: ahora)
        let tokens = corrida.tokens.map { TableroCentro.tokens($0) + " tokens" }
        let costo = TableroCentro.costo(corrida.costoUSD)
        let contenido = TarjetaAura(tono: .trabaja, ancho: AuroraNotch.anchoAgente) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Trabajando" + (corrida.proyecto.map { " · " + $0 } ?? ""), color: TonoAura.trabaja.rotulo)
                Text(corrida.titulo).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(2).padding(.top, 2)
                Spacer(minLength: 4)
                if let tiempo { Cifra(numero: tiempo.split(separator: " ").first.map(String.init) ?? "0", unidad: tiempo.split(separator: " ").dropFirst().joined(separator: " "), tamano: 26, peso: .ultraLight) }
                VStack(alignment: .leading, spacing: 1) {
                    if let tokens { Text(tokens).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(1) }
                    if let costo { Text(costo).font(AuroraNotch.fila).foregroundStyle(.white.opacity(0.62)).lineLimit(1) }
                }
                .padding(.top, 4)
            }
        }
        if let destino {
            Button { destino.abrir() } label: { contenido }
                .buttonStyle(PulsadoAurora())
                .help("Abrir «\(corrida.titulo)»")
                .accessibilityLabel("Abrir «\(corrida.titulo)», trabajando" + (tiempo.map { " desde hace \($0)" } ?? ""))
        } else {
            contenido
                .accessibilityElement(children: .combine)
        }
    }
}

/// Una corrida que terminó desde anoche: tarjeta oscura con su resumen y Ver.
struct TarjetaTerminadaAura: View {
    let corrida: CorridaTablero
    let ahora: Date
    let destino: DestinoCorrida?

    var body: some View {
        let fallo = corrida.estado == .fallo
        TarjetaOscura(ancho: AuroraNotch.anchoAgente) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza((fallo ? "No terminó" : "Lista") + " · " + Tiempo.hace(corrida.fin ?? corrida.inicio ?? ahora),
                            color: fallo ? TonoAura.alerta.rotulo : AuroraNotch.sutil)
                Text(corrida.titulo).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(2).padding(.top, 2)
                Spacer(minLength: 4)
                Text(corrida.resumen ?? [corrida.proyecto, TableroCentro.costo(corrida.costoUSD)].compactMap { $0 }.joined(separator: " · "))
                    .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if let destino {
                        BotonAura("Ver", estilo: .oscuro, ayuda: "Abrir «\(corrida.titulo)»") { destino.abrir() }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }
        }
    }
}

/// Un encargo dictado que ya está en el Tablero y espera a un agente.
struct TarjetaEncargoPendiente: View {
    let encargo: EncargoTablero

    var body: some View {
        TarjetaOscura(ancho: AuroraNotch.anchoAgente) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Encargo · pendiente", color: TonoAura.reunion.rotulo)
                Text(encargo.titulo).font(AuroraNotch.titulo).tracking(-0.16).lineLimit(3).padding(.top, 2)
                Spacer(minLength: 4)
                Text("Quedó en el Tablero. Un agente lo toma cuando lo reclame.")
                    .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

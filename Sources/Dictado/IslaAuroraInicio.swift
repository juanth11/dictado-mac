import AppKit
import CoreServices
import DictadoKit
import Observation
import SwiftUI

// Pestaña Inicio: la música, el lanzador (apps, carpetas, atajos y espacios), la próxima reunión y los agentes que te esperan.

// MARK: - Apps más usadas

/// Las seis apps de Inicio: las más usadas según Spotlight (`"kMDItemUseCount" as CFString`), o las que fijes con el ajuste `isla.apps`.
/// Todo el trabajo (Spotlight, las carpetas de apps, los íconos) corre en un hilo aparte; el resultado queda en un caché
/// en disco para que la próxima vez aparezca al instante, y se recalcula como mucho cada 6 horas.
@MainActor @Observable
final class AppsUsadas {
    var apps: [EntradaApp] = []
    /// Las más usadas para el lanzador a pantalla completa (hasta `cuantasLanzador`); las `cuantas` primeras son `apps`.
    var usadas: [EntradaApp] = []
    var iconos: [String: NSImage] = [:]
    /// Todas las apps instaladas y la categoría de cada una (`LSApplicationCategoryType`, por id): de aquí salen las carpetas.
    var catalogo: [EntradaApp] = []
    var categorias: [String: String] = [:]

    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private var midiendo = false
    @ObservationIgnored private var ultima = Date.distantPast

    nonisolated static let cuantas = 6
    nonisolated static let cuantasLanzador = 36
    nonisolated static let vigencia: TimeInterval = 6 * 3600
    nonisolated static let cache = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/app.dictado/apps-usadas.json")
    nonisolated static let cacheCatalogo = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/app.dictado/apps-catalogo.json")

    init(vivo: Bool = true) {
        self.vivo = vivo
        guard vivo else { return }
        if let datos = try? Data(contentsOf: Self.cache),
           let guardadas = try? JSONDecoder().decode([EntradaGuardada].self, from: datos) {
            usadas = guardadas.map { EntradaApp(nombre: $0.nombre, ruta: $0.ruta, bundleID: $0.bundleID) }
            apps = Array(usadas.prefix(Self.cuantas))
            ultima = (try? FileManager.default.attributesOfItem(atPath: Self.cache.path)[.modificationDate]) as? Date ?? .distantPast
            pedirIconos()
        }
        if let datos = try? Data(contentsOf: Self.cacheCatalogo),
           let guardadas = try? JSONDecoder().decode([EntradaGuardada].self, from: datos) {
            catalogo = guardadas.map { EntradaApp(nombre: $0.nombre, ruta: $0.ruta, bundleID: $0.bundleID) }
            categorias = Dictionary(guardadas.compactMap { g in g.categoria.flatMap { c in g.bundleID.map { ($0, c) } } }, uniquingKeysWith: { a, _ in a })
        }
    }

    private struct EntradaGuardada: Codable { var nombre: String; var ruta: String; var bundleID: String?; var categoria: String? }

    /// Al abrir la isla: si el caché es viejo (o no hay), mide de nuevo sin bloquear nada.
    func refrescar() {
        guard vivo, !midiendo, apps.isEmpty || catalogo.isEmpty || Date().timeIntervalSince(ultima) > Self.vigencia else { return }
        midiendo = true
        let preferidas = Ajustes.fijasDeLaIsla + Ajustes.appsDeLaIsla   // las fijadas primero; el ranking salta las que no están instaladas
        Task.detached(priority: .utility) {
            let pares = Self.catalogoConCategorias()
            let lista = Self.medir(preferidas: preferidas, instaladas: pares.map(\.app), cuantas: Self.cuantasLanzador)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.midiendo = false
                self.ultima = Date()
                let seis = Array(lista.prefix(Self.cuantas))
                if !lista.isEmpty, lista != self.usadas { self.usadas = lista }
                if !lista.isEmpty, seis != self.apps { self.apps = seis }
                if !pares.isEmpty {
                    self.catalogo = pares.map(\.app)
                    self.categorias = Dictionary(pares.compactMap { p in p.categoria.flatMap { c in p.app.bundleID.map { ($0, c) } } }, uniquingKeysWith: { a, _ in a })
                }
                self.pedirIconos()
                let guardar = lista.map { EntradaGuardada(nombre: $0.nombre, ruta: $0.ruta, bundleID: $0.bundleID) }
                let guardarCatalogo = pares.map { EntradaGuardada(nombre: $0.app.nombre, ruta: $0.app.ruta, bundleID: $0.app.bundleID, categoria: $0.categoria) }
                Task.detached(priority: .utility) {
                    try? FileManager.default.createDirectory(at: Self.cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if let datos = try? JSONEncoder().encode(guardar) { try? datos.write(to: Self.cache, options: .atomic) }
                    if !guardarCatalogo.isEmpty, let datos = try? JSONEncoder().encode(guardarCatalogo) { try? datos.write(to: Self.cacheCatalogo, options: .atomic) }
                }
            }
        }
    }

    /// Para los renders: el catálogo ya armado.
    func fijar(catalogo: [EntradaApp], categorias: [String: String]) {
        self.catalogo = catalogo
        self.categorias = categorias
    }

    /// Pide (sin bloquear) los íconos de estas apps si aún no están (las de una carpeta, por ejemplo).
    func pedirIconos(de lista: [EntradaApp]) {
        let faltan = lista.filter { iconos[$0.id] == nil }.map { ($0.id, $0.ruta) }
        guard vivo, !faltan.isEmpty else { return }
        Task.detached(priority: .utility) {
            var salida: [String: NSImage] = [:]
            for (id, ruta) in faltan { salida[id] = CatalogoApps.icono(ruta) }
            let hecho = salida
            await MainActor.run { [weak self] in self?.iconos.merge(hecho) { $1 } }
        }
    }

    /// Para los renders: las apps ya elegidas y sus íconos.
    func fijar(_ lista: [EntradaApp], iconos: [String: NSImage]) {
        apps = lista
        usadas = lista
        self.iconos = iconos
    }

    func abrir(_ app: EntradaApp) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.ruta), configuration: NSWorkspace.OpenConfiguration())
    }

    private func pedirIconos() {
        let faltan = apps.filter { iconos[$0.id] == nil }.map { ($0.id, $0.ruta) }
        guard !faltan.isEmpty else { return }
        Task.detached(priority: .utility) {
            var salida: [String: NSImage] = [:]
            for (id, ruta) in faltan { salida[id] = CatalogoApps.icono(ruta) }
            let hecho = salida
            await MainActor.run { [weak self] in self?.iconos.merge(hecho) { $1 } }
        }
    }

    // MARK: Medición (fuera del hilo principal)

    /// Las apps instaladas con su categoría (se lee el Info.plist de cada una; fuera del hilo principal).
    nonisolated static func catalogoConCategorias() -> [(app: EntradaApp, categoria: String?)] {
        let propio = Bundle.main.bundleIdentifier ?? "app.dictado"
        return CatalogoApps.escanear(CatalogoApps.carpetas).filter { $0.bundleID != propio }.map {
            ($0, Bundle(path: $0.ruta)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String)
        }
    }

    nonisolated static func medir(preferidas: [String], instaladas: [EntradaApp]? = nil, cuantas: Int = AppsUsadas.cuantas) -> [EntradaApp] {
        let instaladas = instaladas ?? CatalogoApps.escanear(CatalogoApps.carpetas)
        let porID = Dictionary(instaladas.compactMap { a in a.bundleID.map { ($0, a) } }, uniquingKeysWith: { primera, _ in primera })
        // Las que ocultaste en el lanzador (clic derecho → Ocultar) tampoco salen en Inicio de la isla.
        let ocultas = Set(UserDefaults.dictado.stringArray(forKey: "lanzador.ocultas") ?? [])
        let ids = MasUsadas.ranking(usosSpotlight(), instaladas: Set(porID.keys),
                                    excluir: ocultas.union([Bundle.main.bundleIdentifier ?? "app.dictado"]),
                                    preferidas: preferidas, cuantas: cuantas)
        return ids.compactMap { porID[$0] }
    }

    /// `"kMDItemUseCount" as CFString` y `"kMDItemLastUsedDate" as CFString` de cada app que Spotlight conoce (consulta síncrona, en el hilo que la llama).
    nonisolated static func usosSpotlight() -> [UsoApp] {
        guard let consulta = MDQueryCreate(kCFAllocatorDefault, "kMDItemContentTypeTree == 'com.apple.application-bundle'" as CFString, nil, nil),
              MDQueryExecute(consulta, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var salida: [UsoApp] = []
        for i in 0..<MDQueryGetResultCount(consulta) {
            guard let crudo = MDQueryGetResultAtIndex(consulta, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(crudo).takeUnretainedValue()
            guard let usos = MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? Int, usos > 0,
                  let ruta = MDItemCopyAttribute(item, "kMDItemPath" as CFString) as? String,
                  let id = Bundle(path: ruta)?.bundleIdentifier else { continue }
            salida.append(UsoApp(bundleID: id, usos: usos, ultimoUso: MDItemCopyAttribute(item, "kMDItemLastUsedDate" as CFString) as? Date))
        }
        return salida
    }
}

// MARK: - La pestaña

/// Inicio: la música (la tarjeta principal), el lanzador, la próxima reunión y, a la derecha, los agentes o —con un bloque de foco
/// en curso— el foco. El reparto de ancho lo decide `DisposicionInicio` (en DictadoKit, con pruebas): nada se sale de los 178.
struct InicioAurora: View {
    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let fuentes: Fuentes?
    var foco: Foco?
    var apps: AppsUsadas?
    var lanzador: LanzadorIsla?
    var tablero: TableroIsla?
    let ahora: Date
    let acciones: AccionesIsla
    let simulado: Bool
    let ir: (EstadoIsla.Pestana) -> Void

    var body: some View {
        GeometryReader { g in
            let enFoco = foco?.activo != nil
            let d = DisposicionInicio.repartir(total: Double(g.size.width), separacion: Double(AuroraNotch.separacion), foco: enFoco)
            HStack(spacing: AuroraNotch.separacion) {
                MusicaAurora(musica: musica, fuentes: fuentes, foco: foco, acciones: acciones)
                    .frame(width: d.musica)
                if let apps, let lanzador {
                    LanzadorAurora(lanzador: lanzador, apps: apps, foco: foco, ancho: d.apps)
                        .frame(width: d.apps)
                }
                TarjetaReunion(agenda: agenda, ahora: ahora, ancho: d.reunion, acciones: acciones)
                if let foco, enFoco {
                    TarjetaFoco(foco: foco, acciones: acciones, ancho: d.derecha, ahoraFijo: simulado ? ahora : nil)
                } else {
                    ResumenAgentesAurora(claude: claude, agentes: agentes, tablero: tablero, ahora: ahora, ancho: d.derecha, acciones: acciones, ir: ir)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
    }
}

// MARK: - Música (las piezas viven en IslaAuroraMusica.swift)

/// El avance: tiempo escuchado, barra y tiempo que falta. Se redibuja una vez por segundo solo mientras suena; en pausa
/// es estático. Tocar o arrastrar salta a ese punto si la app lo acepta.
struct ProgresoAurora: View {
    let musica: Musica
    @State private var arrastre: Double?

    var body: some View {
        if musica.sonando {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in barra(ctx.date) }
        } else {
            barra(Date())
        }
    }

    private func barra(_ ahora: Date) -> some View {
        let pos = arrastre.map { $0 * musica.duracion } ?? musica.posicion(en: ahora)
        let fraccion = musica.duracion > 0 ? min(1, pos / musica.duracion) : 0
        return VStack(spacing: 4) {
            HStack {
                Text(Tiempo.reloj(pos))
                Spacer()
                if musica.duracion > 0 { Text("-" + Tiempo.reloj(max(0, musica.duracion - pos))) }
            }
            .font(.system(size: 8.5, weight: .bold)).monospacedDigit()
            .foregroundStyle(AuroraNotch.suave)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: g.size.width * fraccion)
                }
                .contentShape(Rectangle().inset(by: -6))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard musica.puedeSaltar, musica.duracion > 0, g.size.width > 0 else { return }
                        arrastre = max(0, min(1, v.location.x / g.size.width))
                    }
                    .onEnded { v in
                        guard musica.puedeSaltar, musica.duracion > 0, g.size.width > 0 else { return }
                        musica.saltar(a: max(0, min(1, v.location.x / g.size.width)) * musica.duracion)
                        arrastre = nil
                    })
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Avance: \(Tiempo.reloj(pos)) de \(Tiempo.reloj(musica.duracion))")
    }
}

// MARK: - Próxima reunión

extension Agenda {
    /// La reunión de hoy que sigue (en curso o por empezar), con invitados o enlace; nil si no queda ninguna.
    func proximaReunion(ahora: Date, calendario: Calendar = .current) -> Evento? {
        eventos.first { $0.esReunion && $0.fin > ahora && calendario.isDate($0.inicio, inSameDayAs: ahora) }
    }
}

/// La tarjeta azul de la próxima reunión: "Empieza en" con la cuenta en puntos, el título, la hora y quiénes van, y
/// Unirse y Abrir. Sin reunión cerca, dice cuándo cambia lo libre por lo ocupado. La usan Inicio (angosta: cuenta, título y
/// Unirse) y Agenda (entera).
struct TarjetaReunion: View {
    let agenda: Agenda
    let ahora: Date
    var ancho: CGFloat? = AuroraNotch.anchoReunion
    let acciones: AccionesIsla

    /// Más angosta de 190: sin quiénes van y con Abrir como ícono.
    private var angosta: Bool { (ancho ?? .infinity) < 190 }

    var body: some View {
        if let e = agenda.proximaReunion(ahora: ahora) {
            conReunion(e)
        } else {
            sinReunion
        }
    }

    /// "Carla y 3 más", "Carla", o el servicio de la videollamada si no hay invitados.
    private func quienes(_ e: Agenda.Evento) -> String {
        let nombres = e.invitados.map { String($0.split(separator: " ").first ?? "") }.filter { !$0.isEmpty }
        guard let primero = nombres.first else { return e.enlace.map { Tiempo.servicio($0.host ?? "") } ?? "" }
        return nombres.count > 1 ? "\(primero) y \(nombres.count - 1) más" : primero
    }

    private func conReunion(_ e: Agenda.Evento) -> some View {
        let enCurso = e.inicio <= ahora
        let cuenta = enCurso ? CuentaRegresiva.texto(hasta: e.fin, desde: ahora) : CuentaRegresiva.texto(hasta: e.inicio, desde: ahora)
        return TarjetaAura(tono: .reunion, ancho: ancho) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    RotuloPieza(enCurso ? "Termina en" : "Empieza en", color: TonoAura.reunion.rotulo)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        NumeroPuntos(texto: cuenta?.texto ?? "0")
                        Text(cuenta?.unidad ?? "min").font(.system(size: 9, weight: .semibold)).foregroundStyle(AuroraNotch.sutil)
                    }
                }
                Spacer(minLength: 0)
                Text(e.titulo).font(angosta ? AuroraNotch.tituloTarea : AuroraNotch.titulo).tracking(-0.16).help(e.titulo)
                    .lineLimit(angosta ? 2 : 1).fixedSize(horizontal: false, vertical: angosta)
                Text(angosta ? Frase.hora(e.inicio) + " – " + Frase.hora(e.fin)
                             : [Frase.hora(e.inicio) + " – " + Frase.hora(e.fin), quienes(e)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(1)
                    .padding(.top, 1)
                if !angosta, let lugar = e.lugar { EtiquetaLugar(lugar: lugar).padding(.top, 1) }
                HStack(spacing: 4) {
                    if let enlace = e.enlace {
                        BotonAura("Unirse", icono: "video.fill", estilo: .lleno, compacto: angosta, ayuda: "Unirse a la videollamada: \(e.titulo)") { acciones.unirse(enlace) }
                    }
                    if angosta {
                        BotonAura(icono: "arrow.up.forward", redondo: true, compacto: true, ayuda: "Abrir «\(e.titulo)» en el calendario") { AbrirCalendario.evento(e) }
                    } else {
                        BotonAura("Abrir", ayuda: "Abrir «\(e.titulo)» en el calendario") { AbrirCalendario.evento(e) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, angosta ? 8 : 8)
            }
        }
    }

    private var sinReunion: some View {
        let cambio = CambioAgenda.proximo(ocupados: agenda.eventos.filter(\.ocupado).map { Intervalo(inicio: $0.inicio, fin: $0.fin) }, ahora: ahora)
        let frase: String
        if let c = cambio.cambio {
            let dia = Calendar.current.isDate(c, inSameDayAs: ahora) ? "" : " " + FormatoHuecos.dia(c)
            frase = (cambio.ocupadoAhora ? "Ocupado hasta " : "Libre hasta ") + FormatoHuecos.hora(c).texto + " " + FormatoHuecos.hora(c).periodo + dia
        } else {
            frase = "Nada más en la agenda"
        }
        return TarjetaAura(tono: .reunion, ancho: ancho) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Reuniones", color: TonoAura.reunion.rotulo)
                Spacer(minLength: 0)
                Text("Sin reuniones hoy").font(angosta ? AuroraNotch.tituloTarea : AuroraNotch.titulo).tracking(-0.16).lineLimit(2)
                Text(frase).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen).lineLimit(2).padding(.top, 1)
                HStack(spacing: 4) {
                    BotonAura("Abrir", compacto: angosta, ayuda: "Abrir el día en el calendario") { AbrirCalendario.dia(ahora) }
                    Spacer(minLength: 0)
                }
                .padding(.top, angosta ? 8 : 8)
            }
        }
    }
}

// MARK: - Agentes (resumen)

/// La tarjeta de agentes: el dial (se llena con el contexto de la sesión que más trabaja; la chispa de Claude gira mientras
/// alguna trabaja y late si una te espera), cuántos esperan tu sí y Revisar, que lleva a la pestaña Agentes. De 160 para arriba
/// suma hasta dos de lo que espera y el micrófono para dictar. Quieta (y a 0 % de CPU) si nada trabaja ni espera.
struct ResumenAgentesAurora: View {
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    var tablero: TableroIsla?
    var ahora = Date()
    /// nil: toma el ancho que le den (el bloque del lanzador).
    var ancho: CGFloat?
    let acciones: AccionesIsla
    let ir: (EstadoIsla.Pestana) -> Void

    private struct Pendiente: Identifiable {
        let id: String
        let nombre: String
        let accion: String
    }

    /// Lo que te espera: las decisiones abiertas del Tablero (si hay lectura vigente), las sesiones que piden tu respuesta y los agentes con alerta.
    private func pendientes(_ t: Tablero?) -> [Pendiente] {
        (t?.decisiones.map { Pendiente(id: "d\($0.id)", nombre: $0.encargoTitulo ?? $0.pregunta, accion: "decidir") } ?? [])
            + claude.esperando.map { Pendiente(id: "s" + $0.id, nombre: $0.nombre, accion: "responder") }
            + agentes.agentes.filter { $0.estado == .alerta || $0.estado == .caido }.map { Pendiente(id: "a" + $0.nombre, nombre: $0.nombre, accion: "ver") }
    }

    private var angosta: Bool { (ancho ?? .infinity) < 190 }

    var body: some View {
        let cuentas = CuentasAgentes.de(claude: claude, agentes: agentes, tablero: tablero, ahora: ahora)
        let t = tablero?.vigente(ahora: ahora)
        let espera = pendientes(t)
        let trabajando = cuentas.trabajando
        let esperan = cuentas.esperan
        let total = t.map { max(1, $0.enCurso.count) } ?? max(1, claude.sesiones.count)
        // El anillo: el contexto de la sesión que más usa (de 0 a 1 M de tokens); sin sesiones medidas, cuántas trabajan del total.
        let contexto = claude.sesiones.filter { $0.estado == .trabajando }.map(\.contexto).max() ?? 0
        let valor = contexto > 0 ? min(1, Double(contexto) / 1_000_000) : Double(trabajando) / Double(total)
        let modo: ChispaViva.Modo = esperan > 0 ? .espera : (trabajando > 0 ? .trabaja : .quieta)
        let grande = esperan > 0 ? esperan : trabajando
        let leyenda = esperan > 0 ? (esperan == 1 ? "espera tu sí" : "esperan tu sí") : (trabajando > 0 ? (trabajando == 1 ? "trabaja" : "trabajan") : "en calma")
        TarjetaAura(tono: esperan == 0 ? .trabaja : .agentes, ancho: ancho) {
            VStack(alignment: .leading, spacing: 0) {
                RotuloPieza("Agentes", color: (esperan == 0 ? TonoAura.trabaja : TonoAura.agentes).rotulo)
                HStack(spacing: 8) {
                    ZStack {
                        AnilloLatido(activo: esperan > 0, lado: 46)
                        Dial(lado: 46, valor: valor, colores: [.white.opacity(0.8), .white], marcas: 30, anillo: 4, brillo: 0.2, destello: false) {
                            ChispaViva(modo: modo, lado: 20)
                        }
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 0) {
                        NumeroFino(texto: "\(grande)", tamano: 30, peso: .thin)
                        Text(leyenda).font(.system(size: 10, weight: .semibold)).foregroundStyle(AuroraNotch.resumen).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(trabajando) trabajando, \(esperan) esperan tu sí")
                Spacer(minLength: 0)
                if !angosta {
                    VStack(spacing: 2) {
                        ForEach(espera.prefix(2)) { p in
                            HStack {
                                Text(p.nombre).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(p.accion).foregroundStyle(.white.opacity(0.6))
                            }
                            .font(AuroraNotch.fila)
                        }
                    }
                }
                HStack(spacing: 4) {
                    BotonAura("Revisar", estilo: .lleno, compacto: angosta, ayuda: "Ver los agentes y sesiones") { ir(.agentes) }
                    Spacer(minLength: 0)
                    if !angosta {
                        BotonAura(icono: "mic.fill", redondo: true, ayuda: "Dictar un encargo", accion: cuentas.deTablero ? acciones.dictarEncargo : acciones.dictar)
                    }
                }
                .padding(.top, angosta ? 4 : 8)
            }
        }
    }
}

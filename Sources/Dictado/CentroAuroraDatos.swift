import AppKit
import DictadoKit
import Observation
import SwiftUI

// Los datos del Centro a pantalla completa. Es la vista grande de lo mismo que ya ven la isla y el Dock: el Tablero (`TableroIsla`),
// las tareas (`TareasIsla`), la agenda, las sesiones de Claude y Salud; aquí solo se suman el historial de corridas y las notas de
// reunión, que únicamente se leen mientras el Centro está abierto. Nada se cura a mano: todo se lee solo y se suelta al cerrar.

/// Las diez secciones del Centro nuevo (⌘1 a ⌘9 y ⌘0): Hoy (la mañana: foco, agenda, correos, inbox y radar) va primero y es la que abre antes
/// del mediodía; Tablero, Semana, Reuniones y Mac son las de siempre; Consumo, Herramientas, Finanzas, Noticias y Automatizaciones leen del
/// paquete `centro` solo mientras están a la vista.
enum SeccionAurora: String, CaseIterable {
    case hoy, tablero, semana, reuniones, mac, consumo, herramientas, finanzas, noticias, automatizaciones

    var titulo: String {
        switch self {
        case .hoy: return "Hoy"
        case .tablero: return "Tablero"
        case .semana: return "Semana"
        case .reuniones: return "Reuniones"
        case .mac: return "Mac"
        case .consumo: return "Consumo"
        case .herramientas: return "Herramientas"
        case .finanzas: return "Finanzas"
        case .noticias: return "Noticias"
        case .automatizaciones: return "Automatizaciones"
        }
    }

    var simbolo: String {
        switch self {
        case .hoy: return "sun.horizon"
        case .tablero: return "square.grid.3x1.below.line.grid.1x2"
        case .semana: return "calendar"
        case .reuniones: return "person.2.wave.2"
        case .mac: return "macbook"
        case .consumo: return "chart.bar.xaxis"
        case .herramientas: return "wrench.and.screwdriver"
        case .finanzas: return "banknote"
        case .noticias: return "newspaper"
        case .automatizaciones: return "clock.arrow.2.circlepath"
        }
    }

    /// ⌘1 a ⌘9 para las nueve primeras y ⌘0 para la décima.
    var atajo: String { "⌘\(((Self.allCases.firstIndex(of: self) ?? 0) + 1) % 10)" }

    /// La sección de un atajo (la tecla sin ⌘): "1" a "9" y "0".
    static func deAtajo(_ tecla: String?) -> SeccionAurora? {
        guard let tecla, tecla.count == 1, let n = Int(tecla) else { return nil }
        let i = (n + 9) % 10
        return allCases.indices.contains(i) ? allCases[i] : nil
    }
}

/// Dónde está parado el Centro: la sección, el día del historial, la semana, la reunión elegida. Todo se olvida al cerrar.
@MainActor @Observable
final class NavegacionAurora {
    var seccion: SeccionAurora
    /// El día elegido del historial (0 = hoy).
    var dia = 0
    /// 0 = esta semana, 1 = la que viene.
    var semana = 0
    var reunion: String?
    var descartadoAbierto = false
    var correoCopiado = false
    var disponibilidadCopiada = false
    /// Consumo: lo que miden las barras (costo o tokens).
    var medidaConsumo = ConsumoCentro.Medida.costo
    /// Herramientas: qué skills se ven.
    var filtroSkills = HerramientasCentro.Filtro.todo
    /// Noticias: el vertical elegido (nil = todos).
    var verticalNoticias: String?
    /// Cierra con un fundido hecho por SwiftUI (sin animar la ventana, que se quedaría con ella).
    var saliendo = false

    /// Antes del mediodía abre en Hoy; después, en el Tablero.
    init(ahora: Date = Date()) {
        seccion = HoyCentro.abreEnHoy(ahora: ahora) ? .hoy : .tablero
    }
}

/// El minuto del Centro: se actualiza con el mismo reloj de una vez por minuto que refresca los datos, mientras la ventana está a la vista.
@MainActor @Observable
final class RelojCentro {
    var ahora = Date()
}

// MARK: - Historial de corridas

@MainActor @Observable
final class HistorialTableroModelo {
    /// nil = no se pudo leer (sin centro o el comando falló): el Tablero cae a lo que se ve directo.
    private(set) var corridas: [CorridaTablero]?
    private(set) var leido: Date?
    private(set) var cargando = false

    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private var ultimaPeticion: Date?
    nonisolated static let limite = 500
    nonisolated static let limiteLeer: TimeInterval = 10

    init(vivo: Bool = true) { self.vivo = vivo }

    /// `corrida listar --estado todas --limite 500 --json`, fuera del hilo principal y con tope de tiempo; como mucho una vez por minuto.
    func refrescar(forzar: Bool = false) {
        guard vivo, !cargando, let carpeta = TareasIsla.carpetaCentro else { return }
        guard forzar || TableroCentro.tocaPedir(ultima: ultimaPeticion, ahora: Date()) else { return }
        ultimaPeticion = Date()
        cargando = true
        Task.detached(priority: .userInitiated) {
            let r = CentroStore.correr(URL(fileURLWithPath: "/usr/bin/python3"),
                                       ["-m", "centro", "corrida", "listar", "--estado", "todas", "--limite", String(Self.limite), "--json"],
                                       limite: Self.limiteLeer, carpeta: carpeta)
            let lista = r.error == nil ? TableroCentro.decodificarCorridas(r.datos) : nil
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cargando = false
                self.corridas = lista
                self.leido = lista == nil ? nil : Date()
            }
        }
    }

    /// Para los renders: lo que se muestra, sin leer nada.
    func fijar(_ corridas: [CorridaTablero]?, leido: Date = Date()) {
        self.corridas = corridas
        self.leido = corridas == nil ? nil : leido
    }

    func soltar() {
        corridas = nil
        leido = nil
    }
}

// MARK: - Notas de reunión

@MainActor @Observable
final class ReunionesModelo {
    private(set) var actas: [ActaReunion] = []
    private(set) var cargando = false
    private(set) var leida = false

    @ObservationIgnored private let carpeta: URL?
    @ObservationIgnored private let vivo: Bool
    /// La carpeta de las notas (el inbox): de ahí se abren o se muestran en el Finder.
    var carpetaNotas: URL? { carpeta }
    /// Las más recientes que se leen (el resto no se abre) y el tope de tamaño de una nota.
    nonisolated static let maximo = 60
    nonisolated static let maximoBytes = 400_000

    /// `carpeta`: la que tiene los `reunion-*.md`, como hacen `Pendientes` y `NotasReunion` (la carpeta del inbox de Dictado).
    init(carpeta: URL? = Ajustes().carpetaInbox, vivo: Bool = true) {
        self.carpeta = carpeta
        self.vivo = vivo
    }

    func refrescar() {
        guard vivo, !cargando, let carpeta else { return }
        cargando = true
        Task.detached(priority: .userInitiated) {
            let actas = Self.leer(carpeta)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cargando = false
                self.actas = actas
                self.leida = true
            }
        }
    }

    /// Lista la carpeta, toma las `reunion-*.md` más recientes y las interpreta. Sin hilo principal.
    nonisolated static func leer(_ carpeta: URL) -> [ActaReunion] {
        let fm = FileManager.default
        let archivos = (try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let candidatos = archivos.filter { $0.lastPathComponent.hasPrefix("reunion-") && $0.pathExtension == "md" }
            .map { url -> (URL, Date) in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maximo)
        var actas: [ActaReunion] = []
        for (url, _) in candidatos {
            if let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize), bytes > maximoBytes { continue }
            guard let texto = try? String(contentsOf: url, encoding: .utf8),
                  let acta = LectorActa.interpretar(texto, archivo: url.lastPathComponent) else { continue }
            actas.append(acta)
        }
        return LectorActa.ordenar(actas)
    }

    /// Para los renders y las pruebas: lo que se muestra, sin leer nada.
    func fijar(_ actas: [ActaReunion]) {
        self.actas = LectorActa.ordenar(actas)
        leida = true
    }

    func soltar() {
        actas = []
        leida = false
    }
}

// MARK: - Todo junto

/// Lo que cada sección necesita. Los objetos de la isla (agenda, sesiones, Tablero, tareas, Salud) se comparten; los del historial y las
/// reuniones son del Centro y se sueltan al cerrar.
@MainActor
final class DatosCentro {
    let agenda: Agenda
    let claude: SesionesClaude
    let tablero: TableroIsla
    let tareas: TareasIsla
    let salud: EstadoSalud
    let historial: HistorialTableroModelo
    let reuniones: ReunionesModelo
    let lecturas: LecturasCentro
    /// El estado del día que lee Hoy (brief, noticias, inbox y la capa privada de la mañana): el mismo comando que alimenta el Centro clásico.
    let hoy: CentroStore
    /// Lo que ya quedó hecho hoy en los bloques de foco (los títulos), para marcar las prioridades del brief.
    var focoHechas: () -> Set<String> = { [] }
    let reloj = RelojCentro()
    /// La sección a la vista: solo ella se lee (las demás esperan a que las abras).
    var seccionVisible = SeccionAurora.tablero
    private var ultimaLecturaHoy: Date?
    var config: ConfigHuecos
    /// El espacio actual de la isla (Trabajo, Foco…), para el chip del encabezado.
    var espacio: () -> String?
    /// La línea `fondo:` del espacio actual (el fondo que ese espacio le da al lanzador y al Centro); nil = el global.
    var fondoEspacio: () -> String? = { nil }

    /// Los que piden la app (medir y analizar Salud; son de ella, no del Centro).
    var medirSalud: () -> Void = {}
    var analizarSalud: () -> Void = {}

    init(agenda: Agenda, claude: SesionesClaude, tablero: TableroIsla, tareas: TareasIsla, salud: EstadoSalud, historial: HistorialTableroModelo? = nil,
         reuniones: ReunionesModelo? = nil, lecturas: LecturasCentro? = nil, hoy: CentroStore? = nil, config: ConfigHuecos? = nil, espacio: @escaping () -> String? = { Ajustes.espacioDeLaIsla }) {
        self.agenda = agenda
        self.claude = claude
        self.tablero = tablero
        self.tareas = tareas
        self.salud = salud
        self.historial = historial ?? HistorialTableroModelo()
        self.reuniones = reuniones ?? ReunionesModelo()
        self.lecturas = lecturas ?? LecturasCentro()
        self.hoy = hoy ?? CentroStore()
        self.config = config ?? Ajustes().huecos
        self.espacio = espacio
    }

    /// Al abrir: lee todo lo que la ventana muestra (cada pieza respeta su propio tope de frecuencia).
    func abrir() {
        reloj.ahora = Date()
        agenda.refrescar()
        tareas.refrescar()
        tablero.refrescar()
        historial.refrescar(forzar: true)
        reuniones.refrescar()
        leer(seccionVisible)
        medirSalud()
        analizarSalud()
    }

    /// El minuto: el único reloj del Centro. Refresca lo que cambia (el Tablero, las tareas, la agenda, Salud) y las horas que se muestran.
    func minuto() {
        reloj.ahora = Date()
        agenda.refrescar()
        tareas.refrescar()
        tablero.refrescar(forzar: true)
        historial.refrescar(forzar: true)
        reuniones.refrescar()
        leer(seccionVisible)
        medirSalud()
    }

    /// Cambió la sección a la vista: se lee esa (respetando su frecuencia).
    func visitar(_ s: SeccionAurora) {
        seccionVisible = s
        leer(s)
    }

    /// Lee lo de la sección a la vista. Hoy usa el comando del centro (por SSH al VPS y lo local): como mucho una vez cada cinco minutos.
    private func leer(_ s: SeccionAurora) {
        lecturas.leer(s)
        guard s == .hoy, hoy.configurado, !hoy.cargando else { return }
        let ahora = Date()
        if let u = ultimaLecturaHoy, ahora.timeIntervalSince(u) < 300 { return }
        ultimaLecturaHoy = ahora
        hoy.actualizar()
    }

    func soltar() {
        historial.soltar()
        reuniones.soltar()
        lecturas.soltar()
        hoy.estado = nil
    }

    // MARK: Cuentas

    /// Lo que trabaja: del Tablero si hay lectura vigente; si no, las sesiones de Claude que se ven directo.
    func trabajando(ahora: Date) -> Int {
        tablero.vigente(ahora: ahora).map { $0.trabajando } ?? claude.trabajando
    }

    /// Lo que espera tu sí: las decisiones abiertas del Tablero y las sesiones que piden permiso.
    func esperan(ahora: Date) -> Int {
        (tablero.vigente(ahora: ahora)?.decisiones.count ?? 0) + claude.esperando.count
    }

    /// Las tareas de hoy (las que vencen hoy o antes y las sin fecha).
    func tareasHoy(ahora: Date) -> Int {
        SemanaCentro.tareasDeHoy(tareasSemana(), ahora: ahora)
    }

    func tareasSemana() -> [TareaSemana] {
        tareas.lista.map { TareaSemana(id: $0.id, texto: $0.texto, vence: tareas.vencimientos[$0.id]) }
    }

    func frase(ahora: Date) -> String {
        FraseCentro.estado(trabajando: trabajando(ahora: ahora), esperan: esperan(ahora: ahora), tareasHoy: tareas.lista.isEmpty && tareas.cargando ? nil : tareasHoy(ahora: ahora))
    }

    /// El aviso del riel: lo que espera tu sí. (Lo programado que pide atención se ve dentro de Automatizaciones: en el riel no cabe sin recortar el nombre.)
    func aviso(_ s: SeccionAurora, ahora: Date) -> Int { s == .tablero ? esperan(ahora: ahora) : 0 }
}

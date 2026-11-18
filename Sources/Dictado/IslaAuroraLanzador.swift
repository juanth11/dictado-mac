import AppKit
import DictadoKit
import Observation
import SwiftUI

// El lanzador de Inicio: una fila de espacios (Trabajo, Foco, Mañana, Descanso) y debajo una rejilla de mosaicos con dos
// secciones, Apps (carpetas y las más usadas) y Atajos (los de la app Atajos de Apple). Una carpeta se abre en el sitio, con
// un chip para volver; no hay ventanas ni menús flotantes. Los datos del dueño viven en `carpetas.txt` y `espacios.txt`
// (Application Support/Dictado) y en el ajuste `isla.atajos`. Todo lo que toca disco o procesos corre fuera del hilo principal.

// MARK: - Mosaicos

enum MosaicoInicio: Identifiable {
    case app(EntradaApp)
    case carpeta(CarpetaApps, [EntradaApp])
    case atajo(String)

    var id: String {
        switch self {
        case .app(let a): return "app:" + a.id
        case .carpeta(let c, _): return "carpeta:" + c.nombre
        case .atajo(let n): return "atajo:" + n
        }
    }

    /// Con qué nombres puede referirse a él un espacio (`primero:`).
    var claves: [String] {
        switch self {
        case .app(let a): return [a.nombre, a.bundleID ?? ""]
        case .carpeta(let c, let r): return [c.nombre] + r.flatMap { [$0.nombre, $0.bundleID ?? ""] }
        case .atajo(let n): return [n]
        }
    }

    var apps: [EntradaApp] {
        switch self {
        case .app(let a): return [a]
        case .carpeta(_, let r): return Array(r.prefix(4))
        case .atajo: return []
        }
    }
}

// MARK: - Modelo

@MainActor @Observable
final class LanzadorIsla {
    enum Seccion: Int { case apps, atajos }
    enum EstadoAtajo: Equatable { case corriendo, listo, fallo(String) }

    var seccion = Seccion.apps
    var carpetaAbierta: String?
    var pagina = 0
    var carpetas: [CarpetaApps] = []
    var espacios: [EspacioIsla] = []
    var espacioActual: String?
    var todosLosAtajos: [String] = []
    var cargandoAtajos = false
    var estados: [String: EstadoAtajo] = [:]

    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private var ultimaLectura = Date.distantPast
    @ObservationIgnored private var ultimaLecturaEspacios = Date.distantPast
    @ObservationIgnored private var leyendoEspacios = false

    nonisolated static let cacheAtajos = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/app.dictado/atajos.json")
    /// Una lectura nueva (archivos y lista de atajos) como mucho cada tanto, aunque la isla se abra a cada rato.
    nonisolated static let vigencia: TimeInterval = 20
    nonisolated static let segundosListo: Double = 2.5
    nonisolated static let segundosFallo: Double = 8
    nonisolated static var porPagina: Int { AuroraNotch.columnasLanzador * AuroraNotch.filasLanzador }
    /// Con el lanzador ancho (la música compacta) caben cinco columnas.
    nonisolated static func columnas(ancho: CGFloat) -> Int { ancho >= AuroraNotch.anchoLanzadorAncho ? AuroraNotch.columnasLanzadorAncho : AuroraNotch.columnasLanzador }

    init(vivo: Bool = true) {
        self.vivo = vivo
        guard vivo else { return }
        espacioActual = Ajustes.espacioDeLaIsla
        if let datos = try? Data(contentsOf: Self.cacheAtajos), let lista = try? JSONDecoder().decode([String].self, from: datos) { todosLosAtajos = lista }
    }

    /// Para los renders.
    func fijar(carpetas: [CarpetaApps], espacios: [EspacioIsla], espacio: String?, atajos: [String], estados: [String: EstadoAtajo] = [:],
               seccion: Seccion = .apps, carpetaAbierta: String? = nil) {
        self.carpetas = carpetas
        self.espacios = espacios
        self.espacioActual = espacio
        self.todosLosAtajos = atajos
        self.estados = estados
        self.seccion = seccion
        self.carpetaAbierta = carpetaAbierta
    }

    // MARK: Archivos

    nonisolated static var archivoCarpetas: URL { Ajustes.archivoVocabulario.deletingLastPathComponent().appendingPathComponent("carpetas.txt") }
    nonisolated static var archivoEspacios: URL { Ajustes.archivoVocabulario.deletingLastPathComponent().appendingPathComponent("espacios.txt") }

    /// Crea `carpetas.txt` con el reparto automático si no existe (se lee el Info.plist de cada app: no usar en el hilo principal).
    nonisolated static func asegurarCarpetas() {
        guard !FileManager.default.fileExists(atPath: archivoCarpetas.path) else { return }
        let reparto = CarpetasApps.agrupar(AppsUsadas.catalogoConCategorias())
        guard !reparto.isEmpty else { return }   // sin catálogo no se escribe nada: se vuelve a intentar la próxima vez
        try? FileManager.default.createDirectory(at: archivoCarpetas.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? CarpetasApps.texto(reparto).write(to: archivoCarpetas, atomically: true, encoding: .utf8)
    }

    nonisolated static func asegurarEspacios() {
        guard !FileManager.default.fileExists(atPath: archivoEspacios.path) else { return }
        try? FileManager.default.createDirectory(at: archivoEspacios.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? EspaciosIsla.inicial.write(to: archivoEspacios, atomically: true, encoding: .utf8)
    }

    // MARK: Al abrir la isla

    /// Vuelve a la primera página y lee de nuevo archivos y atajos (sin bloquear; con tope de frecuencia).
    func alAbrir() {
        carpetaAbierta = nil
        pagina = 0
        guard vivo, Date().timeIntervalSince(ultimaLectura) > Self.vigencia else { return }
        ultimaLectura = Date()
        Task.detached(priority: .utility) {
            Self.asegurarEspacios()
            Self.asegurarCarpetas()
            let c = CarpetasApps.leer((try? String(contentsOf: Self.archivoCarpetas, encoding: .utf8)) ?? "")
            let leidos = EspaciosIsla.leer((try? String(contentsOf: Self.archivoEspacios, encoding: .utf8)) ?? "")
            let e = leidos.isEmpty ? EspaciosIsla.leer(EspaciosIsla.inicial) : leidos
            await MainActor.run { [weak self] in
                guard let self else { return }
                if c != self.carpetas { self.carpetas = c }
                if e != self.espacios { self.espacios = e }
                if let actual = self.espacioActual, !e.contains(where: { $0.nombre == actual }) { self.espacioActual = nil }
            }
        }
        guard !cargandoAtajos else { return }
        cargandoAtajos = true
        Task.detached(priority: .utility) {
            let r = ProcesoAtajos.ejecutar(["list"], limite: AtajosSistema.segundosLista)
            let lista = r.codigo == 0 ? AtajosSistema.analizarLista(r.salida) : nil
            if let lista, let datos = try? JSONEncoder().encode(lista) {
                try? FileManager.default.createDirectory(at: Self.cacheAtajos.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? datos.write(to: Self.cacheAtajos, options: .atomic)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cargandoAtajos = false
                if let lista, lista != self.todosLosAtajos { self.todosLosAtajos = lista }
            }
        }
    }

    /// Lee `espacios.txt` (y lo crea si falta) fuera del hilo principal, con el mismo tope de frecuencia que `alAbrir`. Lo usa el
    /// Dock, que comparte los espacios con la isla pero no necesita los atajos ni las carpetas de apps.
    func leerEspacios() {
        guard vivo, !leyendoEspacios, Date().timeIntervalSince(ultimaLecturaEspacios) > Self.vigencia else { return }
        leyendoEspacios = true
        ultimaLecturaEspacios = Date()
        Task.detached(priority: .utility) {
            Self.asegurarEspacios()
            let leidos = EspaciosIsla.leer((try? String(contentsOf: Self.archivoEspacios, encoding: .utf8)) ?? "")
            let e = leidos.isEmpty ? EspaciosIsla.leer(EspaciosIsla.inicial) : leidos
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.leyendoEspacios = false
                if e != self.espacios { self.espacios = e }
                if let actual = self.espacioActual, !e.contains(where: { $0.nombre == actual }) { self.espacioActual = nil }
            }
        }
    }

    /// Pone (o quita, con nil) el fondo de un espacio: se ve al instante y se escribe en `espacios.txt` (fuera del hilo principal; lo demás
    /// del archivo queda como está).
    func fijarFondo(_ fondo: FondoLanzador?, espacio nombre: String) {
        if let i = espacios.firstIndex(where: { $0.nombre == nombre }) { espacios[i].fondo = fondo?.texto }
        guard vivo else { return }
        Task.detached(priority: .utility) {
            Self.asegurarEspacios()
            let actual = (try? String(contentsOf: Self.archivoEspacios, encoding: .utf8)) ?? ""
            let nuevo = EspaciosIsla.conFondo(actual, espacio: nombre, fondo: fondo)
            guard nuevo != actual else { return }
            try? nuevo.write(to: Self.archivoEspacios, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Lo que se ve

    var espacio: EspacioIsla? { espacios.first { $0.nombre == espacioActual } }

    var atajosVisibles: [String] { AtajosSistema.elegir(todos: todosLosAtajos, preferidos: Ajustes.atajosDeLaIsla) }

    func mosaicos(_ apps: AppsUsadas) -> [MosaicoInicio] {
        switch seccion {
        case .atajos:
            return PrioridadInicio.ordenar(atajosVisibles.map(MosaicoInicio.atajo), claves: \.claves, primero: espacio?.primero ?? [])
        case .apps:
            return Self.mosaicosDeApps(carpetas: carpetas, catalogo: apps.catalogo, masUsadas: apps.apps, espacio: espacio, carpetaAbierta: carpetaAbierta)
        }
    }

    /// Las apps de Inicio y del lanzador a pantalla completa, de las mismas fuentes: primero las fijadas (`isla.fijas`; Spotify por
    /// omisión), luego las carpetas de `carpetas.txt` (cada una un mosaico que se abre en el sitio) y al final las más usadas; el
    /// espacio activo puede adelantar lo suyo. Con una carpeta abierta, solo sus apps.
    static func mosaicosDeApps(carpetas: [CarpetaApps], catalogo: [EntradaApp], masUsadas: [EntradaApp], espacio: EspacioIsla?,
                               carpetaAbierta: String?) -> [MosaicoInicio] {
        var lista: [MosaicoInicio]
        if let nombre = carpetaAbierta, let c = carpetas.first(where: { $0.nombre == nombre }) {
            lista = CarpetasApps.resolver(c, instaladas: catalogo).map(MosaicoInicio.app)
        } else {
            let ids = Set(catalogo.compactMap(\.bundleID))
            let fijasIDs = MasUsadas.conFijas(fijas: Ajustes.fijasDeLaIsla, instaladas: ids, resto: []).filter { ids.contains($0) }
            let fijas = fijasIDs.compactMap { id in catalogo.first { $0.bundleID == id } }
            let fijasSet = Set(fijas.map(\.id))
            lista = fijas.map(MosaicoInicio.app) + carpetas.compactMap { c in
                let r = CarpetasApps.resolver(c, instaladas: catalogo)
                return r.isEmpty ? nil : MosaicoInicio.carpeta(c, r)
            } + masUsadas.filter { !fijasSet.contains($0.id) }.map(MosaicoInicio.app)
        }
        return PrioridadInicio.ordenar(lista, claves: \.claves, primero: espacio?.primero ?? [])
    }

    func elegir(_ s: Seccion) {
        seccion = s
        carpetaAbierta = nil
        pagina = 0
    }

    func abrir(carpeta: String) {
        carpetaAbierta = carpeta
        pagina = 0
    }

    func cerrarCarpeta() {
        carpetaAbierta = nil
        pagina = 0
    }

    // MARK: Espacios

    /// Elegir el espacio que ya está activo lo quita (queda sin espacio, sin tocar ningún ajuste).
    func elegirEspacio(_ e: EspacioIsla, foco: Foco?) {
        if espacioActual == e.nombre {
            espacioActual = nil
            if vivo { Ajustes.espacioDeLaIsla = nil; EspaciosAcciones.cambio(a: nil) }
            pagina = 0
            return
        }
        espacioActual = e.nombre
        pagina = 0
        guard vivo else { return }
        Ajustes.espacioDeLaIsla = e.nombre
        aplicar(e, foco: foco)
        EspaciosAcciones.cambio(a: e)   // fondo de pantalla, abrir y reproducir (Espacios.swift)
    }

    /// Lo que hace un espacio al activarse: solo ajustes de la propia app (velo, teclas, un bloque de foco) y, si el dueño lo
    /// puso en `espacios.txt`, un atajo de Apple. Lo que el archivo no menciona no se toca.
    private func aplicar(_ e: EspacioIsla, foco: Foco?) {
        switch e.velo {
        case .sinCambio: break
        case .apagado: Velo.apagar()
        case .encendido(let modo):
            if !Funcion.velo.activa { Funcion.velo.poner(true) }
            Velo.encender(modo: modo.flatMap(ModoVelo.init(rawValue:)))
        }
        switch e.teclas {
        case .sinCambio: break
        case .apagado: if Funcion.teclas.activa { Funcion.teclas.poner(false) }
        case .encendido(let perfil):
            if let p = perfil.flatMap(PerfilTeclas.init(rawValue:)) {
                UserDefaults.dictado.set(p.rawValue, forKey: "teclas.perfil")
                if Funcion.teclas.activa { Teclas.shared.cambiarPerfil(p) }
            }
            if !Funcion.teclas.activa { Funcion.teclas.poner(true) }
        }
        if let minutos = e.foco, let foco, foco.activo == nil { foco.empezar("", minutos: minutos) }
        if let atajo = e.atajo { correr(atajo) }
    }

    /// Una frase de lo que hace el espacio (para la ayuda del chip).
    static func resumen(_ e: EspacioIsla) -> String {
        var partes: [String] = []
        switch e.velo {
        case .sinCambio: break
        case .apagado: partes.append("velo apagado")
        case .encendido(let m): partes.append("velo " + (m ?? "encendido"))
        }
        switch e.teclas {
        case .sinCambio: break
        case .apagado: partes.append("teclas apagadas")
        case .encendido(let p): partes.append("teclas " + (p ?? "encendidas"))
        }
        if let f = e.foco { partes.append("foco de \(f) min") }
        if let a = e.atajo { partes.append("atajo «\(a)»") }
        if e.rutaFondoDePantalla() != nil { partes.insert("fondo de pantalla", at: 0) }
        if !e.abrir.isEmpty { partes.append("abre " + e.abrir.joined(separator: ", ")) }
        if e.reproducir != nil { partes.append("reproduce") }
        let cambios = partes.isEmpty ? "Solo cambia el orden de Inicio" : partes.joined(separator: " · ")
        return e.titulo.map { $0 + ". " + cambios } ?? cambios
    }

    // MARK: Atajos

    /// Corre un atajo de Apple. Solo se llama desde un clic (en un mosaico o al elegir un espacio que lo nombra).
    func correr(_ nombre: String) {
        guard vivo, estados[nombre] != .corriendo else { return }
        estados[nombre] = .corriendo
        Task.detached(priority: .userInitiated) {
            let r = ProcesoAtajos.ejecutar(["run", nombre], limite: AtajosSistema.segundosLimite)
            await MainActor.run { [weak self] in self?.terminar(nombre, r) }
        }
    }

    private func terminar(_ nombre: String, _ r: ProcesoAtajos.Resultado) {
        let limpiar: Double
        if r.codigo == 0 && !r.agotado {
            estados[nombre] = .listo
            limpiar = Self.segundosListo
        } else {
            let texto = r.agotado ? "Tardó más de \(Int(AtajosSistema.segundosLimite)) s y se cortó" : AtajosSistema.primeraLinea(r.error)
            estados[nombre] = .fallo(texto)
            limpiar = Self.segundosFallo
        }
        let esperado = estados[nombre]
        Task { [weak self] in   // un solo despertar: quita la marca de "listo" o "falló"
            try? await Task.sleep(for: .seconds(limpiar))
            if self?.estados[nombre] == esperado { self?.estados[nombre] = nil }
        }
    }
}

/// `/usr/bin/shortcuts` con tope de tiempo: sin hilo principal, leyendo las dos salidas a la vez para que no se trabe.
enum ProcesoAtajos {
    struct Resultado: Sendable { var codigo: Int32; var salida: String; var error: String; var agotado: Bool }

    private final class Caja: @unchecked Sendable { var datos = Data() }

    nonisolated static func ejecutar(_ argumentos: [String], limite: Double) -> Resultado {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = argumentos
        let tuboSalida = Pipe(), tuboError = Pipe()
        p.standardOutput = tuboSalida
        p.standardError = tuboError
        p.standardInput = FileHandle.nullDevice
        let fin = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in fin.signal() }
        do { try p.run() } catch { return Resultado(codigo: -1, salida: "", error: "No se pudo abrir Atajos", agotado: false) }
        let salida = Caja(), error = Caja(), lectura = DispatchGroup()
        for (tubo, caja) in [(tuboSalida, salida), (tuboError, error)] {
            lectura.enter()
            DispatchQueue.global(qos: .utility).async {
                caja.datos = tubo.fileHandleForReading.readDataToEndOfFile()
                lectura.leave()
            }
        }
        var agotado = false
        if fin.wait(timeout: .now() + limite) == .timedOut {
            agotado = true
            p.terminate()
            _ = fin.wait(timeout: .now() + 2)
        }
        _ = lectura.wait(timeout: .now() + 2)
        return Resultado(codigo: p.isRunning ? -1 : p.terminationStatus, salida: String(decoding: salida.datos, as: UTF8.self),
                         error: String(decoding: error.datos, as: UTF8.self), agotado: agotado)
    }
}

// MARK: - Vista

/// El lanzador de Inicio. Alto flexible: lo fijo son los espacios y el control de arriba; la rejilla toma el resto, así que no
/// puede empujar ni desbordar la fila de 178.
struct LanzadorAurora: View {
    let lanzador: LanzadorIsla
    let apps: AppsUsadas
    var foco: Foco?
    /// El ancho que le da la fila de Inicio: de él depende cuántas columnas caben.
    var ancho: CGFloat = AuroraNotch.anchoApps

    private let altoControl: CGFloat = 22
    /// Los iconos de los mosaicos llevan aire por dentro: con 34 pt y la etiqueta ocupaban casi todo el alto de la celda y
    /// tocaban el borde curvo. 30 pt de icono (carpeta: 2 × 17 + 4 = 38) y 4 pt de aire arriba y abajo.
    static let ladoIcono: CGFloat = 30
    static let ladoMini: CGFloat = 17
    static let aireVertical: CGFloat = 4
    private var columnas: Int { LanzadorIsla.columnas(ancho: ancho) }

    var body: some View {
        let todos = lanzador.mosaicos(apps)
        let porPagina = columnas * AuroraNotch.filasLanzador
        let total = PaginasInicio.cantidad(total: todos.count, porPagina: porPagina)
        let rango = PaginasInicio.rango(pagina: lanzador.pagina, total: todos.count, porPagina: porPagina)
        let visibles = Array(todos[rango])
        VStack(spacing: AuroraNotch.separacionApps) {
            if !lanzador.espacios.isEmpty { espacios }
            control(paginas: total, actual: min(lanzador.pagina, total - 1))
                .frame(height: altoControl)
            rejilla(visibles)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: visibles.flatMap { $0.apps.map(\.id) }) { apps.pedirIconos(de: visibles.flatMap(\.apps)) }
    }

    // MARK: Espacios

    private var espacios: some View {
        HStack(spacing: 4) {
            ForEach(Array(lanzador.espacios.prefix(5)), id: \.nombre) { e in chip(e) }
        }
        .frame(height: AuroraNotch.altoChip)
    }

    private func chip(_ e: EspacioIsla) -> some View {
        let activo = lanzador.espacioActual == e.nombre
        let resumen = LanzadorIsla.resumen(e)
        let ayuda = "\(e.nombre): \(resumen)" + (activo ? ". Toca otra vez para quitar el espacio." : "")
        let texto: Color = activo ? .black : AuroraNotch.suave
        let fondo: Color = activo ? .white : AuroraNotch.pildora
        return Button { lanzador.elegirEspacio(e, foco: foco) } label: {
            Text(e.nombre).font(AuroraNotch.chipFuente).lineLimit(1).minimumScaleFactor(0.8).help(e.nombre)
                .foregroundStyle(texto)
                .frame(maxWidth: .infinity)
                .frame(height: AuroraNotch.altoChip)
                .background { Capsule().fill(fondo) }
                .indicadorEspacio(activo: activo, acento: e.acento)
                .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel("Espacio \(e.nombre)" + (activo ? ", activo" : ""))
        .accessibilityHint(resumen)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }

    // MARK: Control (sección, carpeta, páginas)

    private func control(paginas: Int, actual: Int) -> some View {
        HStack(spacing: 4) {
            if let nombre = lanzador.carpetaAbierta {
                Button { lanzador.cerrarCarpeta() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 8.5, weight: .bold))
                        Text(nombre).font(AuroraNotch.chipFuente).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: AuroraNotch.altoChip)
                    .background { Capsule().fill(AuroraNotch.botonVidrio) }
                    .contentShape(Capsule())
                }
                .buttonStyle(PulsadoAurora())
                .help("Volver a Inicio")
                .accessibilityLabel("Volver desde la carpeta \(nombre)")
            } else {
                SegmentadoAurora(opciones: ["Apps", "Atajos"], elegida: lanzador.seccion.rawValue) { lanzador.elegir(LanzadorIsla.Seccion(rawValue: $0) ?? .apps) }
            }
            Spacer(minLength: 0)
            if paginas > 1 {
                // Un solo control chico a la derecha, lejos del segmentado.
                HStack(spacing: 2) {
                    paso("chevron.left", "Página anterior", habilitado: actual > 0) { lanzador.pagina = actual - 1 }
                    Text("\(actual + 1)/\(paginas)").font(AuroraNotch.rotuloMosaico).monospacedDigit().foregroundStyle(AuroraNotch.suave)
                        .frame(minWidth: 24)
                    paso("chevron.right", "Página siguiente", habilitado: actual < paginas - 1) { lanzador.pagina = actual + 1 }
                }
                .background { Capsule().fill(AuroraNotch.pildora) }
            }
        }
    }

    private func paso(_ simbolo: String, _ ayuda: String, habilitado: Bool, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(habilitado ? Color.white : AuroraNotch.suave.opacity(0.4))
                .frame(width: AuroraNotch.altoChip, height: AuroraNotch.altoChip)
                .contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora())
        .disabled(!habilitado)
        .help(ayuda)
        .accessibilityLabel(ayuda)
    }

    // MARK: Rejilla

    private func rejilla(_ visibles: [MosaicoInicio]) -> some View {
        let sep = AuroraNotch.separacionApps
        return VStack(spacing: sep) {
            ForEach(0..<AuroraNotch.filasLanzador, id: \.self) { fila in
                HStack(spacing: sep) {
                    ForEach(0..<columnas, id: \.self) { col in
                        let i = fila * columnas + col
                        celda(i < visibles.count ? visibles[i] : nil)
                    }
                }
            }
        }
        .overlay { if visibles.isEmpty { vacio } }
    }

    @ViewBuilder private var vacio: some View {
        let texto: String = {
            switch lanzador.seccion {
            case .atajos: return lanzador.cargandoAtajos && lanzador.todosLosAtajos.isEmpty ? "Buscando tus atajos…" : "Sin atajos: crea uno en la app Atajos"
            case .apps: return "Buscando tus apps…"
            }
        }()
        Text(texto).font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.suave).multilineTextAlignment(.center).padding(.horizontal, 12)
    }

    @ViewBuilder private func celda(_ m: MosaicoInicio?) -> some View {
        let forma = RoundedRectangle(cornerRadius: AuroraNotch.radioIcono, style: .continuous)
        Group {
            switch m {
            case .app(let a): mosaicoApp(a, forma)
            case .carpeta(let c, let r): mosaicoCarpeta(c, r, forma)
            case .atajo(let n): mosaicoAtajo(n, forma)
            case nil: Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { forma.fill(m == nil ? AuroraNotch.superficie.opacity(0.45) : AuroraNotch.superficie) }
        .overlay { forma.strokeBorder(AuroraNotch.filo, lineWidth: 1) }
    }

    private func icono(_ a: EntradaApp, lado: CGFloat) -> some View {
        Group {
            if let img = apps.iconos[a.id] { Image(nsImage: img).resizable().scaledToFit() } else { Color.clear }
        }
        .frame(width: lado, height: lado)
    }

    private func mosaicoApp(_ a: EntradaApp, _ forma: RoundedRectangle) -> some View {
        Button { apps.abrir(a) } label: {
            VStack(spacing: 4) {
                icono(a, lado: Self.ladoIcono)
                Text(a.nombre).font(AuroraNotch.etiquetaApp).foregroundStyle(AuroraNotch.resumen).lineLimit(1).minimumScaleFactor(0.8).help(a.nombre)
            }
            .padding(.horizontal, 6).padding(.vertical, Self.aireVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(forma)
        }
        .buttonStyle(PulsadoAurora())
        .help("Abrir " + a.nombre)
        .accessibilityLabel("Abrir " + a.nombre)
    }

    private func mosaicoCarpeta(_ c: CarpetaApps, _ r: [EntradaApp], _ forma: RoundedRectangle) -> some View {
        let mini = Array(r.prefix(4))
        let sep = AuroraNotch.separacionMini
        return Button { lanzador.abrir(carpeta: c.nombre) } label: {
            VStack(spacing: 4) {
                VStack(spacing: sep) {
                    ForEach(0..<2, id: \.self) { fila in
                        HStack(spacing: sep) {
                            ForEach(0..<2, id: \.self) { col in
                                let i = fila * 2 + col
                                if i < mini.count { icono(mini[i], lado: Self.ladoMini) } else { Color.clear.frame(width: Self.ladoMini, height: Self.ladoMini) }
                            }
                        }
                    }
                }
                Text(c.nombre).font(AuroraNotch.etiquetaApp).foregroundStyle(AuroraNotch.resumen).lineLimit(1).minimumScaleFactor(0.8).help(c.nombre)
            }
            .padding(.horizontal, 6).padding(.vertical, Self.aireVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(forma)
        }
        .buttonStyle(PulsadoAurora())
        .help("Abrir la carpeta \(c.nombre) (\(r.count) apps)")
        .accessibilityLabel("Carpeta \(c.nombre), \(r.count) apps")
    }

    private func mosaicoAtajo(_ nombre: String, _ forma: RoundedRectangle) -> some View {
        let estado = lanzador.estados[nombre]
        var simbolo = "bolt.fill"
        var color = Color.white
        var ayuda = "Correr el atajo «\(nombre)»"
        switch estado {
        case .corriendo: (simbolo, color, ayuda) = ("hourglass", AuroraAcento.foco, "Corriendo…")
        case .listo: (simbolo, color, ayuda) = ("checkmark.circle.fill", AuroraAcento.bien, "Listo")
        case .fallo(let t): (simbolo, color, ayuda) = ("exclamationmark.triangle.fill", AuroraAcento.hoy, t)
        case nil: break
        }
        return Button { lanzador.correr(nombre) } label: {
            VStack(spacing: 4) {
                Image(systemName: simbolo).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                Text(nombre).font(AuroraNotch.rotuloMosaico).foregroundStyle(AuroraNotch.resumen).lineLimit(2)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(forma)
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel("Atajo \(nombre)" + (estado == nil ? "" : ": " + ayuda))
    }
}

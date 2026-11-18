import AppKit
import DictadoKit
import EventKit
import Observation
import SwiftUI

// Los espacios cambian todo: el fondo de pantalla, el Dock (piezas y paleta), el orden del lanzador y de Inicio, los ajustes (velo,
// teclas, foco) y lo que se abre o suena al entrar. Es un solo concepto (`espacios.txt`) para el Dock, el lanzador y la isla. Aquí
// vive lo que no es de una vista: las acciones al entrar, el fondo de pantalla (se recuerda el anterior), el teclado (Hyper + número,
// Hyper + [ y ]) y el plan de Mañana. Todo corre solo cuando el dueño elige el espacio; nada en bucle ni en reposo.

extension Notification.Name {
    /// Se eligió otro espacio (o se quitó el activo): el Dock vuelve a leer su paleta y sus piezas.
    static let espacioCambio = Notification.Name("app.dictado.espacioCambio")
}

extension EspacioIsla {
    /// Su paleta Aurora (la línea `paleta:`), si la tiene.
    var paletaAurora: AuroraPaleta? { paleta.flatMap(AuroraPaleta.init(rawValue:)) }
    /// El tono de acento del espacio activo (el del indicador): el claro de su paleta.
    var acento: Color? { paletaAurora?.tonoB }
}

// MARK: - Fondo de pantalla

/// Pone y devuelve el fondo de pantalla del Mac. Antes del primer cambio guarda el fondo de cada pantalla (en el ajuste
/// `espacios.fondoPrevio`) y lo devuelve al quitar el espacio activo o al elegir uno sin fondo propio.
@MainActor
enum FondoDePantalla {
    static let clave = "espacios.fondoPrevio"

    private static func id(_ p: NSScreen) -> String {
        (p.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { "\($0)" } ?? p.localizedName
    }

    /// Pone esta imagen en todas las pantallas (con las opciones de escala que ya tenían). Devuelve si lo hizo.
    @discardableResult
    static func poner(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var previos = UserDefaults.dictado.dictionary(forKey: clave) as? [String: String] ?? [:]
        let ws = NSWorkspace.shared
        var hecho = false
        for p in NSScreen.screens {
            let actual = ws.desktopImageURL(for: p)
            if actual?.path == url.path { continue }
            var esCarpeta: ObjCBool = false
            if previos[id(p)] == nil, let actual, FileManager.default.fileExists(atPath: actual.path, isDirectory: &esCarpeta), !esCarpeta.boolValue {
                previos[id(p)] = actual.path
            }
            do {
                try ws.setDesktopImageURL(url, for: p, options: ws.desktopImageOptions(for: p) ?? [:])
                hecho = true
            } catch {
                continue
            }
        }
        UserDefaults.dictado.set(previos, forKey: clave)
        return hecho
    }

    /// Devuelve el fondo que había antes del primer espacio con fondo propio (si hay algo guardado).
    static func devolver() {
        guard let previos = UserDefaults.dictado.dictionary(forKey: clave) as? [String: String], !previos.isEmpty else { return }
        let ws = NSWorkspace.shared
        for p in NSScreen.screens {
            guard let ruta = previos[id(p)], FileManager.default.fileExists(atPath: ruta) else { continue }
            try? ws.setDesktopImageURL(URL(fileURLWithPath: ruta), for: p, options: ws.desktopImageOptions(for: p) ?? [:])
        }
        UserDefaults.dictado.removeObject(forKey: clave)
    }
}

// MARK: - Al entrar

/// Lo que pasa cuando el dueño elige un espacio: el fondo, abrir apps y reproducir. El velo, las teclas, el foco y el atajo de Apple
/// siguen en `LanzadorIsla.aplicar`. Solo se llama desde un clic o una tecla.
@MainActor
enum EspaciosAcciones {
    /// `nil`: se quitó el espacio activo.
    static func cambio(a e: EspacioIsla?, plan: PlanManana? = nil) {
        guard let e else {
            FondoDePantalla.devolver()
            NotificationCenter.default.post(name: .espacioCambio, object: nil)
            return
        }
        ponerFondo(de: e)
        NotificationCenter.default.post(name: .espacioCambio, object: nil)
        let acciones = e.accionesAlEntrar
        if !acciones.isEmpty { Task { await correr(acciones) } }
        if e.piezasDockUsaPlan { (plan ?? .compartido).pedirPermisoYRefrescar() }
    }

    /// El fondo de pantalla del espacio: una imagen, un fondo de macOS por nombre o el cuadro fijo de un aéreo (si todavía no se sacó,
    /// se saca en otro hilo y se pone al terminar, si el dueño no cambió de espacio mientras tanto). Sin fondo propio, o con uno que no
    /// está en el Mac, devuelve el que había. `mac` y `paleta:` no tocan el escritorio.
    private static var generacion = 0
    private static func ponerFondo(de e: EspacioIsla) {
        generacion += 1
        let mia = generacion
        guard let fondo = e.fondo.flatMap({ FondoLanzador(texto: $0) }) else { return FondoDePantalla.devolver() }
        switch fondo {
        case .mac, .paleta: FondoDePantalla.devolver()
        case .imagen, .sistema:
            if let url = FondosMac.archivoEscritorio(fondo) { FondoDePantalla.poner(url) } else { FondoDePantalla.devolver() }
        case .aereo(let nombre):
            // Apagado y sin efecto (ver `AereoEnEscritorio`): el escritorio siempre lleva el cuadro fijo.
            if AereoEnEscritorio.activado, let r = FondosMac.resolverAereo(nombre), AereoEnEscritorio.poner(r.aereo) { return }
            if let url = FondosMac.archivoEscritorio(fondo) {
                FondoDePantalla.poner(url)
            } else {
                FondoDePantalla.devolver()
                Task {
                    guard let url = await FondosMac.prepararEscritorio(fondo), mia == generacion else { return }
                    FondoDePantalla.poner(url)
                }
            }
        }
    }

    /// Abre las apps (sin quitarte el foco) y, si toca, le manda "reproducir". Si la app no estaba abierta, espera un poco a que arranque.
    private static func correr(_ acciones: [AccionEntrada]) async {
        var abrioAlgo = false
        for a in acciones {
            // `abrir: dictado://centro/abrir` (u otro enlace de Dictado): se atiende aquí mismo, sin buscar una app.
            if case .abrir(let nombre) = a, nombre.lowercased().hasPrefix("dictado:"), let enlace = URL(string: nombre) {
                NSWorkspace.shared.open(enlace)
                continue
            }
            guard case .abrir(let nombre) = a, let url = urlApp(nombre) else { continue }
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == url }) { continue }
            let c = NSWorkspace.OpenConfiguration()
            c.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: c)
            abrioAlgo = true
        }
        for a in acciones {
            guard case .reproducir(let nombre) = a, let script = ReproducirApp.script(nombre) else { continue }
            if abrioAlgo { try? await Task.sleep(for: .seconds(3)) }
            await Task.detached(priority: .userInitiated) { Self.ejecutar(script) }.value
        }
    }

    /// Una app por nombre o por identificador, en las carpetas de apps de siempre.
    static func urlApp(_ nombre: String) -> URL? {
        if nombre.contains("."), let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: nombre) { return u }
        let carpetas = ["/Applications", "/System/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for c in carpetas {
            let u = URL(fileURLWithPath: c).appendingPathComponent(nombre + ".app")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// `osascript` con tope de 10 s. macOS pide el permiso de Automatización la primera vez; no se hace nada para saltárselo.
    nonisolated private static func ejecutar(_ script: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        let limite = Date().addingTimeInterval(10)
        while p.isRunning, Date() < limite { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning { p.terminate() }
    }
}

extension EspacioIsla {
    /// ¿Su Dock lleva la pieza del plan? (Entonces, al entrar, se pide la lista fresca.)
    var piezasDockUsaPlan: Bool { piezasDock(masUsadas: []).contains(.plan) }
}

// MARK: - Teclado

@MainActor
enum EspaciosTeclado {
    /// Hyper + número, Hyper + ] y Hyper + [. Elegir el espacio que ya está activo no lo quita (el clic sí; el teclado nunca deja sin espacio).
    static func ir(_ destino: DestinoEspacio, isla: Isla?, avisar: (String, String, String?) -> Void) {
        guard let isla else { return }
        let l = isla.lanzador
        if l.espacios.isEmpty {   // el archivo es chico: se lee aquí si todavía nadie abrió la isla ni el Dock
            LanzadorIsla.asegurarEspacios()
            l.espacios = EspaciosIsla.leer((try? String(contentsOf: LanzadorIsla.archivoEspacios, encoding: .utf8)) ?? "")
        }
        guard let i = EspaciosIsla.resolver(destino, nombres: l.espacios.map(\.nombre), actual: l.espacioActual) else {
            if case .numero(let n) = destino { avisar("No hay un espacio \(n)", "square.grid.2x2", nil) }
            return
        }
        let e = l.espacios[i]
        if l.espacioActual != e.nombre { l.elegirEspacio(e, foco: isla.foco) }
        avisar(e.nombre, "square.grid.2x2", e.titulo)
    }

    /// dictado://espacio/<nombre>: lo mismo, buscando el espacio por su nombre (sin importar mayúsculas ni tildes).
    static func irPorNombre(_ nombre: String, isla: Isla?, avisar: (String, String, String?) -> Void) {
        guard let isla else { return }
        let l = isla.lanzador
        if l.espacios.isEmpty {
            LanzadorIsla.asegurarEspacios()
            l.espacios = EspaciosIsla.leer((try? String(contentsOf: LanzadorIsla.archivoEspacios, encoding: .utf8)) ?? "")
        }
        guard let i = EnlaceDictado.indiceDeEspacio(nombre, en: l.espacios.map(\.nombre)) else {
            return avisar("No hay un espacio «\(nombre)»", "square.grid.2x2", nil)
        }
        ir(.numero(i + 1), isla: isla, avisar: avisar)
    }
}

// MARK: - Indicador del espacio activo

extension View {
    /// Un aro del color del espacio alrededor de su chip cuando está activo.
    func indicadorEspacio(activo: Bool, acento: Color?) -> some View {
        overlay { if activo, let acento { Capsule().strokeBorder(acento, lineWidth: 1.5) } }
    }
}

extension EstadoLanzador {
    /// La paleta que vale en el lanzador: la del fondo si es una paleta; si no, la del espacio activo; si no, la elegida.
    var paletaVigente: AuroraPaleta {
        if case .paleta(let n) = fondo, let p = AuroraPaleta(rawValue: n) { return p }
        return datos?.lanzador.espacio?.paletaAurora ?? paleta
    }
}

// MARK: - El plan de Mañana

/// Lo de hoy y lo de la semana, de tres fuentes de solo lectura: las tareas de la isla (el centro o las notas de reunión),
/// Recordatorios (EventKit) y las metas del cerebro (`metas/`). Se lee al entrar a Mañana y al mostrarse la pieza, con tope de un
/// minuto; nunca en bucle.
@MainActor @Observable
final class PlanManana {
    static let compartido = PlanManana()

    private(set) var plan = PlanPendientes.vacio
    /// Los recordatorios que se acaban de marcar desde la tarjeta (`FilaPlan.id`): se tachan hasta que la lista se vuelve a leer.
    private(set) var hechas: Set<String> = []
    @ObservationIgnored private var ultima = Date.distantPast
    @ObservationIgnored private var leyendo = false
    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private weak var tareas: TareasIsla?
    nonisolated static let vigencia: TimeInterval = 60

    init(vivo: Bool = true) { self.vivo = vivo }

    /// Para los renders.
    func fijar(_ plan: PlanPendientes) { self.plan = plan }

    /// Marca un recordatorio como hecho en Recordatorios (EventKit). Solo los que tienen identificador; si falla, no cambia nada.
    func marcarHecho(_ fila: FilaPlan) {
        guard vivo, fila.puedeMarcar, let id = fila.idFuente, !hechas.contains(fila.id) else { return }
        hechas.insert(fila.id)
        Task { [weak self] in
            let hecho = await Self.completar(id)
            guard let self else { return }
            if hecho { self.refrescar(forzar: true) } else { self.hechas.remove(fila.id) }
        }
    }

    nonisolated private static func completar(_ id: String) async -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return false }
        let almacen = EKEventStore()
        guard let r = almacen.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        r.isCompleted = true
        return (try? almacen.save(r, commit: true)) != nil
    }

    /// Para los renders: una fila ya marcada.
    func simularHecha(_ id: String) { hechas.insert(id) }

    func recordar(tareas: TareasIsla?) { if let tareas { self.tareas = tareas } }

    /// Al entrar a Mañana: si Recordatorios nunca se ha pedido, macOS pregunta una vez; luego lee.
    func pedirPermisoYRefrescar() {
        guard vivo else { return }
        Task { [weak self] in
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined { _ = try? await EKEventStore().requestFullAccessToReminders() }
            self?.refrescar(forzar: true)
        }
    }

    func refrescar(tareas t: TareasIsla? = nil, forzar: Bool = false) {
        guard vivo, !leyendo else { return }
        if let t { tareas = t }
        guard forzar || Date().timeIntervalSince(ultima) > Self.vigencia else { return }
        leyendo = true
        ultima = Date()
        tareas?.refrescar()
        let deTareas = itemsDeTareas()
        let carpeta = Ajustes().carpetaInbox.deletingLastPathComponent().appendingPathComponent("metas")
        Task.detached(priority: .utility) {
            var items = deTareas
            items += Self.metas(en: carpeta)
            items += await Self.recordatorios()
            let ahora = Date()
            let nuevo = PlanPendientesCalculo.armar(items, ahora: ahora)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.leyendo = false
                if nuevo != self.plan { self.plan = nuevo }
                // Las marcadas que ya no están en la lista leída dejan de recordarse.
                let vivas = Set((nuevo.hoy + nuevo.semana).map { TarjetaPlan.clave($0) })
                let quedan = self.hechas.intersection(vivas)
                if quedan != self.hechas { self.hechas = quedan }
            }
        }
    }

    private func itemsDeTareas() -> [ItemPlan] {
        guard let t = tareas else { return [] }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return t.lista.map { v in ItemPlan(texto: v.texto, vence: t.vencimientos[v.id].flatMap { f.date(from: $0) }, origen: .tarea, delDia: true) }
    }

    /// Las metas abiertas de la semana y los hitos con fecha del trimestre más reciente. Solo lectura.
    nonisolated private static func metas(en carpeta: URL) -> [ItemPlan] {
        let archivos = ((try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let ultimo = archivos.last, let texto = try? String(contentsOf: ultimo, encoding: .utf8) else { return [] }
        return MetasPlan.items(texto)
    }

    /// Los recordatorios sin completar que vencen de hoy al domingo (y los vencidos). Sin permiso, nada.
    nonisolated private static func recordatorios() async -> [ItemPlan] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let almacen = EKEventStore()
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let fin = cal.dateInterval(of: .weekOfYear, for: Date())?.end else { return [] }
        let predicado = almacen.predicateForIncompleteReminders(withDueDateStarting: nil, ending: fin, calendars: nil)
        let lista: [EKReminder] = await withCheckedContinuation { c in almacen.fetchReminders(matching: predicado) { c.resume(returning: $0 ?? []) } }
        return lista.compactMap { r in
            guard let t = r.title, !t.isEmpty else { return nil }
            return ItemPlan(texto: t, vence: r.dueDateComponents.flatMap { cal.date(from: $0) }, origen: .recordatorio, delDia: true, id: r.calendarItemIdentifier)
        }
    }
}

/// La pieza del Dock con el plan de Mañana: cuántas cosas hay hoy y cuántas en la semana, y la más próxima. Un toque abre las tareas; el
/// botón "Agentes" abre la lista de agentes y sesiones para dejarlos trabajando (no lanza nada por su cuenta).
struct PlanPieza: View {
    let estado: EstadoDock
    let ancho: CGFloat

    var body: some View {
        let plan = estado.plan.plan
        let siguiente = (plan.hoy.first ?? plan.semana.first)?.texto
        let resumen = "Plan: \(plan.hoy.count) para hoy, \(plan.semana.count) en la semana"
        PiezaDockMarco(ancho: ancho, tono: TonosPieza.agenda, etiqueta: resumen, accion: { estado.acciones.abrirPestana(.tareas) }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    RotuloPieza("Plan del día", color: TonosPieza.agenda.rotulo)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(plan.hoy.count)").font(AuroraDock.cifraMedia).monospacedDigit()
                        Text("hoy").font(AuroraDock.cifraPequena).foregroundStyle(AuroraDock.textoTenue)
                        Text("\(plan.semana.count)").font(AuroraDock.cifraMedia).monospacedDigit().padding(.leading, 4)
                        Text("semana").font(AuroraDock.cifraPequena).foregroundStyle(AuroraDock.textoTenue)
                    }
                    Text(siguiente ?? "Nada pendiente").font(AuroraDock.cifraPequena).foregroundStyle(AuroraDock.textoTenue).lineLimit(1)
                }
                Button { estado.acciones.abrirPestana(.agentes) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                        Text("Agentes").font(AuroraDock.cifraPequena)
                    }
                    .foregroundStyle(TonosPieza.agentes.rotulo)
                    .frame(width: 52, height: 46)
                    .background { RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.10)) }
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(PulsadoAurora())
                .help("Dejar trabajando a los agentes: abre su lista y tus sesiones")
                .accessibilityLabel("Dejar trabajando a los agentes")
            }
            .padding(.horizontal, 12)
        }
        .help(plan.total == 0 ? "Nada pendiente hoy ni esta semana" : ([("Hoy", plan.hoy), ("Semana", plan.semana)].filter { !$0.1.isEmpty }
            .map { "\($0.0): " + $0.1.prefix(4).map(\.texto).joined(separator: "; ") }.joined(separator: "\n")))
        .onAppear { if estado.hayTablero { estado.plan.refrescar(tareas: estado.tareas) } }
    }
}

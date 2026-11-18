import AppKit
import DictadoKit
import Observation
import SwiftUI

// Pestaña Tareas: una tarjeta por tarea abierta (de qué viene y cuándo vence, la tarea, la frase que la respalda) con Hecha,
// Agendar y descartar; y el resumen del día. La lista única la tiene el centro (`python3 -m centro tarea …`); si no está
// configurado o falla, se muestran los pendientes de tus notas de reunión (`Pendientes`).

/// Una tarea tal como la dibuja la tarjeta, venga del centro o de las notas de reunión.
struct TareaVista: Identifiable, Equatable {
    enum Origen: Equatable {
        case centro(Int)
        case pendiente(Pendientes.Item)
    }

    let id: String
    let rotulo: String
    let texto: String
    let cita: String?
    let origen: Origen
}

@MainActor @Observable
final class TareasIsla {
    private(set) var lista: [TareaVista] = []
    private(set) var hechasHoy = 0
    private(set) var total = 0
    /// De dónde salió lo que se ve: la lista del centro o, si no estaba configurada o falló, las notas de reunión.
    private(set) var delCentro = false
    private(set) var cargando = false
    /// Cuándo vence cada tarea del centro (AAAA-MM-DD, por el id de su tarjeta); las que no tienen fecha no aparecen. La Semana del Centro las ubica por día.
    private(set) var vencimientos: [String: String] = [:]

    @ObservationIgnored private let pendientes: Pendientes?
    @ObservationIgnored private let vivo: Bool

    var abiertas: Int { lista.count }

    init(pendientes: Pendientes?, vivo: Bool = true) {
        self.pendientes = pendientes
        self.vivo = vivo
    }

    // MARK: Configuración del centro

    /// La carpeta desde donde se corre `python3 -m centro`: el ajuste `centro → carpeta` o, por omisión, la que contiene el
    /// script de acciones (`…/centro/mac/accion.sh` → `…/centro`). nil si no está configurada o no tiene el paquete.
    nonisolated static var carpetaCentro: URL? {
        let ajuste = UserDefaults.dictado.dictionary(forKey: "centro")?["carpeta"] as? String
        var ruta = (ajuste?.isEmpty ?? true) ? nil : (ajuste! as NSString).expandingTildeInPath
        if ruta == nil, let acciones = UserDefaults.dictado.dictionary(forKey: "centro")?["acciones"] as? String, !acciones.isEmpty {
            ruta = URL(fileURLWithPath: (acciones as NSString).expandingTildeInPath).deletingLastPathComponent().deletingLastPathComponent().path
        }
        guard let ruta, FileManager.default.fileExists(atPath: ruta + "/centro/__main__.py") else { return nil }
        return URL(fileURLWithPath: ruta)
    }

    nonisolated private static func correr(_ argumentos: [String], en carpeta: URL) -> (datos: Data, error: String?) {
        CentroStore.correr(URL(fileURLWithPath: "/usr/bin/python3"), ["-m", "centro", "tarea"] + argumentos, limite: 8, carpeta: carpeta)
    }

    // MARK: Leer

    /// Pide la lista fresca (fuera del hilo principal, con un límite de 8 s). Se llama al abrir la isla o la pestaña y tras
    /// cada cambio; no hay consultas periódicas.
    func refrescar() {
        guard vivo, !cargando else { return }
        guard let carpeta = Self.carpetaCentro else {
            usarNotas()
            return
        }
        cargando = true
        Task.detached(priority: .userInitiated) {
            let r = Self.correr(["listar", "--estado", "todas", "--json"], en: carpeta)
            let tareas = r.error == nil ? TareasCentro.decodificar(r.datos) : nil
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cargando = false
                if let tareas { self.aplicar(tareas) } else { self.usarNotas() }
            }
        }
    }

    private func aplicar(_ tareas: [TareaCentro]) {
        let ahora = Date()
        delCentro = true
        vencimientos = Dictionary(tareas.filter(\.abierta).compactMap { t in t.vence.map { ("c\(t.id)", $0) } }, uniquingKeysWith: { a, _ in a })
        lista = TareasCentro.ordenar(tareas).map {
            TareaVista(id: "c\($0.id)", rotulo: TareasCentro.rotulo($0, ahora: ahora), texto: $0.texto, cita: $0.cita, origen: .centro($0.id))
        }
        let r = TareasCentro.resumenDelDia(tareas, ahora: ahora)
        hechasHoy = r.hechas
        total = r.total
    }

    private func usarNotas() {
        delCentro = false
        vencimientos = [:]
        guard let pendientes else {
            lista = []
            hechasHoy = 0
            total = 0
            return
        }
        pendientes.refrescar()
        lista = pendientes.items.map { i in
            TareaVista(id: "p" + i.id, rotulo: [i.reunion, i.cuando].compactMap { $0 }.joined(separator: " · "), texto: i.texto,
                       cita: i.gatillo.map { "Si: " + $0 }, origen: .pendiente(i))
        }
        hechasHoy = pendientes.hechasHoy
        total = hechasHoy + lista.count
    }

    /// Para los renders: lo que se muestra, sin leer nada.
    func fijar(_ lista: [TareaVista], hechas: Int, delCentro: Bool, vencimientos: [String: String] = [:]) {
        self.lista = lista
        self.vencimientos = vencimientos
        hechasHoy = hechas
        total = hechas + lista.count
        self.delCentro = delCentro
    }

    // MARK: Cambiar

    func hecha(_ t: TareaVista) { cerrar(t, "hecha") }
    func descartar(_ t: TareaVista) { cerrar(t, "descartar") }

    private func cerrar(_ t: TareaVista, _ orden: String) {
        lista.removeAll { $0.id == t.id }   // sale al instante; si el centro no lo logra, la lectura siguiente la devuelve
        switch t.origen {
        case .pendiente(let item):
            if orden == "hecha" { pendientes?.hecho(item) } else { pendientes?.soltar(item) }
            usarNotas()
        case .centro(let id):
            guard let carpeta = Self.carpetaCentro else { return }
            if orden == "hecha" { hechasHoy += 1 }
            Task.detached(priority: .userInitiated) {
                _ = Self.correr([orden, String(id), "--json"], en: carpeta)
                await MainActor.run { [weak self] in
                    self?.cargando = false
                    self?.refrescar()
                }
            }
        }
    }
}

extension AbrirCalendario {
    /// "Agendar" una tarea: la página de "nuevo evento" de Google Calendar con la franja y la tarea como título. No crea nada.
    static func nuevo(en inicio: Date, titulo: String) {
        if let url = EnlacesCalendario.nuevoEvento(inicio: inicio, titulo: titulo) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - La pestaña

struct TareasAurora: View {
    var tareas: TareasIsla?
    let ahora: Date
    let agenda: Agenda
    let simulado: Bool

    /// Un tono por tarjeta (la barra de la cita y el rótulo): coral, azul y lima, como en el diseño.
    private static let tonos: [(barra: Color, rotulo: Color)] = [
        (Color(hex: 0xFF6A4A), Color(hex: 0xFFB39C)), (Color(hex: 0x6F97FF), Color(hex: 0xB9CCFF)), (Color(hex: 0xC9E04A), Color(hex: 0xE4F08F)),
    ]

    var body: some View {
        let lista = tareas?.lista ?? []
        HStack(spacing: AuroraNotch.separacion) {
            if lista.isEmpty {
                TarjetaOscura {
                    VStack(alignment: .leading, spacing: 4) {
                        RotuloPieza("Tareas")
                        Text(tareas?.cargando == true ? "Buscando tus tareas…" : "Nada abierto por ahora").font(AuroraNotch.titulo)
                        Text("Aquí va lo que te toca a ti: lo que quedó de tus reuniones y lo que dictas.")
                            .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.suave)
                    }
                }
            } else {
                GeometryReader { g in
                    if simulado {
                        fila(lista, g.size.width).clipped()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) { fila(lista, g.size.width) }
                    }
                }
            }
            resumen
        }
    }

    private func fila(_ lista: [TareaVista], _ ancho: CGFloat) -> some View {
        HStack(spacing: AuroraNotch.separacion) {
            ForEach(Array(lista.enumerated()), id: \.element.id) { i, t in
                tarjeta(t, Self.tonos[i % Self.tonos.count])
            }
        }
        .frame(minWidth: ancho, alignment: .leading)
    }

    private func tarjeta(_ t: TareaVista, _ tono: (barra: Color, rotulo: Color)) -> some View {
        TarjetaOscura(ancho: AuroraNotch.anchoTarea - 6) {
            VStack(alignment: .leading, spacing: 0) {
                if !t.rotulo.isEmpty { RotuloPieza(t.rotulo, color: tono.rotulo) }
                Text(t.texto).font(AuroraNotch.tituloTarea).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 2).help(t.texto)
                Spacer(minLength: 4)
                if let cita = t.cita {
                    Text("«\(cita)»").font(AuroraNotch.cita).foregroundStyle(.white.opacity(0.62)).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    BotonAura("Hecha", estilo: .lleno, ayuda: "Marcar como hecha: " + t.texto) { tareas?.hecha(t) }
                    BotonAura("Agendar", estilo: .oscuro, ayuda: "Abrir Google Calendar con un evento para: " + t.texto) {
                        AbrirCalendario.nuevo(en: agenda.huecos(desde: ahora).first?.inicio ?? ListaAgenda.proximaMedia(ahora), titulo: t.texto)
                    }
                    Spacer(minLength: 0)
                    BotonAura(icono: "xmark", estilo: .oscuro, redondo: true, ayuda: "Descartar: " + t.texto) { tareas?.descartar(t) }
                }
                .padding(.top, 8)
            }
        }
    }

    private var resumen: some View {
        let hechas = tareas?.hechasHoy ?? 0, total = tareas?.total ?? 0
        let quedan = tareas?.abiertas ?? 0
        return TarjetaAura(tono: .trabaja, ancho: AuroraNotch.anchoResumen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        RotuloPieza("Hoy", color: TonoAura.trabaja.rotulo)
                        Text("\(hechas) de \(total)").font(AuroraNotch.titulo).tracking(-0.16)
                    }
                    Spacer(minLength: 4)
                    Dial(lado: 46, valor: total > 0 ? Double(hechas) / Double(total) : 0, colores: [.white.opacity(0.8), .white],
                         marcas: 30, anillo: 4, brillo: 0.2) {
                        NumeroFino(texto: "\(hechas)", tamano: 16, peso: .thin)
                    }
                    .accessibilityLabel("\(hechas) hechas de \(total)")
                }
                Spacer(minLength: 0)
                Text(quedan == 0 ? "Todo al día" : (quedan == 1 ? "Queda 1 por hacer" : "Quedan \(quedan) por hacer"))
                    .font(AuroraNotch.resumenFuente).foregroundStyle(AuroraNotch.resumen)
                if tareas?.delCentro == false {
                    Text("Del cerebro: pendientes de tus notas de reunión.")
                        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(2).padding(.top, 4)
                }
            }
        }
    }
}

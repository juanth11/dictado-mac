import AppKit
import ApplicationServices
import DictadoKit
import Observation
import SwiftUI

// El panel del selector de apps (⌘Tab propio), a la manera del de macOS: vidrio oscuro centrado, la fila de apps con iconos grandes
// (la elegida sobre un cuadro gris claro, sin anillos) y debajo, en filas sobrias, las ventanas de esa app y, si es un navegador,
// las pestañas de cada ventana. La selección de la lista es una franja gris, como en las listas del sistema.
// Todo medido en la rejilla de 4. Sin movimiento en reposo: solo cambia la selección (fundido corto) y, con "Reducir movimiento",
// ni eso. Nada de lo que muestra se escribe en ningún lado.

// MARK: - Medidas

enum AuroraSelector {
    static let icono: CGFloat = 64
    static let celda = CGFloat(DisposicionSelector.celda)
    static let hueco = CGFloat(DisposicionSelector.hueco)
    static let relleno = CGFloat(DisposicionSelector.relleno)
    static let radio: CGFloat = 24
    static let radioCelda: CGFloat = 16
    static let radioTarjeta: CGFloat = 10
    static let margen = AuroraDock.panelMargen
    static let anchoMinimo: CGFloat = 520
    static let altoVentana: CGFloat = 64
    static let altoPestana: CGFloat = 40
    static let huecoLista: CGFloat = 4
    static let sangria: CGFloat = 16
    static let miniatura = CGSize(width: 88, height: 56)
    static let cabecera: CGFloat = 28
    static let pie: CGFloat = 16
    static let aire: CGFloat = 12
    static let listaMaxima: CGFloat = 488
    static let listaVacia: CGFloat = 40

    static let titulo = Font.system(size: 15, weight: .semibold)
    static let cuerpo = Font.system(size: 13, weight: .regular)
    static let etiqueta = Font.system(size: 11, weight: .regular)
    static let rotulo = Font.system(size: 11, weight: .regular)
    static let tonosPestana: [Color] = [Color(hex: 0x4A8DFF), Color(hex: 0xF2784A), Color(hex: 0x30D158), Color(hex: 0xBF5AF2), Color(hex: 0xFF9F0A), Color(hex: 0x40B8D8)]
}

// MARK: - Datos

struct AppSel: Identifiable, Equatable {
    let id: pid_t
    let nombre: String
    let bundleID: String?
    var icono: NSImage?
    static func == (a: AppSel, b: AppSel) -> Bool { a.id == b.id && a.nombre == b.nombre }
}

struct VentanaSel: Identifiable {
    var id: Int
    var titulo: String
    var minimizada = false
    var miniatura: NSImage?
    var ax: AXUIElement?
    var pestanas: [PestanaApp] = []
    var ventanaNav: VentanaNavegador?
}

enum EstadoPestanas: Equatable {
    case noAplica, cargando, listo
    /// Falta el permiso de Automatización sobre el navegador: no se pide desde aquí.
    case sinPermiso
    case fallo
}

/// Un aviso del pie que se puede tocar: pide el permiso que falta.
enum AvisoSelector: Equatable {
    case automatizacion(bundle: String)
    case grabacion
}

/// Lo que se sabe de una app: sus ventanas y, si es un navegador, sus pestañas. Es la caché que se refresca al abrir el selector.
struct DetalleApp {
    var ventanas: [VentanaSel] = []
    var cargandoVentanas = true
    var pestanas = EstadoPestanas.noAplica
    var nav: [VentanaNavegador] = []
    var pestanasInstante = Date.distantPast
    var ventanasInstante = Date.distantPast

    var resumen: [ResumenVentana] {
        ventanas.map { ResumenVentana(pestanas: $0.pestanas.count, activa: $0.pestanas.firstIndex(where: \.activa)) }
    }
    var elementos: [ElementoDetalle] { ListaDetalle.aplanar(resumen) }
    var totalPestanas: Int { ventanas.reduce(0) { $0 + $1.pestanas.count } }
}

@MainActor @Observable
final class EstadoSelector {
    var apps: [AppSel] = []
    var maquina = MaquinaSelector()
    var detalles: [pid_t: DetalleApp] = [:]
    var hayMiniaturas = true
    var anchoPantalla = 1440.0
    var altoPantalla = 900.0
    /// Los renders: el vidrio real no se compone fuera de la pantalla.
    var simulado = false
    @ObservationIgnored var alElegir: ((Int, Int?) -> Void)?
    @ObservationIgnored var alAviso: ((AvisoSelector) -> Void)?

    var appActual: AppSel? { apps.indices.contains(maquina.app) ? apps[maquina.app] : nil }
    var detalleActual: DetalleApp? { appActual.flatMap { detalles[$0.id] } }
    var columnas: Int { DisposicionSelector.columnas(total: apps.count, anchoPantalla: anchoPantalla) }
    var filas: [Range<Int>] { DisposicionSelector.filas(total: apps.count, columnas: columnas) }

    // MARK: Medidas

    var ancho: CGFloat {
        max(CGFloat(DisposicionSelector.anchoFila(columnas: columnas)), AuroraSelector.anchoMinimo) + 2 * AuroraSelector.relleno
    }

    private var altoApps: CGFloat {
        let n = CGFloat(filas.count)
        return n * AuroraSelector.celda + max(0, n - 1) * AuroraSelector.hueco
    }

    func altura(_ e: ElementoDetalle) -> CGFloat {
        switch e {
        case .ventana: return AuroraSelector.altoVentana
        case .pestana: return AuroraSelector.altoPestana
        }
    }

    /// Lo que pide la parte de abajo sin contar la lista.
    private var altoFijo: CGFloat {
        2 * AuroraSelector.relleno + altoApps + 2 * AuroraSelector.aire + 1 + AuroraSelector.cabecera + AuroraSelector.aire + AuroraSelector.pie + AuroraSelector.aire
    }

    var listaMaxima: CGFloat {
        max(120, min(AuroraSelector.listaMaxima, CGFloat(altoPantalla) * 0.9 - altoFijo - 2 * AuroraSelector.margen))
    }

    /// Los elementos que se ven (la selección siempre dentro) y lo que queda fuera por arriba y por abajo.
    var tramo: (rango: Range<Int>, total: Int, alto: CGFloat) {
        let lista = detalleActual?.elementos ?? []
        let alturas = lista.map { Double(altura($0)) }
        let r = ListaDetalle.visibles(alturas: alturas, hueco: Double(AuroraSelector.huecoLista), seleccion: maquina.elemento, maximo: Double(listaMaxima))
        let alto = r.map { altura(lista[$0]) }.reduce(0, +) + CGFloat(max(0, r.count - 1)) * AuroraSelector.huecoLista
        return (r, lista.count, lista.isEmpty ? AuroraSelector.listaVacia : alto)
    }

    var medidas: CGSize {
        CGSize(width: ancho, height: altoFijo + tramo.alto)
    }
}

// MARK: - La vista

struct VistaSelectorApps: View {
    let estado: EstadoSelector
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    private var simulado: Bool { estado.simulado }

    var body: some View {
        let m = estado.medidas
        VStack(spacing: 0) {
            cuadricula
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.vertical, AuroraSelector.aire)
            encabezado.frame(height: AuroraSelector.cabecera)
            lista.padding(.top, AuroraSelector.aire)
            Spacer(minLength: 0)
            pie.frame(height: AuroraSelector.pie)
        }
        .padding(AuroraSelector.relleno)
        .frame(width: m.width, height: m.height, alignment: .top)
        .acabadoDock(radio: AuroraSelector.radio, tonos: .porOmision, sombra: AuroraDock.panelSombra)
        .padding(AuroraSelector.margen)
        .environment(\.auroraTema, .oscuro)
        .environment(\.colorScheme, .dark)
        .environment(\.vidrioSimulado, simulado)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selector de apps")
    }

    // MARK: Fila de apps

    private var cuadricula: some View {
        VStack(spacing: AuroraSelector.hueco) {
            ForEach(Array(estado.filas.enumerated()), id: \.offset) { _, fila in
                HStack(spacing: AuroraSelector.hueco) {
                    ForEach(fila, id: \.self) { i in celdaApp(i) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func celdaApp(_ i: Int) -> some View {
        let app = estado.apps[i]
        let elegida = i == estado.maquina.app
        let dentro = elegida && estado.maquina.elemento != nil
        return ZStack {
            RoundedRectangle(cornerRadius: AuroraSelector.radioCelda, style: .continuous)
                .fill(.white.opacity(elegida ? (dentro ? 0.08 : 0.18) : 0))
            if let icono = app.icono {
                Image(nsImage: icono).resizable().interpolation(.high).frame(width: AuroraSelector.icono, height: AuroraSelector.icono)
            } else {
                Image(systemName: "app.dashed").font(.system(size: 32, weight: .light)).foregroundStyle(AuroraDock.textoSuave)
            }
        }
        .frame(width: AuroraSelector.celda, height: AuroraSelector.celda)
        .contentShape(RoundedRectangle(cornerRadius: AuroraSelector.radioCelda, style: .continuous))
        .animation(sinMovimiento ? nil : .easeOut(duration: AuroraMovimiento.punteroDuracion), value: elegida)
        .onTapGesture { estado.alElegir?(i, nil) }
        .accessibilityElement()
        .accessibilityLabel(app.nombre)
        .accessibilityAddTraits(elegida ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Encabezado, lista y pie

    private var encabezado: some View {
        let d = estado.detalleActual
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(estado.appActual?.nombre ?? "").font(AuroraSelector.titulo).lineLimit(1)
            Text(resumenTexto(d)).font(AuroraSelector.etiqueta).foregroundStyle(AuroraDock.textoSuave).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func resumenTexto(_ d: DetalleApp?) -> String {
        guard let d else { return "" }
        if d.cargandoVentanas && d.ventanas.isEmpty { return "Buscando ventanas…" }
        var partes = [d.ventanas.count == 1 ? "1 ventana" : "\(d.ventanas.count) ventanas"]
        if d.totalPestanas > 0 { partes.append(d.totalPestanas == 1 ? "1 pestaña" : "\(d.totalPestanas) pestañas") }
        else if d.pestanas == .cargando { partes.append("cargando pestañas…") }
        return partes.joined(separator: " · ")
    }

    @ViewBuilder private var lista: some View {
        let t = estado.tramo
        let d = estado.detalleActual
        if let d, !d.elementos.isEmpty {
            VStack(spacing: AuroraSelector.huecoLista) {
                ForEach(Array(t.rango), id: \.self) { k in
                    let e = d.elementos[k]
                    let elegido = estado.maquina.elemento == k
                    Group {
                        switch e {
                        case .ventana(let w): tarjetaVentana(d.ventanas[w], icono: estado.appActual?.icono, elegida: elegido)
                        case .pestana(let w, let p): tarjetaPestana(d.ventanas[w].pestanas[p], elegida: elegido)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { estado.alElegir?(estado.maquina.app, k) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        } else {
            Text(d?.cargandoVentanas == true && (d?.ventanas.isEmpty ?? true) ? "Buscando ventanas…" : "Sin ventanas abiertas")
                .font(AuroraSelector.cuerpo).foregroundStyle(AuroraDock.textoSuave)
                .frame(maxWidth: .infinity, minHeight: AuroraSelector.listaVacia, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func tarjetaVentana(_ v: VentanaSel, icono: NSImage?, elegida: Bool) -> some View {
        let n = v.pestanas.count
        let sub: String = v.minimizada ? "Minimizada" : (n == 0 ? "" : (n == 1 ? "1 pestaña" : "\(n) pestañas"))
        return HStack(spacing: 12) {
            Group {
                if let m = v.miniatura {
                    Image(nsImage: m).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.06)
                        if let icono { Image(nsImage: icono).resizable().scaledToFit().frame(width: 28, height: 28).opacity(0.85) }
                    }
                }
            }
            .frame(width: AuroraSelector.miniatura.width, height: AuroraSelector.miniatura.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(PanelVentanasDock.titulo(v.titulo, maximo: 64)).font(AuroraSelector.cuerpo.weight(.medium)).lineLimit(2)
                if !sub.isEmpty { Text(sub).font(AuroraSelector.etiqueta).foregroundStyle(AuroraDock.textoSuave) }
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(height: AuroraSelector.altoVentana)
        .modifier(FondoTarjetaSel(elegida: elegida))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    private func tarjetaPestana(_ p: PestanaApp, elegida: Bool) -> some View {
        let dominio = EtiquetaPestana.dominio(de: p.url)
        return HStack(spacing: 12) {
            IconoPestana(titulo: p.titulo, url: p.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(PanelVentanasDock.titulo(p.titulo, maximo: 72)).font(AuroraSelector.cuerpo).lineLimit(1)
                    .foregroundStyle(p.activa || elegida ? .white : .white.opacity(0.82))
                if !dominio.isEmpty { Text(dominio).font(AuroraSelector.etiqueta).foregroundStyle(AuroraDock.textoSuave).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if p.activa {
                Circle().fill(AuroraAcento.seleccion).frame(width: 6, height: 6).padding(.trailing, 4)
                    .help("Pestaña activa")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: AuroraSelector.altoPestana)
        .modifier(FondoTarjetaSel(elegida: elegida))
        .padding(.leading, AuroraSelector.sangria + 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(p.activa ? "\(p.titulo), pestaña activa" : p.titulo)
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    private var pie: some View {
        let t = estado.tramo
        let aviso = avisoPie
        return HStack(spacing: 12) {
            if let aviso {
                Button { estado.alAviso?(aviso.tipo) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: aviso.simbolo).font(.system(size: 10, weight: .semibold))
                        Text(aviso.texto).font(AuroraSelector.rotulo).lineLimit(1)
                    }
                    .foregroundStyle(AuroraAcento.seleccion)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("↓ ventanas y pestañas    esc cancelar").font(AuroraSelector.rotulo).foregroundStyle(AuroraDock.textoTenue).lineLimit(1)
            }
            Spacer(minLength: 0)
            if t.rango.count < t.total {
                Text("\(t.rango.lowerBound + 1)–\(t.rango.upperBound) de \(t.total)").font(AuroraSelector.rotulo)
                    .foregroundStyle(AuroraDock.textoTenue)
            }
        }
        .padding(.horizontal, 4)
    }

    private var avisoPie: (tipo: AvisoSelector, texto: String, simbolo: String)? {
        guard let d = estado.detalleActual, let app = estado.appActual else { return nil }
        if d.pestanas == .sinPermiso, let bundle = app.bundleID {
            return (.automatizacion(bundle: bundle), "Permitir ver las pestañas de \(app.nombre)", "lock.open")
        }
        if !estado.hayMiniaturas && !d.ventanas.isEmpty {
            return (.grabacion, "Permitir miniaturas de ventanas (Grabación de pantalla)", "rectangle.dashed")
        }
        return nil
    }
}

/// El fondo de una fila de la lista: nada en reposo; la elegida, una franja gris clara (como las listas de macOS).
private struct FondoTarjetaSel: ViewModifier {
    let elegida: Bool

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: AuroraSelector.radioTarjeta, style: .continuous)
        content.background(forma.fill(.white.opacity(elegida ? 0.16 : 0)))
    }
}

/// Sin favicon (la lista de pestañas no lo trae y no se consulta la red): la inicial del sitio sobre un tono que sale de su dominio.
private struct IconoPestana: View {
    let titulo: String
    let url: String

    var body: some View {
        let dominio = EtiquetaPestana.dominio(de: url)
        let inicial = EtiquetaPestana.inicial(titulo: titulo, url: url)
        let tono = AuroraSelector.tonosPestana[EtiquetaPestana.tono(de: dominio.isEmpty ? titulo : dominio)]
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tono.gradient)
            if inicial.isEmpty {
                Image(systemName: "globe").font(.system(size: 10, weight: .semibold))
            } else {
                Text(inicial).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

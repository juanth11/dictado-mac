import AppKit
import ApplicationServices
import DictadoKit
import Observation
import ScreenCaptureKit
import SwiftUI

// Ventanas flotantes por app. Con el puntero un momento sobre una app abierta del Dock (o clic derecho > Ventanas) sale un panel con
// sus ventanas: título y, si ya diste el permiso de Grabación de pantalla, miniatura. Un clic lleva a esa ventana (Accesibilidad:
// AXRaise + activar la app). En los navegadores controlables por AppleScript (Cra, Chrome y compañía, Safari) se listan también las
// pestañas de cada ventana y se puede saltar a una. Nunca se pide un permiso por cuenta propia: sin permiso se muestra solo el título.

@MainActor @Observable
final class ModeloVentanasApp {
    struct Item: Identifiable {
        let id: Int
        var titulo: String
        var miniatura: NSImage?
        var minimizada = false
        var pestanas: [PestanaApp] = []
        var ventanaNav: VentanaNavegador?
        var ax: AXUIElement?
    }

    let app: EntradaApp
    private(set) var items: [Item] = []
    private(set) var cargando = true
    private(set) var hayAccesibilidad = true
    private(set) var hayMiniaturas = true
    private(set) var familia: FamiliaNavegador?
    var icono: NSImage?
    @ObservationIgnored var alCambiar: (() -> Void)?
    @ObservationIgnored private var generacion = 0

    init(app: EntradaApp) {
        self.app = app
        familia = NavegadoresDock.familia(bundleID: app.bundleID)
    }

    /// Lo que mide el panel, según lo que contiene.
    var medidas: CGSize {
        var alto = 2 * AuroraDockVentanas.relleno + AuroraDockVentanas.cabecera
        if items.isEmpty { alto += 30 }
        for i in items {
            alto += max(AuroraDockVentanas.fila, 0)
            alto += CGFloat(min(i.pestanas.count, PanelVentanasDock.pestanasVisibles)) * AuroraDockVentanas.filaPestana
        }
        alto += CGFloat(max(0, items.count - 1)) * AuroraDockVentanas.separacion
        if !hayMiniaturas || !hayAccesibilidad { alto += 22 }
        return CGSize(width: AuroraDockVentanas.ancho, height: min(alto, AuroraDockVentanas.altoMaximo))
    }

    func soltar() { generacion += 1; items = []; alCambiar = nil }

    /// Los renders: datos ya armados.
    func fijar(_ lista: [Item], accesibilidad: Bool = true, miniaturas: Bool = true) {
        items = lista
        hayAccesibilidad = accesibilidad
        hayMiniaturas = miniaturas
        cargando = false
    }

    func cargar() {
        generacion += 1
        let mia = generacion
        guard let pid = ProcesoApp.pid(app) else { cargando = false; return }
        hayAccesibilidad = AXIsProcessTrusted()
        hayMiniaturas = CGPreflightScreenCaptureAccess()   // solo consulta: no abre ningún diálogo
        var lista: [Item] = []
        if hayAccesibilidad {
            let el = AXUIElementCreateApplication(pid)
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &v) == .success, let ws = v as? [AXUIElement] {
                for (k, w) in ws.enumerated() {
                    var t: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
                    var m: CFTypeRef?
                    AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m)
                    var item = Item(id: k, titulo: (t as? String) ?? "", ax: w)
                    item.minimizada = (m as? Bool) ?? false
                    lista.append(item)
                }
            }
        }
        items = lista
        cargando = false
        alCambiar?()
        let bundle = app.bundleID
        let fam = familia
        if let bundle, let fam {
            Task.detached(priority: .userInitiated) {
                let texto = LecturaVentanas.ejecutar(NavegadoresDock.guionListar(bundleID: bundle, familia: fam))
                let nav = NavegadoresDock.leer(texto ?? "")
                await MainActor.run { [weak self] in
                    guard let self, self.generacion == mia else { return }
                    for k in self.items.indices {
                        self.items[k].ventanaNav = NavegadoresDock.emparejar(titulo: self.items[k].titulo, posicion: k, entre: nav)
                        self.items[k].pestanas = self.items[k].ventanaNav?.pestanas ?? []
                    }
                    self.alCambiar?()
                }
            }
        }
        if hayMiniaturas {
            let marcos = lista.map { LecturaVentanas.marco($0.ax) }
            Task { [weak self] in
                let imgs = await LecturaVentanas.miniaturas(pid: pid, marcos: marcos)
                guard let self, self.generacion == mia else { return }
                for (k, img) in imgs.enumerated() where self.items.indices.contains(k) { self.items[k].miniatura = img }
            }
        }
    }

    // MARK: Ir a una ventana o una pestaña

    func ir(a item: Item) {
        if let w = item.ax {
            if item.minimizada { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, false as CFBoolean) }
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        }
        AppsAbiertasDock.ejecutando(app)?.activate()
    }

    func ir(a pestana: PestanaApp, en item: Item) {
        ir(a: item)
        guard let bundle = app.bundleID, let fam = familia, let v = item.ventanaNav else { return }
        let guion = NavegadoresDock.guionSaltar(bundleID: bundle, familia: fam, ventana: v, pestana: pestana)
        Task.detached(priority: .userInitiated) { _ = LecturaVentanas.ejecutar(guion) }
    }
}

enum ProcesoApp {
    @MainActor static func pid(_ app: EntradaApp) -> pid_t? { AppsAbiertasDock.ejecutando(app)?.processIdentifier }
}

// MARK: - La vista

struct PanelVentanasVista: View {
    let modelo: ModeloVentanasApp
    let estado: EstadoDock
    let tonos: TonosDock
    var simulado = false
    var alElegir: () -> Void = {}

    var body: some View {
        let icono = estado.iconos[modelo.app.id]
        VStack(alignment: .leading, spacing: AuroraDockVentanas.separacion) {
            HStack(spacing: 8) {
                if let icono { Image(nsImage: icono).resizable().frame(width: 20, height: 20) }
                Text(modelo.app.nombre).font(AuroraDock.titulo).lineLimit(1)
                Spacer(minLength: 0)
                Text(modelo.items.count == 1 ? "1 ventana" : "\(modelo.items.count) ventanas").font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave)
            }
            .frame(height: AuroraDockVentanas.cabecera)
            if modelo.items.isEmpty {
                Text(modelo.hayAccesibilidad ? PanelVentanasDock.sinVentanas : PanelVentanasDock.avisoAccesibilidad)
                    .font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave).frame(height: 30)
            }
            ForEach(modelo.items) { item in
                FilaVentana(item: item, modelo: modelo, icono: icono, simulado: simulado, alElegir: alElegir)
            }
            if !modelo.hayMiniaturas || !modelo.hayAccesibilidad {
                Text(!modelo.hayAccesibilidad ? PanelVentanasDock.avisoAccesibilidad : PanelVentanasDock.avisoMiniaturas)
                    .font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoTenue).lineLimit(1).frame(height: 18)
            }
        }
        .padding(AuroraDockVentanas.relleno)
        .frame(width: AuroraDockVentanas.ancho, alignment: .topLeading)
        .acabadoDock(radio: AuroraDock.panelRadio, tonos: tonos, sombra: AuroraDock.panelSombra)
        .padding(AuroraDock.panelMargen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.auroraTema, .oscuro)
        .environment(\.colorScheme, .dark)
        .environment(\.vidrioSimulado, simulado)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ventanas de \(modelo.app.nombre)")
    }
}

private struct FilaVentana: View {
    let item: ModeloVentanasApp.Item
    let modelo: ModeloVentanasApp
    let icono: NSImage?
    var simulado = false
    let alElegir: () -> Void
    @State private var encima = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                modelo.ir(a: item)
                alElegir()
            } label: {
                HStack(spacing: 10) {
                    Group {
                        if let m = item.miniatura {
                            Image(nsImage: m).resizable().scaledToFill()
                        } else {
                            ZStack {
                                Color.white.opacity(0.06)
                                if let icono { Image(nsImage: icono).resizable().scaledToFit().frame(width: 28, height: 28).opacity(0.85) }
                            }
                        }
                    }
                    .frame(width: AuroraDockVentanas.miniatura.width, height: AuroraDockVentanas.miniatura.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PanelVentanasDock.titulo(item.titulo, maximo: 40)).font(AuroraDock.titulo).lineLimit(2)
                        if item.minimizada { Text("Minimizada").font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: AuroraDockVentanas.fila)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { encima = $0 }
            .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(encima ? 0.08 : 0)).padding(.horizontal, -4) }
            if !item.pestanas.isEmpty {
                // En los renders no hay desplazamiento (ImageRenderer no dibuja ScrollView).
                Group { if simulado { lista } else { ScrollView(.vertical, showsIndicators: false) { lista } } }
                .frame(height: CGFloat(min(item.pestanas.count, PanelVentanasDock.pestanasVisibles)) * AuroraDockVentanas.filaPestana, alignment: .top).clipped()
            }
        }
    }

    private var lista: some View {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(item.pestanas) { p in
                            Button {
                                modelo.ir(a: p, en: item)
                                alElegir()
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(p.activa ? Color.white : .white.opacity(0.0)).frame(width: 5, height: 5)
                                    Text(PanelVentanasDock.titulo(p.titulo, maximo: 54)).font(AuroraDock.detalle).lineLimit(1)
                                        .foregroundStyle(p.activa ? .white : AuroraDock.textoSuave)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: AuroraDockVentanas.filaPestana).padding(.leading, AuroraDockVentanas.miniatura.width + 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
    }
}

import AppKit
import DictadoKit
import SwiftUI

// Los paneles que el Dock despliega hacia arriba: la carpeta del Finder (lo último que tocaste, con miniaturas) y el grupo de
// apps. Son ventanas aparte que existen solo mientras están abiertas; al cerrarse se sueltan la vista, el modelo y las miniaturas.

extension AuroraDock {
    static let cabeceraPanel: CGFloat = 36

    /// Alto del panel (sin el aire de la sombra) para `filas` filas de miniaturas: la cabecera, hasta tres filas y el relleno.
    static func altoPanel(filas: Int) -> CGFloat {
        let visibles = CGFloat(max(1, min(filas, CarpetaDock.filasVisibles)))
        return 2 * panelRelleno + cabeceraPanel + panelSeparacion + visibles * celdaAlto
    }

    /// La pila de una carpeta: abanico con pocos elementos y cuadrícula con muchos (`defaults write app.dictado dock.pila abanico|cuadricula`
    /// la fija).
    static func modoPila(_ cuantos: Int) -> ModoPila {
        PilaDock.modo(cuantos: cuantos, preferencia: UserDefaults.dictado.string(forKey: "dock.pila"))
    }

    /// El tamaño del panel (sin el aire de la sombra) según el modo y cuántos elementos tiene.
    static func medidasPanel(modo: ModoPila, cuantos: Int) -> CGSize {
        switch modo {
        case .abanico: return CGSize(width: AuroraDockPila.abanicoAncho, height: AuroraDockPila.altoAbanico(cuantos))
        case .cuadricula: return CGSize(width: anchoPanel(), height: altoPanel(filas: CarpetaDock.filas(cuantos)))
        }
    }
}

/// Qué elemento del panel tiene la selección del teclado (flechas, Espacio, Retorno).
@MainActor @Observable
final class SeleccionPila {
    var indice: Int?
}

/// La entrada del panel: un resorte desde abajo (de donde está su mosaico); con "Reducir movimiento", solo un fundido.
private struct EntradaPanel: ViewModifier {
    @State private var dentro = false
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    func body(content: Content) -> some View {
        content
            .opacity(dentro ? 1 : 0)
            .scaleEffect(dentro || sinMovimiento ? 1 : 0.94, anchor: .bottom)
            .animation(sinMovimiento ? .easeOut(duration: AuroraMovimiento.fundidoSinMovimiento) : .spring(response: 0.35, dampingFraction: 0.82), value: dentro)
            .onAppear { dentro = true }
    }
}

// MARK: - Carpeta

/// El panel de una carpeta: una pila como las de macOS. Con pocos archivos, un abanico (nombre a la izquierda y miniatura a la derecha,
/// curvándose hacia arriba); con muchos, una cuadrícula. Las miniaturas son las reales (QuickLookThumbnailing).
struct PanelCarpetaVista: View {
    let modelo: ModeloCarpeta
    let tonos: TonosDock
    var seleccion = SeleccionPila()
    var simulado = false
    var ahoraFijo: Date?

    var body: some View {
        Group {
            switch AuroraDock.modoPila(modelo.archivos.count) {
            case .abanico: AbanicoCarpeta(modelo: modelo, seleccion: seleccion, simulado: simulado)
            case .cuadricula: CuadriculaCarpeta(modelo: modelo, tonos: tonos, seleccion: seleccion, simulado: simulado, ahoraFijo: ahoraFijo)
            }
        }
        .modifier(EntradaPanel())
        .environment(\.auroraTema, .oscuro)
        .environment(\.colorScheme, .dark)
        .environment(\.vidrioSimulado, simulado)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carpeta \((modelo.ruta as NSString).lastPathComponent)")
    }
}

struct CuadriculaCarpeta: View {
    let modelo: ModeloCarpeta
    let tonos: TonosDock
    let seleccion: SeleccionPila
    var simulado: Bool
    var ahoraFijo: Date?

    var body: some View {
        let columnas = Array(repeating: GridItem(.fixed(AuroraDock.celdaAncho), spacing: 0), count: AuroraDock.panelColumnas)
        let filas = CarpetaDock.filas(modelo.archivos.count)
        VStack(alignment: .leading, spacing: AuroraDock.panelSeparacion) {
            HStack(spacing: 10) {
                CarpetaVidrioEscalada(nombre: "", foto: ContenidoCarpetas.compartido.datos[modelo.ruta]?.foto, ancho: 46)
                    .task { ContenidoCarpetas.compartido.pedir(modelo.ruta) }
                VStack(alignment: .leading, spacing: 2) {
                    RotuloPieza(CarpetaDock.sello(modelo.ruta, maximo: 24))
                    Text(subtitulo).font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave).lineLimit(1)
                }
                Spacer(minLength: 8)
                BotonAura("Abrir", icono: "folder", estilo: .oscuro, ayuda: "Abrir la carpeta en Finder") { NSWorkspace.shared.open(modelo.url) }
            }
            .frame(height: AuroraDock.cabeceraPanel)
            if modelo.archivos.isEmpty {
                Text(modelo.cargando ? "Leyendo…" : (modelo.legible ? "La carpeta está vacía" : "No se pudo leer la carpeta"))
                    .font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave)
                    .frame(maxWidth: .infinity, minHeight: AuroraDock.celdaAlto)
            } else {
                // En los renders no hay desplazamiento (ImageRenderer no dibuja ScrollView): se recorta a las filas visibles.
                Group {
                    if simulado {
                        LazyVGrid(columns: columnas, spacing: 0) { celdas }
                            .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        ScrollViewReader { lector in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: columnas, spacing: 0) { celdas }
                            }
                            .onChange(of: seleccion.indice) { _, i in
                                if let i, modelo.archivos.indices.contains(i) { withAnimation(.easeOut(duration: 0.15)) { lector.scrollTo(modelo.archivos[i].id) } }
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(filas, CarpetaDock.filasVisibles)) * AuroraDock.celdaAlto)
                .clipped()
            }
        }
        .padding(AuroraDock.panelRelleno)
        .frame(width: AuroraDock.anchoPanel(), alignment: .leading)
        .acabadoDock(radio: AuroraDock.panelRadio, tonos: tonos, sombra: AuroraDock.panelSombra)
        .padding(AuroraDock.panelMargen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var celdas: some View {
        ForEach(Array(modelo.archivos.enumerated()), id: \.element.id) { i, a in
            CeldaArchivo(archivo: a, lista: modelo.archivos, imagen: modelo.miniaturas[a.ruta], ahora: ahoraFijo ?? Date(), seleccionada: seleccion.indice == i)
        }
    }

    private var subtitulo: String {
        let n = modelo.archivos.count
        return n == 0 ? "Lo último que modificaste" : "\(n) recientes · lo último que modificaste"
    }
}

/// El abanico: el más reciente abajo, junto a la carpeta, y los demás subiendo en una curva suave; cada uno con su nombre en una
/// píldora a la izquierda. Sin recuadro: flota sobre lo que haya detrás, como las pilas de macOS.
struct AbanicoCarpeta: View {
    let modelo: ModeloCarpeta
    let seleccion: SeleccionPila
    var simulado: Bool

    var body: some View {
        let n = modelo.archivos.count
        let ancho = AuroraDockPila.abanicoAncho
        VStack(spacing: 0) {
            // Arriba del todo: abrir la carpeta en el Finder.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button { NSWorkspace.shared.open(modelo.url) } label: {
                    HStack(spacing: 6) {
                        CarpetaVidrioEscalada(nombre: "", foto: ContenidoCarpetas.compartido.datos[modelo.ruta]?.foto, ancho: 22)
                        Text("Abrir " + (modelo.ruta as NSString).lastPathComponent).font(AuroraDock.detalle).lineLimit(1)
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background { Capsule().fill(Color.black.opacity(0.62)) }
                    .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
                    .frame(maxWidth: AuroraDockPila.abanicoEtiquetaMax + 60)
                }
                .buttonStyle(PulsadoAurora())
                .help("Abrir la carpeta en Finder")
                Spacer(minLength: 0)
            }
            .frame(width: ancho, height: AuroraDockPila.abanicoCabecera)
            // Del más reciente (abajo) al más antiguo (arriba): en la pantalla el último de la lista va primero.
            ForEach(Array((0..<n).reversed()), id: \.self) { i in
                FilaAbanico(archivo: modelo.archivos[i], imagen: modelo.miniaturas[modelo.archivos[i].ruta], indice: i, total: n, seleccionada: seleccion.indice == i)
            }
        }
        .padding(.vertical, AuroraDockPila.abanicoMargen)
        .frame(width: ancho)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(AuroraDock.panelMargen - AuroraDockPila.abanicoMargen)
    }
}

struct FilaAbanico: View {
    let archivo: ArchivoReciente
    let imagen: NSImage?
    let indice: Int
    let total: Int
    let seleccionada: Bool
    @State private var encima = false
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        let (desvio, giro) = PilaDock.abanico(indice: indice, de: total)
        let lado = AuroraDockPila.abanicoMiniatura
        let resaltada = seleccionada || encima
        HStack(spacing: 0) {
            Text(archivo.nombre).font(AuroraDock.detalle).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 12).frame(height: 26)
                .background { Capsule().fill(resaltada ? Color(white: 0.30).opacity(0.92) : Color.black.opacity(0.62)) }
                .overlay { Capsule().strokeBorder(resaltada ? AuroraDockPila.seleccionFilo : .white.opacity(0.14), lineWidth: 1) }
                .frame(maxWidth: AuroraDockPila.abanicoEtiquetaMax)
                .frame(width: AuroraDockPila.abanicoAncho / 2 - lado / 2 + CGFloat(desvio) - 12, alignment: .trailing)
            Color.clear.frame(width: 12, height: 1)
            Group {
                if let imagen {
                    Image(nsImage: imagen).resizable().interpolation(.high).scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.18))
                }
            }
            .frame(width: lado, height: lado)
            .padding(2)
            .background { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white) }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .rotationEffect(.degrees(giro))
            .scaleEffect(resaltada && !sinMovimiento ? 1.08 : 1)
            .animation(AuroraMovimiento.puntero, value: resaltada)
            Spacer(minLength: 0)
        }
        .frame(width: AuroraDockPila.abanicoAncho, height: AuroraDockPila.abanicoPaso)
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        .onTapGesture { AccionArchivo.abrir(archivo) }
        .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: archivo.ruta)) ?? NSItemProvider() }
        .contextMenu { MenuArchivo(archivo: archivo, lista: [archivo]) }
        .help(archivo.nombre)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(archivo.esCarpeta ? "Carpeta" : "Archivo") \(archivo.nombre)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { AccionArchivo.abrir(archivo) }
    }
}

struct MenuArchivo: View {
    let archivo: ArchivoReciente
    let lista: [ArchivoReciente]

    var body: some View {
        Button("Abrir") { AccionArchivo.abrir(archivo) }
        Button("Mostrar en Finder") { AccionArchivo.mostrarEnFinder(archivo) }
        Button("Vista rápida") { AccionArchivo.vistaRapida(archivo, de: lista) }
        Divider()
        Button("Copiar archivo") { AccionArchivo.copiarArchivo(archivo) }
        Button("Copiar nombre") { AccionArchivo.copiarNombre(archivo) }
        Button("Copiar ruta") { AccionArchivo.copiarRuta(archivo) }
        Divider()
        Button("Mover a la papelera") { AccionArchivo.aLaPapelera(archivo) }
    }
}

struct CeldaArchivo: View {
    let archivo: ArchivoReciente
    var lista: [ArchivoReciente] = []
    let imagen: NSImage?
    let ahora: Date
    var seleccionada = false
    @State private var encima = false

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let imagen {
                    Image(nsImage: imagen).resizable().interpolation(.high).scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: AuroraDock.miniaturaRadio, style: .continuous).fill(.white.opacity(0.06))
                }
            }
            .frame(width: AuroraDock.miniatura, height: AuroraDock.miniatura)
            .clipShape(RoundedRectangle(cornerRadius: AuroraDock.miniaturaRadio, style: .continuous))
            Text(archivo.nombre).font(AuroraDock.nombreArchivo).lineLimit(2).multilineTextAlignment(.center)
                .frame(width: AuroraDock.celdaAncho - 10)
            Text(CarpetaDock.hace(archivo.modificado, ahora: ahora)).font(AuroraDock.cifraPequena).foregroundStyle(AuroraDock.textoTenue).lineLimit(1)
        }
        .frame(width: AuroraDock.celdaAncho, height: AuroraDock.celdaAlto, alignment: .top)
        .padding(.top, 4)
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(seleccionada ? AuroraDockPila.seleccion : (encima ? .white.opacity(0.08) : .clear)) }
        .overlay { if seleccionada { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AuroraDockPila.seleccionFilo, lineWidth: 1) } }
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        .onTapGesture { AccionArchivo.abrir(archivo) }
        .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: archivo.ruta)) ?? NSItemProvider() }
        .contextMenu { MenuArchivo(archivo: archivo, lista: lista.isEmpty ? [archivo] : lista) }
        .help(archivo.nombre)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(archivo.esCarpeta ? "Carpeta" : "Archivo") \(archivo.nombre), \(CarpetaDock.hace(archivo.modificado, ahora: ahora))")
        .accessibilityAddTraits(seleccionada ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { AccionArchivo.abrir(archivo) }
    }
}

// MARK: - Grupo de apps (y apps abiertas)

struct PanelGrupoVista: View {
    let nombre: String
    let apps: [EntradaApp]
    let estado: EstadoDock
    let tonos: TonosDock
    var seleccion = SeleccionPila()
    var simulado = false
    var subtitulo: String?

    var body: some View {
        let columnas = Array(repeating: GridItem(.fixed(AuroraDock.celdaAncho), spacing: 0), count: AuroraDock.panelColumnas)
        let filas = CarpetaDock.filas(apps.count)
        VStack(alignment: .leading, spacing: AuroraDock.panelSeparacion) {
            VStack(alignment: .leading, spacing: 2) {
                RotuloPieza(nombre)
                Text(subtitulo ?? "\(apps.count) apps").font(AuroraDock.detalle).foregroundStyle(AuroraDock.textoSuave)
            }
            .frame(height: AuroraDock.cabeceraPanel, alignment: .leading)
            Group {
                if simulado {
                    LazyVGrid(columns: columnas, spacing: 0) { celdas }
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: columnas, spacing: 0) { celdas }
                    }
                }
            }
            .clipped()
            .frame(height: CGFloat(min(filas, CarpetaDock.filasVisibles)) * AuroraDock.celdaAlto)
        }
        .padding(AuroraDock.panelRelleno)
        .frame(width: AuroraDock.anchoPanel(), alignment: .leading)
        .acabadoDock(radio: AuroraDock.panelRadio, tonos: tonos, sombra: AuroraDock.panelSombra)
        .padding(AuroraDock.panelMargen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .modifier(EntradaPanel())
        .environment(\.auroraTema, .oscuro)
        .environment(\.colorScheme, .dark)
        .environment(\.vidrioSimulado, simulado)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Grupo \(nombre)")
    }

    @ViewBuilder private var celdas: some View {
        ForEach(Array(apps.enumerated()), id: \.element.id) { i, a in CeldaAppDock(app: a, estado: estado, seleccionada: seleccion.indice == i) }
    }
}

struct CeldaAppDock: View {
    let app: EntradaApp
    let estado: EstadoDock
    var seleccionada = false
    @State private var encima = false

    private var abierta: Bool { app.bundleID.map { estado.abiertas.abiertas.contains($0) } ?? false }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let i = estado.iconos[app.id] {
                    Image(nsImage: i).resizable().interpolation(.high).frame(width: AuroraDock.icono, height: AuroraDock.icono)
                } else {
                    RoundedRectangle(cornerRadius: AuroraDock.icono * AuroraMedida.iconoRadioProporcion, style: .continuous)
                        .fill(.white.opacity(0.06)).frame(width: AuroraDock.icono, height: AuroraDock.icono)
                }
            }
            Text(app.nombre).font(AuroraDock.nombreArchivo).lineLimit(2).multilineTextAlignment(.center).frame(width: AuroraDock.celdaAncho - 10)
            Capsule().fill(.white.opacity(abierta ? 0.8 : 0)).frame(width: AuroraDock.indicador.width, height: AuroraDock.indicador.height)
        }
        .frame(width: AuroraDock.celdaAncho, height: AuroraDock.celdaAlto, alignment: .top)
        .padding(.top, 4)
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(seleccionada ? AuroraDockPila.seleccion : (encima ? .white.opacity(0.08) : .clear)) }
        .overlay { if seleccionada { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AuroraDockPila.seleccionFilo, lineWidth: 1) } }
        .contentShape(Rectangle())
        .onHover { encima = $0 }
        .onTapGesture { AppsAbiertasDock.abrir(app) }
        .menuAppDock(app, estado: estado)
        .help(app.nombre)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.nombre + (abierta ? ", abierta" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { AppsAbiertasDock.abrir(app) }
    }
}

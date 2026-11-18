import AppKit
import DictadoKit
import Observation
import SwiftUI

// El Dock en Aurora: una barra oscura con piezas (la pieza es un dato real, no un adorno), un selector de espacios encima y
// paneles que se despliegan hacia arriba. Estático en reposo; solo se mueve el puntero (escala 1,06) y los cambios de dato.
// Las medidas, la letra y los colores salen de `AuroraDock`; las piezas, de DockPiezas.swift; los paneles, de DockPaneles.swift.

/// Lo que cambia de una pantalla a otra: el ancho que cabe, los tonos de su fondo y si ya se mostró.
@MainActor @Observable
final class PantallaDock {
    var anchoDisponible: CGFloat
    var tonos = TonosDock.porOmision
    /// Falso mientras entra o sale (fundido y desliza de 12 pt); en reposo, verdadero.
    var aparecida = false
    /// Renders: el vidrio real no se compone fuera de la pantalla.
    var simulado = false
    @ObservationIgnored var alCambiarAncho: ((CGFloat) -> Void)?
    /// El efecto lupa de la barra de esta pantalla.
    let lupa = LupaPantalla()

    init(anchoDisponible: CGFloat) { self.anchoDisponible = anchoDisponible }
}

// MARK: - Acabado

/// El desenfoque de lo que hay detrás de la ventana (el material del sistema), recortado a la forma redondeada.
struct DesenfoqueDock: NSViewRepresentable {
    let radio: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = .hudWindow
        v.state = .active
        v.maskImage = Self.mascara(radio)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}

    static func mascara(_ radio: CGFloat) -> NSImage {
        let lado = radio * 2 + 1
        let imagen = NSImage(size: NSSize(width: lado, height: lado), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: radio, yRadius: radio).fill()
            return true
        }
        imagen.capInsets = NSEdgeInsets(top: radio, left: radio, bottom: radio, right: radio)
        imagen.resizingMode = .stretch
        return imagen
    }
}

/// El acabado de la barra, el selector y los paneles: vidrio (el desenfoque del sistema), una base oscura, un degradado sutil de la
/// paleta del espacio (del primer al segundo tono, en diagonal), una luz suave arriba y un filo fino de luz que se apaga hacia abajo.
/// Sin grano, sin puntos y sin franjas. Estático.
struct AcabadoDock: ViewModifier {
    let radio: CGFloat
    let tonos: TonosDock
    var sombra = AuroraDock.sombra
    @Environment(\.vidrioSimulado) private var simulado

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        content.background {
            ZStack {
                if !simulado { DesenfoqueDock(radio: radio) }
                forma.fill(tonos.hondo.opacity(AuroraDockPila.baseOpacidad))
                forma.fill(LinearGradient(colors: [tonos.c1.opacity(AuroraDockPila.degradadoOpacidad), tonos.c2.opacity(AuroraDockPila.degradadoOpacidad * 0.8)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                forma.fill(LinearGradient(colors: [AuroraDockPila.luzInterior, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
                forma.strokeBorder(LinearGradient(colors: [AuroraDockPila.filoArriba, AuroraDockPila.filoAbajo], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(sombra.opacidad), radius: sombra.radio, y: sombra.y)
        }
    }
}

extension View {
    func acabadoDock(radio: CGFloat, tonos: TonosDock, sombra: (radio: CGFloat, y: CGFloat, opacidad: Double) = AuroraDock.sombra) -> some View {
        modifier(AcabadoDock(radio: radio, tonos: tonos, sombra: sombra))
    }
}

// MARK: - La barra

/// La barra con sus piezas. Va en su propia ventana: lo transparente que la rodea es solo el aire de la sombra.
struct VistaDock: View {
    let estado: EstadoDock
    let pantalla: PantallaDock
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        let disposicion = ReglasDock.colocar(estado.piezas, anchoDisponible: pantalla.anchoDisponible)
        BarraDock(estado: estado, disposicion: disposicion, tonos: pantalla.tonos, lupa: pantalla.lupa)
            .padding(.bottom, AuroraDock.margenInferior)
            .padding(.top, AuroraDock.margenSombra)
            .padding(.horizontal, AuroraDock.margenSombra)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .lupaDock(pantalla.lupa)
            .coordinateSpace(name: "dock")
            .entradaDock(pantalla)
            .environment(\.lupaActiva, pantalla.lupa.activa && !sinMovimiento)
            .environment(\.auroraTema, .oscuro)
            .environment(\.colorScheme, .dark)
            .environment(\.vidrioSimulado, pantalla.simulado)
            .onChange(of: disposicion.ancho) { _, nuevo in pantalla.alCambiarAncho?(CGFloat(nuevo)) }
            .task(id: estado.appsVisibles.map(\.id)) { estado.pedirIconos(de: estado.appsVisibles) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dock")
    }
}

/// El selector de espacios, en su propia ventana encima de la barra.
struct VistaSelectorDock: View {
    let estado: EstadoDock
    let pantalla: PantallaDock

    var body: some View {
        SelectorEspacios(estado: estado, tonos: pantalla.tonos)
            .padding(AuroraDock.margenSombra)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .entradaDock(pantalla)
            .environment(\.auroraTema, .oscuro)
            .environment(\.colorScheme, .dark)
            .environment(\.vidrioSimulado, pantalla.simulado)
    }
}

extension View {
    /// Entrar y salir: un fundido y 12 pt de desliza (solo fundido con "Reducir movimiento"). En reposo no hay nada animado.
    func entradaDock(_ pantalla: PantallaDock) -> some View { modifier(EntradaDock(pantalla: pantalla)) }
}

private struct EntradaDock: ViewModifier {
    let pantalla: PantallaDock
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    func body(content: Content) -> some View {
        content
            .opacity(pantalla.aparecida ? 1 : 0)
            .offset(y: pantalla.aparecida || sinMovimiento ? 0 : 12)
            .animation(sinMovimiento ? .easeOut(duration: AuroraMovimiento.fundidoSinMovimiento) : AuroraMovimiento.espacio, value: pantalla.aparecida)
    }
}

struct BarraDock: View {
    let estado: EstadoDock
    let disposicion: DisposicionDock
    let tonos: TonosDock
    var lupa: LupaPantalla?
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        HStack(alignment: .top, spacing: AuroraDock.separacion) {
            ForEach(Array(disposicion.piezas.enumerated()), id: \.offset) { i, c in
                PiezaDockVista(colocada: c, estado: estado, tonos: tonos)
                    .lupaPieza(sinMovimiento ? nil : lupa, indice: i, crece: piezaCreceConLupa(c.pieza))
            }
        }
        .fixedSize()
        .id(estado.espacioActual?.nombre ?? "")
        .transition(.asymmetric(insertion: sinMovimiento ? .opacity : .opacity.combined(with: .offset(y: 12)), removal: .opacity))
        .padding(.top, AuroraDock.relleno)
        .padding(.horizontal, AuroraDock.relleno)
        .padding(.bottom, AuroraDock.rellenoInferior)
        .frame(height: AuroraDock.alto, alignment: .top)
        .cristalDock(sinMovimiento ? nil : lupa, radio: AuroraDock.radio, tonos: tonos)
        .onChange(of: disposicion.piezas.count, initial: true) { _, n in lupa?.limitar(n) }
        .animation(sinMovimiento ? nil : AuroraMovimiento.espacio, value: estado.espacioActual?.nombre)
        .animation(sinMovimiento ? nil : AuroraMovimiento.espacio, value: tonos)   // la paleta del espacio entra con suavidad
    }
}

// MARK: - Selector de espacios

/// Encima de la barra: una cápsula con un círculo por espacio y un "+" aparte que abre `espacios.txt`. Elegir un espacio llama
/// al mismo código que el lanzador de la isla (`LanzadorIsla.elegirEspacio`): el espacio actual es uno solo.
struct SelectorEspacios: View {
    let estado: EstadoDock
    let tonos: TonosDock

    var body: some View {
        let lado = AuroraDock.selectorAlto
        let actual = estado.espacioActual?.nombre
        HStack(spacing: 8) {
            if !estado.espacios.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(estado.espacios.enumerated()), id: \.offset) { i, e in
                        ChipEspacio(numero: i + 1, espacio: e, activo: e.nombre == actual) { estado.acciones.elegirEspacio(e) }
                    }
                }
                .padding(.horizontal, (lado - AuroraDock.selectorChip) / 2)
                .frame(height: lado)
                .acabadoDock(radio: lado / 2, tonos: tonos)
            }
            Button { estado.acciones.masEspacios() } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: lado, height: lado).contentShape(Circle())
            }
            .buttonStyle(PulsadoAurora())
            .acabadoDock(radio: lado / 2, tonos: tonos)
            .help("Editar espacios.txt: ahí se eligen las piezas de cada espacio")
            .accessibilityLabel("Editar espacios")
        }
        .fixedSize()
    }
}

struct ChipEspacio: View {
    let numero: Int
    let espacio: EspacioIsla
    let activo: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Text("\(numero)")
                .font(AuroraDock.chipFuente)
                .foregroundStyle(activo && espacio.acento != nil ? Color.black.opacity(0.86) : .white.opacity(activo ? 1 : 0.7))
                .frame(width: AuroraDock.selectorChip, height: AuroraDock.selectorChip)
                .background { Circle().fill(activo ? (espacio.acento ?? AuroraDock.chipActivo) : AuroraDock.chipReposo) }
                .overlay { if encima && !activo { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) } }
                .contentShape(Circle())
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .help(espacio.nombre + " · " + LanzadorIsla.resumen(espacio) + " · Hyper + \(numero)")
        .accessibilityLabel("Espacio \(espacio.nombre)")
        .accessibilityAddTraits(activo ? [.isButton, .isSelected] : .isButton)
    }
}

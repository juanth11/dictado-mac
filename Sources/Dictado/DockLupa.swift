import DictadoKit
import Observation
import SwiftUI

// El efecto lupa del Dock. Al mover el puntero por la barra, los iconos y las carpetas cercanos crecen sobre su base (hacia arriba,
// 1,5 × bajo el puntero) y las vecinas se apartan; la barra de vidrio se ensancha lo justo. La matemática vive en `LupaDock`
// (DictadoKit, con pruebas). Aquí solo hay el estado y las vistas.
//
// Rendimiento: el puntero se lee con `onContinuousHover` en la raíz y escribe en un solo modelo observable; cada pieza lee su efecto
// en un modificador propio, así el árbol de la barra no se reconstruye (solo se reevalúan los modificadores). Sin "Reducir
// movimiento" y apagable con `defaults write app.dictado dock.lupa -bool false`.

@MainActor @Observable
final class LupaPantalla {
    /// El efecto de cada pieza, por su posición en la barra.
    private(set) var efectos: [Int: LupaDock.Efecto] = [:]
    private(set) var crecimiento = (izquierda: CGFloat(0), derecha: CGFloat(0))
    private(set) var puntero: CGFloat?
    /// Falso: sin lupa (apagada con defaults, o "Reducir movimiento").
    var activa = LupaPantalla.preferencia
    @ObservationIgnored private var marcos: [Int: (marco: CGRect, crece: Bool)] = [:]
    @ObservationIgnored private var orden: [(indice: Int, pieza: LupaDock.Pieza)] = []

    static var preferencia: Bool { UserDefaults.dictado.object(forKey: "dock.lupa") as? Bool ?? true }

    func efecto(_ i: Int) -> LupaDock.Efecto { efectos[i] ?? .reposo }

    /// Cada pieza avisa de su sitio en reposo (en el espacio "dock"). No es observable: no vuelve a dibujar nada.
    func registrar(_ i: Int, _ marco: CGRect, crece: Bool) {
        marcos[i] = (marco, crece)
        orden = []
    }

    /// La barra tiene `cuantas` piezas: lo medido de las que ya no existen se descarta.
    func limitar(_ cuantas: Int) {
        marcos = marcos.filter { $0.key < cuantas }
        orden = []
    }

    func olvidar() {
        marcos = [:]
        orden = []
        reposo()
    }

    func mover(_ x: CGFloat?) {
        guard activa, let x else { return reposo() }
        if orden.isEmpty {
            orden = marcos.map { ($0.key, LupaDock.Pieza(izquierda: Double($0.value.marco.minX), ancho: Double($0.value.marco.width), crece: $0.value.crece)) }
                .sorted { $0.1.izquierda < $1.1.izquierda }
        }
        guard !orden.isEmpty else { return }
        if let p = puntero, abs(p - x) < 0.5 { return }
        let r = LupaDock.calcular(orden.map(\.pieza), puntero: Double(x))
        var nuevos: [Int: LupaDock.Efecto] = [:]
        for (k, e) in r.efectos.enumerated() { nuevos[orden[k].indice] = e }
        efectos = nuevos
        crecimiento = (CGFloat(r.crecimientoIzquierda), CGFloat(r.crecimientoDerecha))
        puntero = x
    }

    func reposo() {
        guard puntero != nil || !efectos.isEmpty else { return }
        efectos = [:]
        crecimiento = (0, 0)
        puntero = nil
    }

    /// Renders: fija los marcos en reposo (ImageRenderer no mide) y el puntero.
    func simular(marcos nuevos: [(CGRect, Bool)], puntero x: CGFloat) {
        marcos = [:]
        for (i, m) in nuevos.enumerated() { marcos[i] = (m.0, m.1) }
        orden = []
        activa = true
        puntero = nil
        mover(x)
    }
}

/// Qué piezas crecen: las que son un icono o una carpeta. Los datos (reloj, agenda…) no crecen, solo se apartan.
func piezaCreceConLupa(_ p: PiezaDock) -> Bool {
    switch p {
    case .app, .carpeta, .grupo, .abiertas, .papelera: return true
    default: return false
    }
}

/// Aplica el efecto a una pieza: escala sobre su base y corrimiento horizontal. Va en su propio modificador para que, al moverse el
/// puntero, solo se reevalúe esto y no la pieza.
struct LupaPieza: ViewModifier {
    let indice: Int
    let crece: Bool
    let lupa: LupaPantalla

    func body(content: Content) -> some View {
        let e = lupa.efecto(indice)
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dock")) } action: { lupa.registrar(indice, $0, crece: crece) }
            .scaleEffect(e.escala, anchor: .bottom)
            .offset(x: e.desplazamiento)
            .zIndex(e.escala)
    }
}

/// Lo que se ve de la barra de vidrio: se ensancha por cada lado lo que crece la fila.
struct CristalLupa: ViewModifier {
    let lupa: LupaPantalla
    let radio: CGFloat
    let tonos: TonosDock

    func body(content: Content) -> some View {
        let g = lupa.crecimiento
        content.background {
            GeometryReader { geo in
                Color.clear
                    .frame(width: geo.size.width + g.izquierda + g.derecha, height: geo.size.height)
                    .acabadoDock(radio: radio, tonos: tonos)
                    .offset(x: -g.izquierda)
            }
        }
    }
}

/// El puntero sobre toda la ventana de la barra (el aire de arriba incluido: los iconos grandes sobresalen por ahí).
struct SeguimientoLupa: ViewModifier {
    let lupa: LupaPantalla
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    func body(content: Content) -> some View {
        content.onContinuousHover(coordinateSpace: .named("dock")) { fase in
            guard lupa.activa, !sinMovimiento else { return }
            switch fase {
            case .active(let p):
                withAnimation(lupa.puntero == nil ? AuroraDockLupa.entrada : AuroraDockLupa.seguir) { lupa.mover(p.x) }
            case .ended:
                withAnimation(AuroraDockLupa.salida) { lupa.mover(nil) }
            }
        }
    }
}

extension View {
    /// La barra de vidrio, con crecimiento si hay lupa.
    func cristalDock(_ lupa: LupaPantalla?, radio: CGFloat, tonos: TonosDock) -> some View {
        modifier(CristalOpcional(lupa: lupa, radio: radio, tonos: tonos))
    }

    func lupaPieza(_ lupa: LupaPantalla?, indice: Int, crece: Bool) -> some View {
        modifier(PiezaOpcional(lupa: lupa, indice: indice, crece: crece))
    }

    func lupaDock(_ lupa: LupaPantalla?) -> some View {
        modifier(SeguimientoLupaOpcional(lupa: lupa))
    }
}

private struct CristalOpcional: ViewModifier {
    let lupa: LupaPantalla?
    let radio: CGFloat
    let tonos: TonosDock
    func body(content: Content) -> some View {
        if let lupa { content.modifier(CristalLupa(lupa: lupa, radio: radio, tonos: tonos)) } else { content.acabadoDock(radio: radio, tonos: tonos) }
    }
}

private struct PiezaOpcional: ViewModifier {
    let lupa: LupaPantalla?
    let indice: Int
    let crece: Bool
    func body(content: Content) -> some View {
        if let lupa { content.modifier(LupaPieza(indice: indice, crece: crece, lupa: lupa)) } else { content }
    }
}

private struct SeguimientoLupaOpcional: ViewModifier {
    let lupa: LupaPantalla?
    func body(content: Content) -> some View {
        if let lupa { content.modifier(SeguimientoLupa(lupa: lupa)) } else { content }
    }
}

private struct LupaActivaClave: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Con la lupa encendida las piezas no hacen su propio "crecer al pasar" (se sumaría al de la lupa).
    var lupaActiva: Bool {
        get { self[LupaActivaClave.self] }
        set { self[LupaActivaClave.self] = newValue }
    }
}

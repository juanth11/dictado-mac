import CoreGraphics
import Testing
@testable import DictadoKit

private func v(_ id: UInt32, _ bundle: String?, x: CGFloat = 0, capa: Int = 0, ancho: CGFloat = 800, alto: CGFloat = 600, alfa: Double = 1) -> VentanaMundo {
    VentanaMundo(id: id, pid: Int32(id), bundle: bundle, capa: capa, marco: CGRect(x: x, y: 0, width: ancho, height: alto), alfa: alfa)
}

private func debajo(_ p: PlanVelo) -> UInt32? {
    if case .debajoDe(let id, _) = p { return id }
    return nil
}

private let sinAjustes = AjustesVelo()

@Test("El velo va justo debajo de la ventana de más arriba de la app al frente")
func debajoDeLaActiva() {
    let ventanas = [v(1, "a"), v(2, "b"), v(3, "c")]
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "a"), ajustes: sinAjustes)) == 1)
}

@Test("Las ventanas de otras apps por encima de la activa no cambian la decisión")
func otraAppEncima() {
    let ventanas = [v(9, "z"), v(1, "a"), v(2, "a"), v(3, "b")]
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "a"), ajustes: sinAjustes)) == 1)
}

@Test("Con varias ventanas de la app, manda la que dice Accesibilidad")
func marcoEnfocado() {
    let ventanas = [v(1, "a", x: 0), v(2, "a", x: 1000), v(3, "b")]
    let s = SituacionVelo(bundleAlFrente: "a", marcoEnfocado: CGRect(x: 1001, y: 1, width: 800, height: 600))
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: s, ajustes: sinAjustes)) == 2)
}

@Test("Toda la app: debajo de la ventana más baja de la app")
func todaLaApp() {
    let ventanas = [v(1, "a"), v(2, "b"), v(3, "a"), v(4, "c"), v(5, "a")]
    let aj = AjustesVelo(todaLaApp: true)
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "a"), ajustes: aj)) == 5)
}

@Test("Grupo: las compañeras se quedan nítidas (su ventana de más arriba)")
func grupos() {
    let ventanas = [v(1, "a"), v(2, "x"), v(3, "b"), v(4, "b"), v(5, "c")]
    let aj = AjustesVelo(grupos: [["a", "b"]])
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "a"), ajustes: aj)) == 3)
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "c"), ajustes: aj)) == 5)
}

@Test("Grupo con toda la app: hasta la ventana más baja de cualquiera del grupo")
func gruposYTodaLaApp() {
    let ventanas = [v(1, "a"), v(2, "b"), v(3, "x"), v(4, "b")]
    let aj = AjustesVelo(todaLaApp: true, grupos: [["a", "b"]])
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "a"), ajustes: aj)) == 4)
}

@Test("Una app ignorada apaga el velo")
func ignorada() {
    let aj = AjustesVelo(ignoradas: ["a"])
    #expect(DecisionVelo.plan(ventanas: [v(1, "a")], situacion: .init(bundleAlFrente: "a"), ajustes: aj) == .ocultar(.ignorada))
}

@Test("Sin ventanas de la app al frente (Finder solo con el escritorio) se oculta")
func sinVentana() {
    let ventanas = [v(1, "b"), v(2, "c")]
    #expect(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "a"), ajustes: sinAjustes) == .ocultar(.sinVentana))
}

@Test("Sin app al frente se oculta")
func sinApp() {
    #expect(DecisionVelo.plan(ventanas: [v(1, "a")], situacion: .init(bundleAlFrente: nil), ajustes: sinAjustes) == .ocultar(.sinApp))
}

@Test("Menús, avisos y piezas chicas o transparentes no cuentan como ventana")
func noSonVentanas() {
    let ventanas = [v(1, "a", capa: 25), v(2, "a", ancho: 40, alto: 20), v(3, "a", alfa: 0), v(4, "a"), v(5, "b")]
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: .init(bundleAlFrente: "a"), ajustes: sinAjustes)) == 4)
}

@Test("Mission Control y pantalla completa ocultan el velo (la segunda, solo si se pidió)")
func misionYCompleta() {
    let ventanas = [v(1, "a"), v(2, "b")]
    let mc = SituacionVelo(bundleAlFrente: "a", misionControl: true)
    #expect(DecisionVelo.plan(ventanas: ventanas, situacion: mc, ajustes: sinAjustes) == .ocultar(.misionControl))
    let pc = SituacionVelo(bundleAlFrente: "a", pantallaCompleta: true)
    #expect(DecisionVelo.plan(ventanas: ventanas, situacion: pc, ajustes: sinAjustes) == .ocultar(.pantallaCompleta))
    let libre = AjustesVelo(ocultarEnPantallaCompleta: false)
    #expect(debajo(DecisionVelo.plan(ventanas: ventanas, situacion: pc, ajustes: libre)) == 1)
}

@Test("El plan trae el marco de la ventana para elegir la pantalla")
func marcoDelPlan() {
    let p = DecisionVelo.plan(ventanas: [v(1, "a", x: 1920)], situacion: .init(bundleAlFrente: "a"), ajustes: sinAjustes)
    #expect(p == .debajoDe(id: 1, marco: CGRect(x: 1920, y: 0, width: 800, height: 600)))
}

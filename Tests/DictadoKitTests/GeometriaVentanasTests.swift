import CoreGraphics
import Testing
@testable import DictadoKit

private typealias G = GeometriaVentanas

private let horizontal = PantallaAX(marco: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                    visible: CGRect(x: 0, y: 25, width: 1920, height: 1055))
private let vertical = PantallaAX(marco: CGRect(x: 0, y: 0, width: 1080, height: 1920),
                                  visible: CGRect(x: 0, y: 25, width: 1080, height: 1895))

@Test("Ciclo de lado: mitad, tercio, dos tercios", arguments: [(0, 0.5), (1, 1.0 / 3), (2, 2.0 / 3)])
func cicloLado(paso: Int, fraccion: Double) {
    let r = G.lado(izquierda: true, paso: paso, en: horizontal.visible)
    #expect(abs(r.width - horizontal.visible.width * fraccion) < 1)
    #expect(r.minX == horizontal.visible.minX)
}

@Test("El lado derecho termina en el borde derecho", arguments: [0, 1, 2])
func ladoDerecho(paso: Int) {
    let r = G.lado(izquierda: false, paso: paso, en: horizontal.visible)
    #expect(abs(r.maxX - horizontal.visible.maxX) < 1)
}

@Test("Una ventana se ubica en la pantalla que la contiene")
func indicePorPantalla() {
    let izq = PantallaAX(marco: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                         visible: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    let ps = [horizontal, izq]
    #expect(G.indice(de: CGRect(x: 100, y: 100, width: 400, height: 300), en: ps) == 0)
    #expect(G.indice(de: CGRect(x: -1500, y: 100, width: 400, height: 300), en: ps) == 1)
}

@Test("Pantalla vertical se detecta; horizontal no")
func orientacion() {
    #expect(G.vertical(vertical.visible))
    #expect(!G.vertical(horizontal.visible))
}

@Test("Casi maximizar deja margen y cabe en la pantalla")
func casiMaximizar() {
    let r = G.casiMaximizada(horizontal.visible)
    #expect(horizontal.visible.contains(r))
    #expect(r.width < horizontal.visible.width)
}

@Test("Sin memoria, restaurar no tiene nada que hacer")
func restaurarSinPrevio() {
    let actual = CGRect(x: 10, y: 40, width: 500, height: 400)
    #expect(G.plan(.restaurar, actual: actual, pantallas: [horizontal], memoria: nil) == nil)
}

@Test("Con una sola pantalla, otraPantalla no hace nada")
func unaSolaPantalla() {
    let actual = CGRect(x: 10, y: 40, width: 500, height: 400)
    #expect(G.plan(.otraPantalla, actual: actual, pantallas: [horizontal], memoria: nil) == nil)
}

@Test("Restaurar devuelve el marco previo tras acomodar")
func restaurarVuelveAlPrevio() throws {
    let antes = CGRect(x: 100, y: 100, width: 600, height: 500)
    let plan = try #require(G.plan(.izquierda, actual: antes, pantallas: [horizontal], memoria: nil))
    let mem = G.recordar(nil, accion: plan.registro, antes: antes, leido: plan.marco, paso: plan.paso)
    let vuelta = try #require(G.plan(.restaurar, actual: plan.marco, pantallas: [horizontal], memoria: mem))
    #expect(G.parecidos(vuelta.marco, antes))
}

@Test("Trasladar entre pantallas conserva las proporciones")
func trasladar() {
    let destino = CGRect(x: 1920, y: 0, width: 3840, height: 2160)
    let r = G.trasladada(CGRect(x: 0, y: 25, width: 960, height: 527), de: horizontal.visible, a: destino)
    #expect(abs(r.width / destino.width - 0.5) < 0.01)
}

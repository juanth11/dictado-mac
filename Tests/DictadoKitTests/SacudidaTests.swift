import CoreGraphics
import Testing
@testable import DictadoKit

/// Alimenta el detector con una lista de (x, y, t) y devuelve el instante del primer disparo, si lo hubo.
private func disparo(_ puntos: [(Double, Double, Double)], config: DetectorSacudida.Config = .init()) -> Double? {
    var d = DetectorSacudida(config: config)
    for (x, y, t) in puntos where d.alimentar(x: x, y: y, t: t) { return t }
    return nil
}

/// Vaivén horizontal: `trazos` recorridos de `largo` puntos, uno cada `cadaTrazo` segundos, muestreados a 120 Hz.
private func vaiven(trazos: Int, largo: Double, cadaTrazo: Double, inicioT: Double = 0, x0: Double = 500, y0: Double = 400,
                    sube: Double = 0) -> [(Double, Double, Double)] {
    var puntos: [(Double, Double, Double)] = []
    let pasos = max(Int(cadaTrazo * 120), 2)
    var x = x0, y = y0, t = inicioT
    puntos.append((x, y, t))
    for k in 0..<trazos {
        let signo: Double = k % 2 == 0 ? 1 : -1
        for _ in 0..<pasos {
            x += signo * largo / Double(pasos)
            y += sube / Double(pasos * trazos)
            t += cadaTrazo / Double(pasos)
            puntos.append((x, y, t))
        }
    }
    return puntos
}

@Test("Una sacudida rápida (5 trazos de 120 pt en 0,5 s) dispara")
func sacudidaDispara() {
    #expect(disparo(vaiven(trazos: 5, largo: 120, cadaTrazo: 0.1)) != nil)
}

@Test("Un solo vaivén no dispara")
func unVaiven() {
    #expect(disparo(vaiven(trazos: 2, largo: 300, cadaTrazo: 0.1)) == nil)
}

@Test("Tres cambios de dirección no bastan; cuatro sí")
func cuantosCambios() {
    #expect(disparo(vaiven(trazos: 4, largo: 120, cadaTrazo: 0.1)) == nil)   // 3 cambios
    #expect(disparo(vaiven(trazos: 5, largo: 120, cadaTrazo: 0.1)) != nil)   // 4 cambios
}

@Test("Un movimiento rápido en una sola dirección no dispara")
func movimientoRapido() {
    var puntos: [(Double, Double, Double)] = []
    for i in 0..<120 { puntos.append((Double(i) * 30, 400 + Double(i % 3), Double(i) / 240)) }  // 3600 pt en 0,5 s
    #expect(disparo(puntos) == nil)
}

@Test("Lento no dispara aunque cambie de dirección muchas veces")
func vaivenLento() {
    #expect(disparo(vaiven(trazos: 8, largo: 120, cadaTrazo: 0.4)) == nil)
}

@Test("Temblor pequeño (trazos de 15 pt) no dispara")
func temblor() {
    #expect(disparo(vaiven(trazos: 12, largo: 15, cadaTrazo: 0.05)) == nil)
}

@Test("Un arrastre de desplazamiento vertical con vaivén chico no dispara")
func desplazamientoVertical() {
    var puntos: [(Double, Double, Double)] = []
    for i in 0..<200 {  // sube y baja 300 pt a lo largo, con un bamboleo de 10 pt de lado
        let y = 400 + 300 * (i % 40 < 20 ? Double(i % 20) / 20 : 1 - Double(i % 20) / 20)
        puntos.append((500 + (i % 2 == 0 ? 5 : -5), y, Double(i) / 120))
    }
    #expect(disparo(puntos) == nil)
}

@Test("Una sacudida más vertical que horizontal no dispara")
func sacudidaVertical() {
    var puntos: [(Double, Double, Double)] = []
    for i in 0..<60 {  // zigzag con 70 pt de lado y 200 pt de alto por trazo
        let k = i / 10
        puntos.append((500 + (k % 2 == 0 ? Double(i % 10) * 7 : 70 - Double(i % 10) * 7), 400 + Double(i) * 20, Double(i) / 120))
    }
    #expect(disparo(puntos) == nil)
}

@Test("Dispara una vez y calla durante el enfriamiento")
func enfriamiento() {
    var d = DetectorSacudida()
    var disparos = 0
    for (x, y, t) in vaiven(trazos: 12, largo: 120, cadaTrazo: 0.1) where d.alimentar(x: x, y: y, t: t) { disparos += 1 }
    #expect(disparos == 1)   // 1,2 s de sacudida seguida: el segundo disparo cae dentro del segundo de silencio
}

@Test("Una pausa larga entre trazos reinicia la cuenta")
func pausa() {
    var puntos = vaiven(trazos: 3, largo: 120, cadaTrazo: 0.1)
    let t = puntos.last!.2 + 1.0
    puntos += vaiven(trazos: 3, largo: 120, cadaTrazo: 0.1, inicioT: t, x0: puntos.last!.0)
    #expect(disparo(puntos) == nil)
}

@Test("Más sensibilidad dispara con trazos más cortos")
func sensibilidad() {
    let corto = vaiven(trazos: 5, largo: 50, cadaTrazo: 0.1)
    #expect(disparo(corto, config: .sensibilidad(0)) == nil)
    #expect(disparo(corto, config: .sensibilidad(1)) != nil)
}

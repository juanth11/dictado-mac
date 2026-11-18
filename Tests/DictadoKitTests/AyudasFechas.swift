import Foundation
@testable import DictadoKit

// Sin `import Testing`: con las Command Line Tools, Foundation y Testing no pueden convivir en un mismo archivo.

/// Calendario fijo (gregoriano, zona dada) para que las pruebas no dependan del Mac que las corre.
func calendarioDePrueba(_ zona: String = "America/Bogota") -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zona) ?? .gmt
    return c
}

/// 2026-11-16 es lunes. `f(16, 9, 30)` = lunes 16 de noviembre de 2026, 9:30.
func f(_ dia: Int, _ hora: Int, _ minuto: Int = 0, zona: String = "America/Bogota") -> Date {
    let c = DateComponents(year: 2026, month: 11, day: dia, hour: hora, minute: minuto)
    return calendarioDePrueba(zona).date(from: c) ?? .distantPast
}
typealias Fecha = Date

/// Los bytes de un texto JSON (los tests no pueden importar Foundation junto con Testing).
func datosJSON(_ texto: String) -> Data { Data(texto.utf8) }

/// Cualquier fecha (en Bogotá).
func fe(_ año: Int, _ mes: Int, _ dia: Int, _ hora: Int = 0, _ minuto: Int = 0) -> Date {
    calendarioDePrueba().date(from: DateComponents(year: año, month: mes, day: dia, hour: hora, minute: minuto)) ?? .distantPast
}

/// Los festivos de un país como "2026-01-01" ordenados.
func clavesFestivos(_ pais: String, _ año: Int) -> [String] { Festivos.de(pais: pais, año: año).map(\.clave) }

// MARK: Audio sintético para probar la captura (clics en horas conocidas sobre ruido)

/// Un clic: ruido blanco con caída rápida (6 ms), que arranca en `inicio` segundos.
func clic(en x: inout [Float], inicio: Double, fuerza: Float, largo: Double = 0.05, tau: Double = 0.006, semilla: UInt64 = 1) {
    var azar = Azar(semilla: semilla)
    let tasa = SintesisTeclas.tasa
    let a = Int(inicio * tasa)
    let n = Int(largo * tasa)
    guard a >= 0, a + n < x.count else { return }
    for i in 0..<n { x[a + i] += fuerza * Float(exp(-Double(i) / tasa / tau) * azar.siguiente()) }
}

/// `segundos` de ruido de fondo (RMS ≈ `ruido`).
func fondoDeRuido(_ segundos: Double, ruido: Float = 0.003, semilla: UInt64 = 99) -> [Float] {
    var azar = Azar(semilla: semilla)
    return (0..<Int(segundos * SintesisTeclas.tasa)).map { _ in ruido * Float(azar.siguiente()) * 1.7 }
}

func abs32(_ x: Float) -> Float { Swift.abs(x) }

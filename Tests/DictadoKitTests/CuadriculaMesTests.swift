import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()

@Test("Cuadrícula: noviembre de 2026 (empieza en domingo) son 6 semanas de 7, desde el lunes 26 de octubre; solo 30 días son del mes")
func cuadriculaNoviembre2026() {
    let c = CuadriculaMes.armar(f(16, 9), ahora: f(16, 9), calendario: cal)
    #expect(c.mes == "Noviembre" && c.anio == 2026)
    #expect(c.semanas.count == 6 && c.semanas.allSatisfy { $0.count == 7 })
    #expect(c.semanas[0][0].numero == 26 && !c.semanas[0][0].delMes)
    #expect(c.semanas[0][6].numero == 1 && c.semanas[0][6].delMes)
    #expect(c.semanas.flatMap { $0 }.filter(\.delMes).count == 30)
    #expect(c.semanas.flatMap { $0 }.filter(\.delMes).map(\.numero) == Array(1...30))
}

@Test("Cuadrícula: hoy se marca una sola vez y solo dentro del mes")
func cuadriculaHoy() {
    let c = CuadriculaMes.armar(f(16, 9), ahora: f(16, 23, 59), calendario: cal)
    let hoy = c.semanas.flatMap { $0 }.filter(\.esHoy)
    #expect(hoy.map(\.numero) == [16] && hoy[0].delMes)
    // Mirando otro mes no hay hoy.
    let dic = CuadriculaMes.armar(fe(2026, 12, 3), ahora: f(16, 9), calendario: cal)
    #expect(dic.semanas.flatMap { $0 }.filter { $0.esHoy && $0.delMes }.isEmpty)
}

@Test("Cuadrícula: lunes primero y fines de semana en las columnas 6 y 7")
func cuadriculaFinesDeSemana() {
    let c = CuadriculaMes.armar(f(16, 9), ahora: f(16, 9), calendario: cal)
    for s in c.semanas {
        #expect(s.map(\.finDeSemana) == [false, false, false, false, false, true, true])
    }
    #expect(CuadriculaMes.iniciales == ["L", "M", "M", "J", "V", "S", "D"])
    #expect(c.semanas[2][0].numero == 9)   // el lunes 9
}

@Test("Cuadrícula: febrero de 2027 cabe en 4 semanas y febrero 2028 (bisiesto, 29 días) en 5")
func cuadriculaSemanasVariables() {
    let f27 = CuadriculaMes.armar(fe(2027, 2, 10), ahora: f(16, 9), calendario: cal)
    #expect(f27.semanas.count == 4 && f27.semanas.flatMap { $0 }.filter(\.delMes).count == 28)
    let f28 = CuadriculaMes.armar(fe(2028, 2, 10), ahora: f(16, 9), calendario: cal)
    #expect(f28.semanas.flatMap { $0 }.filter(\.delMes).count == 29 && f28.semanas.count == 5)
    #expect(CuadriculaMes.armar(fe(2026, 12, 1), ahora: f(16, 9), calendario: cal).mes == "Diciembre")
}

@Test("Cuadrícula: los días con eventos se marcan por día, sin importar la hora")
func cuadriculaEventos() {
    let marcados: Set = [f(18, 9), f(20, 23, 30)]
    let c = CuadriculaMes.armar(f(16, 9), diasConEventos: marcados, ahora: f(16, 9), calendario: cal)
    #expect(c.semanas.flatMap { $0 }.filter(\.conEventos).map(\.numero) == [18, 20])
}

@Test("Días de intervalos: uno corto cuenta su día; uno de varios días, todos; uno de todo el día que acaba a las 0:00 no invade el siguiente")
func diasDeIntervalos() {
    let inicio18 = cal.startOfDay(for: f(18, 12))
    let intervalos = [
        Intervalo(inicio: f(16, 10), fin: f(16, 11)),
        Intervalo(inicio: f(22, 20), fin: f(24, 8)),
        Intervalo(inicio: inicio18, fin: cal.startOfDay(for: f(19, 12))),
        Intervalo(inicio: f(27, 9), fin: f(27, 9)),
    ]
    let dias = CuadriculaMes.dias(de: intervalos, calendario: cal)
    let numeros = dias.map { cal.component(.day, from: $0) }.sorted()
    #expect(numeros == [16, 18, 22, 23, 24, 27])
}

@Test("Enlace de Calendario: calshow con los segundos desde 2001 de la medianoche del día")
func enlaceCalshow() {
    let u = CuadriculaMes.enlaceCalendario(f(16, 15), calendario: cal)
    let esperado = Int(cal.startOfDay(for: f(16, 3)).timeIntervalSinceReferenceDate)
    #expect(u?.absoluteString == "calshow:\(esperado)")
}

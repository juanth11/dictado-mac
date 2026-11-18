import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
private func i(_ d1: Int, _ h1: Int, _ m1: Int = 0, _ d2: Int, _ h2: Int, _ m2: Int = 0) -> Intervalo {
    Intervalo(inicio: f(d1, h1, m1), fin: f(d2, h2, m2))
}
private func libres(_ ocupados: [Intervalo], desde: Fecha, _ config: ConfigHuecos = .porOmision) -> [Intervalo] {
    Huecos.libres(ocupados: ocupados, desde: desde, config: config, calendario: cal)
}

@Test("Unir: encimados y pegados se funden; los vacíos se descartan")
func unirTramos() {
    let r = Huecos.unir([i(16, 10, 0, 16, 11, 0), i(16, 9, 0, 16, 10, 0), i(16, 10, 30, 16, 12, 0), i(16, 14, 0, 16, 14, 0)])
    #expect(r == [i(16, 9, 0, 16, 12, 0)])
}

@Test("Un día vacío es un solo hueco de 8:00 a 18:00")
func diaVacio() {
    let r = libres([], desde: f(16, 6), ConfigHuecos(diasHorizonte: 1))
    #expect(r == [i(16, 8, 0, 16, 18, 0)])
}

@Test("Una reunión parte el día en dos huecos")
func reunionParteElDia() {
    let r = libres([i(16, 10, 0, 16, 11, 0)], desde: f(16, 6), ConfigHuecos(diasHorizonte: 1))
    #expect(r == [i(16, 8, 0, 16, 10, 0), i(16, 11, 0, 16, 18, 0)])
}

@Test("Los eventos encimados cuentan una sola vez")
func encimados() {
    let r = libres([i(16, 9, 0, 16, 12, 0), i(16, 10, 0, 16, 11, 0), i(16, 11, 30, 16, 13, 0)], desde: f(16, 6), ConfigHuecos(diasHorizonte: 1))
    #expect(r == [i(16, 8, 0, 16, 9, 0), i(16, 13, 0, 16, 18, 0)])
}

@Test("Los huecos más cortos que el mínimo se descartan")
func minimo() {
    let r = libres([i(16, 8, 0, 16, 9, 0), i(16, 9, 20, 16, 17, 0)], desde: f(16, 6), ConfigHuecos(diasHorizonte: 1))
    #expect(r == [i(16, 17, 0, 16, 18, 0)])  // los 20 min de 9:00 a 9:20 no llegan a 30
}

@Test("Ahora corta el día y se redondea a 15 minutos hacia arriba")
func fronteraAhora() {
    let r = libres([i(16, 15, 0, 16, 16, 0)], desde: f(16, 10, 7), ConfigHuecos(diasHorizonte: 1))
    #expect(r == [i(16, 10, 15, 16, 15, 0), i(16, 16, 0, 16, 18, 0)])
}

@Test("Si ya pasó el horario, hoy no cuenta y se sigue con el siguiente día laboral")
func despuesDeHorario() {
    let r = libres([], desde: f(16, 19), ConfigHuecos(diasHorizonte: 1))
    #expect(r == [i(17, 8, 0, 17, 18, 0)])
}

@Test("Quedan menos de 30 minutos de hoy: no hay hueco hoy")
func pocoTiempoHoy() {
    let r = libres([], desde: f(16, 17, 40), ConfigHuecos(diasHorizonte: 1))
    #expect(r.isEmpty)
}

@Test("Un evento que cruza la medianoche tapa el comienzo del día siguiente")
func cruzaMedianoche() {
    let r = libres([i(16, 22, 0, 17, 9, 30)], desde: f(16, 6), ConfigHuecos(diasHorizonte: 2))
    #expect(r == [i(16, 8, 0, 16, 18, 0), i(17, 9, 30, 17, 18, 0)])
}

@Test("Fines de semana fuera: el horizonte cuenta solo días laborales")
func soloLaborales() {
    // viernes 20 → luego lunes 23 (el sábado y el domingo no cuentan)
    let r = libres([], desde: f(20, 6), ConfigHuecos(diasHorizonte: 2))
    #expect(r == [i(20, 8, 0, 20, 18, 0), i(23, 8, 0, 23, 18, 0)])
}

@Test("Un sábado de arranque no cuenta como día laboral")
func arrancaSabado() {
    let r = libres([], desde: f(21, 10), ConfigHuecos(diasHorizonte: 1))
    #expect(r == [i(23, 8, 0, 23, 18, 0)])
}

@Test("El horizonte por omisión son 5 días laborales")
func cincoDias() {
    let r = libres([], desde: f(16, 6))
    #expect(r.count == 5)
    #expect(r.last == i(20, 8, 0, 20, 18, 0))
}

@Test("Horario y mínimo configurables")
func configurable() {
    let c = ConfigHuecos(inicioMin: 9 * 60, finMin: 13 * 60, minimoMin: 60, diasHorizonte: 1)
    let r = libres([i(16, 9, 30, 16, 10, 0), i(16, 11, 45, 16, 12, 0)], desde: f(16, 6), c)
    #expect(r == [i(16, 10, 0, 16, 11, 45), i(16, 12, 0, 16, 13, 0)])
}

@Test("Una configuración imposible no devuelve nada ni se cuelga")
func configImposible() {
    #expect(libres([], desde: f(16, 6), ConfigHuecos(inicioMin: 600, finMin: 600)).isEmpty)
    #expect(libres([], desde: f(16, 6), ConfigHuecos(dias: [])).isEmpty)
}

// MARK: Texto

@Test("Hora en 12 horas con a. m. y p. m.", arguments: [(8, 0, "8:00", "a. m."), (12, 5, "12:05", "p. m."), (0, 30, "12:30", "a. m."), (15, 0, "3:00", "p. m.")])
func horas(h: Int, m: Int, texto: String, periodo: String) {
    let r = FormatoHuecos.hora(f(17, h, m), calendario: cal)
    #expect(r.texto == texto)
    #expect(r.periodo == periodo)
}

@Test("Rango corto, con y sin cambio de periodo")
func rangos() {
    #expect(FormatoHuecos.rango(i(17, 15, 0, 17, 16, 30), calendario: cal) == "3:00-4:30 p. m.")
    #expect(FormatoHuecos.rango(i(17, 11, 0, 17, 13, 0), calendario: cal) == "11:00 a. m.-1:00 p. m.")
    #expect(FormatoHuecos.corto(i(17, 15, 0, 17, 16, 30), ahora: f(16, 9), calendario: cal) == "mar 3:00-4:30 p. m.")
    #expect(FormatoHuecos.corto(i(16, 15, 0, 16, 16, 30), ahora: f(16, 9), calendario: cal) == "hoy 3:00-4:30 p. m.")
}

@Test("El texto de disponibilidad queda listo para pegar")
func textoDisponibilidad() {
    let t = FormatoHuecos.disponibilidad([i(17, 15, 0, 17, 16, 30), i(18, 9, 0, 18, 11, 0), i(19, 11, 0, 19, 13, 0)], calendario: cal)
    #expect(t == "Tengo disponibilidad: martes 17 de 3:00 a 4:30 p. m.; miércoles 18 de 9:00 a 11:00 a. m.; jueves 19 de 11:00 a. m. a 1:00 p. m.")
}

@Test("La disponibilidad se limita a cinco huecos y avisa si no hay ninguno")
func limiteDisponibilidad() {
    let muchos = (16...22).map { i($0, 9, 0, $0, 10, 0) }
    let t = FormatoHuecos.disponibilidad(muchos, calendario: cal)
    #expect(t.split(separator: ";").count == 5)
    #expect(FormatoHuecos.disponibilidad([], calendario: cal).hasPrefix("No tengo disponibilidad"))
}

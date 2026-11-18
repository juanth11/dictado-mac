import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
private func oc(_ d1: Int, _ h1: Int, _ m1: Int = 0, _ d2: Int, _ h2: Int, _ m2: Int = 0) -> Intervalo {
    Intervalo(inicio: f(d1, h1, m1), fin: f(d2, h2, m2))
}

@Test("Mes: noviembre de 2026 empieza el domingo 1, así que la cuadrícula arranca el lunes 26 de octubre y tiene 6 semanas (la última, 30 de noviembre al 6 de diciembre)")
func cuadriculaNoviembre() {
    let v = MesCalendario.armar(mes: f(16, 9), eventos: [], ahora: f(16, 9), calendario: cal)
    #expect(v.titulo == "noviembre 2026")
    #expect(v.semanas.count == 6)
    #expect(v.semanas.allSatisfy { $0.count == 7 })
    let primero = v.semanas[0][0]
    #expect(primero.numero == 26 && !primero.delMes)
    #expect(v.semanas[0][6].numero == 1 && v.semanas[0][6].delMes)   // el domingo 1
    #expect(v.semanas[5][0].numero == 30 && v.semanas[5][0].delMes)
    #expect(v.semanas[5][6].numero == 6 && !v.semanas[5][6].delMes)
    #expect(v.semanas.flatMap { $0 }.filter(\.esHoy).map(\.numero) == [16])
}

@Test("Mes: febrero de 2027 empieza en lunes y cabe en cuatro semanas")
func febrero2027() {
    let v = MesCalendario.armar(mes: fe(2027, 2, 10), eventos: [], ahora: fe(2027, 2, 10), calendario: cal)
    #expect(v.semanas.count == 4)
    #expect(v.semanas[0][0].numero == 1 && v.semanas[0][0].delMes)
}

@Test("Mes: la ocupación de un día se mide dentro del horario laboral (8 a 18) y se encima una sola vez")
func densidad() {
    let v = MesCalendario.armar(mes: f(16, 9), eventos: [oc(16, 9, 0, 16, 12, 0), oc(16, 10, 0, 16, 11, 0), oc(16, 17, 0, 16, 20, 0)], ahora: f(16, 9), calendario: cal)
    let d = v.semanas.flatMap { $0 }.first { $0.numero == 16 && $0.delMes }!
    #expect(d.eventos == 3)
    #expect(d.minutosOcupados == 240)         // 3 h de 9 a 12 + 1 h de 17 a 18
    #expect(abs(d.densidad - 0.4) < 1e-9)     // 240 de 600
}

@Test("Mes: los festivos marcan su celda y el fin de semana se reconoce")
func festivosYFines() {
    let festivos = DiasFestivos.entre(f(1, 0), f(30, 0), pais: "CO", calendario: cal)
    let v = MesCalendario.armar(mes: f(16, 9), eventos: [], festivos: festivos, ahora: f(16, 9), calendario: cal)
    let dias = v.semanas.flatMap { $0 }
    #expect(dias.first { $0.numero == 16 && $0.delMes }?.festivo == "Independencia de Cartagena")
    #expect(dias.first { $0.numero == 2 && $0.delMes }?.festivo == "Todos los Santos")
    #expect(dias.first { $0.numero == 17 && $0.delMes }?.festivo == nil)
    #expect(dias.first { $0.numero == 14 && $0.delMes }?.finDeSemana == true)
    #expect(dias.first { $0.numero == 13 && $0.delMes }?.finDeSemana == false)
}

@Test("Mes: desplazar y la ventana que se pide a Calendario")
func ventanaYDesplazar() {
    let nov = MesCalendario.primero(de: f(16, 9), calendario: cal)
    #expect(nov == fe(2026, 11, 1))
    #expect(MesCalendario.desplazar(nov, por: 1, calendario: cal) == fe(2026, 12, 1))
    #expect(MesCalendario.desplazar(nov, por: -2, calendario: cal) == fe(2026, 9, 1))
    #expect(MesCalendario.desplazar(fe(2026, 12, 1), por: 1, calendario: cal) == fe(2027, 1, 1))
    let v = MesCalendario.ventana(de: nov, calendario: cal)
    #expect(v.start == fe(2026, 10, 26))
    #expect(v.end == fe(2026, 12, 7))
}

@Test("Huecos de un día: libres entre reuniones; un festivo no tiene huecos")
func huecosDelDia() {
    let ocupados = [oc(17, 10, 0, 17, 11, 0)]
    let r = MesCalendario.huecosDelDia(f(17, 12), ocupados: ocupados, calendario: cal)
    #expect(r == [Intervalo(inicio: f(17, 8), fin: f(17, 10)), Intervalo(inicio: f(17, 11), fin: f(17, 18))])
    let festivo: Set<Fecha> = [cal.startOfDay(for: f(17, 12))]
    #expect(MesCalendario.huecosDelDia(f(17, 12), ocupados: ocupados, festivos: festivo, calendario: cal).isEmpty)
    // Un sábado no está en el horario laboral: sin huecos.
    #expect(MesCalendario.huecosDelDia(f(21, 12), ocupados: [], calendario: cal).isEmpty)
}

@Test("Huecos: un festivo se salta y no cuenta como día del horizonte")
func festivoEnHuecos() {
    let festivo: Set<Fecha> = [cal.startOfDay(for: f(17, 0))]
    let r = Huecos.libres(ocupados: [], desde: f(16, 6), config: ConfigHuecos(diasHorizonte: 3), excluyendo: festivo, calendario: cal)
    // lunes 16, (martes 17 fuera), miércoles 18 y jueves 19
    #expect(r.map(\.inicio) == [f(16, 8), f(18, 8), f(19, 8)])
    let sin = Huecos.libres(ocupados: [], desde: f(16, 6), config: ConfigHuecos(diasHorizonte: 3), calendario: cal)
    #expect(sin.map(\.inicio) == [f(16, 8), f(17, 8), f(18, 8)])
}

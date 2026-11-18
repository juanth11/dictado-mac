import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()

@Test("Partes de la fecha: domingo 15 de noviembre de 2026")
func lanz_partesFecha() {
    let p = PartesFecha(f(15, 9), calendario: cal)
    #expect(p.diaSemana == "Dom")
    #expect(p.mes == "Nov")
    #expect(p.dia == 15)
    #expect(PartesFecha(f(16, 9), calendario: cal).diaSemana == "Lun")
}

@Test("Mes en puntos: 30 puntos, 15 pasados con hoy, 15 restantes")
func lanz_mesEnPuntos() {
    let m = MesEnPuntos(f(15, 9), calendario: cal)
    #expect(m.dias == 30)
    #expect(m.pasados.count == 30)
    #expect(m.pasados.filter { $0 }.count == 15)
    #expect(m.pasados[14] && !m.pasados[15])
    #expect(m.restantes == 15)
    #expect(m.rotulo == "NOVIEMBRE · 15 DÍAS")
}

@Test("Mes en puntos: primer día, penúltimo y último")
func lanz_mesBordes() {
    #expect(MesEnPuntos(f(1, 8), calendario: cal).pasados.filter { $0 }.count == 1)
    #expect(MesEnPuntos(f(29, 8), calendario: cal).rotulo == "NOVIEMBRE · 1 DÍA")
    #expect(MesEnPuntos(f(30, 8), calendario: cal).rotulo == "NOVIEMBRE · ÚLTIMO DÍA")
    #expect(MesEnPuntos(f(30, 8), calendario: cal).pasados.allSatisfy { $0 })
}

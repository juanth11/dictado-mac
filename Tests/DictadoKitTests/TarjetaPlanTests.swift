import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
private let ahora = f(18, 8)   // miércoles 18

private func plan(hoy: [ItemPlan] = [], semana: [ItemPlan] = []) -> PlanPendientes { PlanPendientes(hoy: hoy, semana: semana) }

@Test("Tarjeta del plan: solo los recordatorios con identificador tienen casilla; tareas y metas son de solo lectura")
func tarjetaCasillas() {
    let t = TarjetaPlan.armar(plan(hoy: [ItemPlan(texto: "Llamar a Carla", origen: .recordatorio, delDia: true, id: "R1"),
                                         ItemPlan(texto: "Enviar el poder", origen: .tarea, delDia: true),
                                         ItemPlan(texto: "Sin id", origen: .recordatorio, delDia: true)],
                                    semana: [ItemPlan(texto: "Cerrar la base", origen: .meta)]), ahora: ahora, calendario: cal)
    #expect(t.hoy.filas.map(\.puedeMarcar) == [true, false, false])
    #expect(t.hoy.filas.first?.idFuente == "R1")
    #expect(t.semana.filas.first?.puedeMarcar == false)
    #expect(t.hoy.filas.map(\.etiqueta) == ["Recordatorio", "Tarea", "Recordatorio"])
    #expect(t.semana.filas.first?.etiqueta == "Meta")
}

@Test("Tarjeta del plan: lo vencido, la hora de hoy y el día de la semana")
func tarjetaCuando() {
    let t = TarjetaPlan.armar(plan(hoy: [ItemPlan(texto: "Vieja", vence: f(16, 9), origen: .tarea),
                                         ItemPlan(texto: "Tarde", vence: f(18, 15, 30), origen: .recordatorio, id: "A"),
                                         ItemPlan(texto: "Sin hora", vence: f(18, 0), origen: .recordatorio, id: "B")],
                                    semana: [ItemPlan(texto: "Jueves", vence: f(19, 9, 5), origen: .recordatorio, id: "C"),
                                             ItemPlan(texto: "Domingo", vence: f(22, 0), origen: .hito)]), ahora: ahora, calendario: cal)
    #expect(t.hoy.filas.map(\.cuando) == ["Vencida", "3:30 p. m.", nil])
    #expect(t.hoy.filas.first?.vencida == true)
    #expect(t.hoy.filas[1].vencida == false)
    #expect(t.semana.filas.map(\.cuando) == ["jue 9:05 a. m.", "dom"])
    #expect(TarjetaPlan.horaTexto(f(18, 12, 0), cal) == "12:00 p. m.")
    #expect(TarjetaPlan.horaTexto(f(18, 0, 7), cal) == "12:07 a. m.")
}

@Test("Tarjeta del plan: lo que no cabe se cuenta como «ocultas» y las marcadas se tachan sin contar como pendientes")
func tarjetaTopeYHechas() {
    let items = (1...6).map { ItemPlan(texto: "Cosa \($0)", origen: .recordatorio, delDia: true, id: "R\($0)") }
    let t = TarjetaPlan.armar(plan(hoy: items), ahora: ahora, maxHoy: 4, calendario: cal)
    #expect(t.hoy.filas.count == 4)
    #expect(t.hoy.ocultas == 2)
    #expect(t.hoy.pendientes == 6)
    let h = TarjetaPlan.armar(plan(hoy: items), hechas: ["id:R1"], ahora: ahora, maxHoy: 4, calendario: cal)
    #expect(h.hoy.pendientes == 5)
    #expect(h.hoy.ocultas == 1)
    #expect(h.hoy.filas.map(\.texto) == ["Cosa 2", "Cosa 3", "Cosa 4", "Cosa 5"])   // sin hueco para la tachada
    let pocas = TarjetaPlan.armar(plan(hoy: Array(items.prefix(2))), hechas: ["id:R1"], ahora: ahora, maxHoy: 4, calendario: cal)
    #expect(pocas.hoy.filas.map(\.texto) == ["Cosa 2", "Cosa 1"])   // la marcada va al final
    #expect(pocas.hoy.filas.last?.hecha == true)
}

@Test("Tarjeta del plan: vacío cuando no hay nada")
func tarjetaVacia() {
    #expect(TarjetaPlan.armar(.vacio, ahora: ahora, calendario: cal).vacio)
    #expect(!TarjetaPlan.armar(plan(semana: [ItemPlan(texto: "Algo", origen: .meta)]), ahora: ahora, calendario: cal).vacio)
}

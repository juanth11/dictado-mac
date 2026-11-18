import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
private func reunion(_ id: String, _ d: Int, _ h: Int, _ m: Int = 0, dur: Int = 60, con: String? = nil, titulo: String = "Comité", ocupado: Bool = true) -> ReunionBreve {
    ReunionBreve(id: id, titulo: titulo, inicio: f(d, h, m), fin: f(d, h + dur / 60, m + dur % 60), invitado: con, personas: con == nil ? 0 : 3, ocupado: ocupado)
}

@Test("Armar: une tramos del mismo tono y alterna dato y enlace")
func lanz_armarAlterna() {
    let s = Frase.armar([("3", .dato), ("trabajando", .enlace), ("·", .enlace), ("2", .acento), ("esperan tu sí", .enlace)])
    #expect(s.map(\.tono) == [.dato, .enlace, .acento, .enlace])
    #expect(Frase.texto(s) == "3 trabajando · 2 esperan tu sí")
}

@Test("Armar: un salto de línea separa dato y enlace sin dejar espacios pegados")
func lanz_armarSalto() {
    let s = Frase.armar([("3", .dato), ("trabajando", .enlace), ("\n", .enlace), ("2", .acento), ("esperan", .enlace), ("\n", .enlace)])
    #expect(Frase.texto(s) == "3 trabajando\n2 esperan")
    #expect(Frase.armar([("\n", .enlace), ("a", .dato)]).count == 1)
    #expect(Frase.texto(Frase.armar([("a", .enlace), ("\n", .enlace), ("b", .enlace)])) == "a\nb")
}

@Test("Armar: descarta lo vacío y pega la puntuación")
func lanz_armarPuntuacion() {
    let s = Frase.armar([("  ", .dato), ("Hola", .dato), (",", .enlace), ("mundo", .dato), ("", .enlace)])
    #expect(Frase.texto(s) == "Hola, mundo")
    #expect(Frase.armar([]).isEmpty)
}

@Test("Hora en doce horas, sin am/pm")
func lanz_horaDoce() {
    #expect(Frase.hora(f(15, 15, 0), calendario: cal) == "3:00")
    #expect(Frase.hora(f(15, 0, 5), calendario: cal) == "12:05")
    #expect(Frase.hora(f(15, 12, 30), calendario: cal) == "12:30")
}

@Test("Agenda: la próxima de hoy con libre hasta entonces")
func lanz_agendaProxima() {
    let r = FrasesLanzador.agenda([reunion("a", 16, 15, con: "Lucía"), reunion("b", 16, 17, 30, titulo: "Cliente")], ahora: f(16, 9, 5), calendario: cal)
    #expect(Frase.texto(r.frase) == "3:00 con Lucía\nlibre hasta entonces")
    #expect(r.frase.first?.tono == .dato)
    #expect(r.proximas.map(\.id) == ["a", "b"])
}

@Test("Agenda: sin invitado sale el título")
func lanz_agendaTitulo() {
    let r = FrasesLanzador.agenda([reunion("a", 16, 15)], ahora: f(16, 9, 0), calendario: cal)
    #expect(Frase.texto(r.frase) == "3:00 Comité\nlibre hasta entonces")
}

@Test("Agenda: reunión en curso")
func lanz_agendaEnCurso() {
    let r = FrasesLanzador.agenda([reunion("a", 16, 9), reunion("b", 16, 11)], ahora: f(16, 9, 20), calendario: cal)
    #expect(Frase.texto(r.frase) == "Comité hasta 10:00")
    #expect(r.proximas.count == 2)
}

@Test("Agenda: lo que ya terminó no cuenta y solo salen dos")
func lanz_agendaDosMaximo() {
    let r = FrasesLanzador.agenda([reunion("v", 16, 8), reunion("a", 16, 14), reunion("b", 16, 15), reunion("c", 16, 16)], ahora: f(16, 12), calendario: cal)
    #expect(r.proximas.map(\.id) == ["a", "b"])
}

@Test("Agenda: la próxima es mañana")
func lanz_agendaManana() {
    let r = FrasesLanzador.agenda([reunion("a", 17, 9, con: "Lucía")], ahora: f(16, 9, 0), calendario: cal)
    #expect(Frase.texto(r.frase) == "Mañana 9:00 con Lucía\nhoy libre")
}

@Test("Agenda: otro día usa el día de la semana; de noche no promete libre")
func lanz_agendaOtroDia() {
    let r = FrasesLanzador.agenda([reunion("a", 19, 10)], ahora: f(16, 20, 0), calendario: cal)
    #expect(Frase.texto(r.frase) == "Jue 10:00 Comité")
}

@Test("Agenda: sin reuniones")
func lanz_agendaVacia() {
    let r = FrasesLanzador.agenda([], ahora: f(16, 9), calendario: cal)
    #expect(Frase.texto(r.frase) == "Agenda libre")
    #expect(r.proximas.isEmpty)
}

@Test("Agenda: un evento marcado como libre no corta el hueco")
func lanz_agendaLibreNoBloquea() {
    let r = FrasesLanzador.agenda([reunion("a", 16, 11, ocupado: false), reunion("b", 16, 15)], ahora: f(16, 9), calendario: cal)
    #expect(Frase.texto(r.frase) == "11:00 Comité")
}

@Test("Agentes: trabajando y esperan")
func lanz_agentesFrases() {
    #expect(Frase.texto(FrasesLanzador.agentes(trabajando: 3, esperan: 2, sesiones: 5)) == "3 trabajando\n2 esperan tu sí")
    let s = FrasesLanzador.agentes(trabajando: 3, esperan: 2, sesiones: 5)
    #expect(s.contains(SegmentoFrase("2", .acento)))
    #expect(Frase.texto(FrasesLanzador.agentes(trabajando: 0, esperan: 1, sesiones: 1)) == "1 espera tu sí")
    #expect(Frase.texto(FrasesLanzador.agentes(trabajando: 2, esperan: 0, sesiones: 2)) == "2 trabajando\nnadie espera tu sí")
    #expect(Frase.texto(FrasesLanzador.agentes(trabajando: 0, esperan: 0, sesiones: 2)) == "Todo en calma")
    #expect(Frase.texto(FrasesLanzador.agentes(trabajando: 0, esperan: 0, sesiones: 0)) == "Sin sesiones abiertas")
}

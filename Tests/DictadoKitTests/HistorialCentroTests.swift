import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
/// Lunes 16 de noviembre de 2026, 3:00 p. m.
private let ahora = f(16, 15)

private func corrida(_ id: Int, _ estado: CorridaTablero.Estado, inicio: Fecha?, fin: Fecha? = nil, tokens: Int? = nil, costo: Double? = nil) -> CorridaTablero {
    CorridaTablero(id: id, titulo: "Corrida \(id)", inicio: inicio, fin: fin, estado: estado, tokensEntrada: tokens, tokensSalida: tokens == nil ? nil : 0, costoUSD: costo)
}

private let ejemplo: [CorridaTablero] = [
    corrida(1, .termino, inicio: f(16, 8), fin: f(16, 10), tokens: 1_000_000, costo: 2.5),          // hoy, 2 h
    corrida(2, .fallo, inicio: f(16, 11), fin: f(16, 11, 30), tokens: 500, costo: 0.25),            // hoy, 30 min
    corrida(3, .trabajando, inicio: f(16, 14), tokens: 300, costo: nil),                             // en marcha: 1 h hoy
    corrida(4, .termino, inicio: f(15, 20), fin: f(16, 1), costo: 4),                                // terminó hoy a la 1 a. m.
    corrida(5, .termino, inicio: f(15, 9), fin: f(15, 12), tokens: 2_000, costo: 10),                // ayer, 3 h
    corrida(6, .termino, inicio: f(11, 9), fin: f(11, 10), costo: 100),                              // hace 5 días
    corrida(7, .termino, inicio: f(8, 9), fin: f(8, 10), costo: 1000),                               // hace 8 días: fuera
    corrida(8, .termino, inicio: nil, fin: nil),                                                     // sin fechas: se salta
]

@Test("Historial: siete días, hoy primero, con su etiqueta")
func historialDias() {
    let dias = HistorialCentro.dias(ejemplo, ahora: ahora, calendario: cal)
    #expect(dias.count == 7)
    #expect(dias.map(\.etiqueta) == ["Hoy", "Ayer", "sáb 14", "vie 13", "jue 12", "mié 11", "mar 10"])
    #expect(dias[0].fecha == "16 nov" && dias[0].esHoy && !dias[1].esHoy)
}

@Test("Historial: las corridas van al día en que terminaron y la en marcha cuenta hoy")
func historialAtribucion() {
    let dias = HistorialCentro.dias(ejemplo, ahora: ahora, calendario: cal)
    #expect(dias[0].corridas.map(\.id) == [3, 2, 1, 4])   // la más reciente primero (la en marcha, por su inicio)
    #expect(dias[0].terminaron == 2 && dias[0].fallaron == 1 && dias[0].enMarcha == 1)
    #expect(dias[1].corridas.map(\.id) == [5])
    #expect(dias[5].corridas.map(\.id) == [6])
    #expect(dias.flatMap(\.corridas).contains { $0.id == 7 } == false)   // hace 8 días
    #expect(dias.flatMap(\.corridas).contains { $0.id == 8 } == false)   // sin fecha
}

@Test("Historial: horas, tokens y costo del día; null cuando ninguna corrida lo trae")
func historialTotales() {
    let dias = HistorialCentro.dias(ejemplo, ahora: ahora, calendario: cal)
    // 2 h + 30 min + 1 h (la en marcha, desde las 2 p. m.) + 5 h (4: de las 8 p. m. a la 1 a. m.)
    #expect(dias[0].segundos == (2 + 0.5 + 1 + 5) * 3600)
    #expect(dias[0].tokens == 1_000_500 + 300)
    #expect(dias[0].costoUSD == 2.5 + 0.25 + 4)
    #expect(dias[2].tokens == nil && dias[2].costoUSD == nil && dias[2].corridas.isEmpty && dias[2].segundos == 0)
    #expect(dias[1].tokens == 2_000 && dias[1].costoUSD == 10)
}

@Test("Historial: la en marcha solo cuenta lo de hoy aunque haya empezado ayer")
func historialEnMarchaDeAyer() {
    let c = corrida(9, .trabajando, inicio: f(15, 20))
    let dias = HistorialCentro.dias([c], ahora: ahora, calendario: cal)
    #expect(dias[0].segundos == 15 * 3600)   // de la medianoche a las 3 p. m.
    #expect(dias[0].corridas.map(\.id) == [9])
}

@Test("Historial: la barra mide cada corrida contra el día más cargado")
func historialBarra() {
    let dias = HistorialCentro.dias(ejemplo, ahora: ahora, calendario: cal)
    let total = dias[0].barra.map(\.fraccion).reduce(0, +)
    #expect(abs(total - 1) < 1e-9)   // hoy es el día más cargado
    #expect(dias[0].barra.count == 4 && dias[0].barra.first?.corridaID == 4)   // de la más antigua a la más reciente
    #expect(dias[1].barra.map(\.fraccion).reduce(0, +) < 1)
    #expect(dias[2].barra.isEmpty)
}

@Test("Cifras de hoy: sesiones, horas, tokens, costo de hoy y de la semana")
func cifrasHoy() {
    let c = HistorialCentro.cifras(ejemplo, ahora: ahora, calendario: cal)
    #expect(c.sesiones == 4)
    #expect(c.segundos == 8.5 * 3600)
    #expect(c.tokens == 1_000_800)
    #expect(c.costoHoy == 6.75)
    #expect(c.costoSemana == 6.75 + 10 + 100)   // la de hace 8 días no entra
}

@Test("Cifras de hoy: sin historial todo es nil; sin costos conocidos, el costo es nil")
func cifrasNulas() {
    #expect(HistorialCentro.cifras(nil, ahora: ahora, calendario: cal) == CifrasHoy())
    let sinCosto = [corrida(1, .termino, inicio: f(16, 8), fin: f(16, 9))]
    let c = HistorialCentro.cifras(sinCosto, ahora: ahora, calendario: cal)
    #expect(c.sesiones == 1 && c.segundos == 3600)
    #expect(c.tokens == nil && c.costoHoy == nil && c.costoSemana == nil)
    let vacio = HistorialCentro.cifras([], ahora: ahora, calendario: cal)
    #expect(vacio.sesiones == 0 && vacio.tokens == nil && vacio.costoSemana == nil)
}

@Test("Lo que terminó desde anoche: hoy y ayer después de las 6 p. m., sin repetir ni lo que sigue en marcha")
func terminadasDesdeAnoche() {
    let t = Tablero(enCurso: [corrida(3, .trabajando, inicio: f(16, 14))],
                    ultimas: [corrida(1, .termino, inicio: f(16, 8), fin: f(16, 10)), corrida(3, .termino, inicio: f(16, 1), fin: f(16, 2))])
    let historial = [corrida(1, .termino, inicio: f(16, 8), fin: f(16, 10)),     // repetida
                     corrida(2, .fallo, inicio: f(16, 11), fin: f(16, 12)),
                     corrida(4, .termino, inicio: f(15, 19), fin: f(15, 19, 30)), // anoche, después de las 6
                     corrida(5, .termino, inicio: f(15, 9), fin: f(15, 17, 59))]  // antes de las 6 p. m. de ayer
    let r = HistorialCentro.terminadasDesdeAnoche(tablero: t, historial: historial, ahora: ahora, calendario: cal)
    #expect(r.map(\.id) == [2, 1, 4])
    #expect(HistorialCentro.terminadasDesdeAnoche(tablero: nil, historial: nil, ahora: ahora, calendario: cal).isEmpty)
    #expect(HistorialCentro.terminadasDesdeAnoche(tablero: t, historial: historial, ahora: ahora, calendario: cal, limite: 1).map(\.id) == [2])
}

@Test("Formato de la tira: horas, tokens y costo en número y unidad")
func formatoTira() {
    #expect(HistorialCentro.horas(42 * 60) == ("42", "min"))
    #expect(HistorialCentro.horas(3.4 * 3600) == ("3,4", "h"))
    #expect(HistorialCentro.horas(12 * 3600) == ("12", "h"))
    #expect(HistorialCentro.horas(0) == ("0", "min"))
    #expect(HistorialCentro.tokens(812) == ("812", "tokens"))
    #expect(HistorialCentro.tokens(340_000) == ("340", "k tokens"))
    #expect(HistorialCentro.tokens(1_200_000) == ("1,2", "M tokens"))
    #expect(HistorialCentro.tokens(103_500_000) == ("104", "M tokens"))
    #expect(HistorialCentro.costo(20.0077) == ("20,01", "US$"))
    #expect(HistorialCentro.costo(1234.5) == ("1.234,50", "US$"))
    #expect(HistorialCentro.costo(0.001) == ("<0,01", "US$"))
    #expect(HistorialCentro.costo(0) == ("0,00", "US$"))
}

@Test("Corridas del historial: una lista; un rechazo o texto suelto no lo es; una fila mala se salta")
func decodificarCorridas() {
    let lista = datosJSON("""
    [{"id": 1, "titulo": "A", "estado": "termino", "inicio": "2026-11-16T08:00:00-05:00", "fin": "2026-11-16T10:00:00-05:00", "costo_usd": 1.5, "tokens_entrada": 10, "tokens_salida": 5},
     {"id": 2, "titulo": ""}, {"titulo": "sin id"}, {"id": 3, "titulo": "C", "estado": "raro", "campo_nuevo": 1}]
    """)
    let r = TableroCentro.decodificarCorridas(lista)
    #expect(r?.map(\.id) == [1, 3])
    #expect(r?.first?.tokens == 15 && r?.first?.costoUSD == 1.5)
    #expect(TableroCentro.decodificarCorridas(datosJSON("[]")) == [])
    #expect(TableroCentro.decodificarCorridas(datosJSON("{\"ok\": false, \"error\": \"x\"}")) == nil)
    #expect(TableroCentro.decodificarCorridas(datosJSON("no es json")) == nil)
    #expect(TableroCentro.decodificarCorridas(datosJSON("")) == nil)
}

@Test("Frase del encabezado: lo que es cero no se dice y el singular se respeta")
func fraseEstado() {
    #expect(FraseCentro.estado(trabajando: 3, esperan: 2, tareasHoy: 5) == "3 trabajando · 2 esperan tu sí · 5 tareas hoy")
    #expect(FraseCentro.estado(trabajando: 1, esperan: 1, tareasHoy: 1) == "1 trabajando · 1 espera tu sí · 1 tarea hoy")
    #expect(FraseCentro.estado(trabajando: 0, esperan: 2, tareasHoy: nil) == "2 esperan tu sí")
    #expect(FraseCentro.estado(trabajando: 0, esperan: 0, tareasHoy: 0) == "Todo en calma")
    #expect(FraseCentro.fecha(ahora, calendario: cal) == "lunes 16 de noviembre")
}

@Test("Flechas en una lista: se queda dentro y entra por el primero o el último")
func flechas() {
    #expect(ListaFlechas.mover(actual: nil, delta: 1, total: 3) == 0)
    #expect(ListaFlechas.mover(actual: nil, delta: -1, total: 3) == 2)
    #expect(ListaFlechas.mover(actual: 1, delta: 1, total: 3) == 2)
    #expect(ListaFlechas.mover(actual: 2, delta: 1, total: 3) == 2)
    #expect(ListaFlechas.mover(actual: 0, delta: -1, total: 3) == 0)
    #expect(ListaFlechas.mover(actual: 0, delta: 1, total: 0) == nil)
}

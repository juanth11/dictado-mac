import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
private func ev(_ id: String, _ h1: Int, _ m1: Int = 0, _ h2: Int, _ m2: Int = 0, reunion: Bool = true, dia: Int = 16) -> ReunionDia {
    ReunionDia(id: id, titulo: id, inicio: f(dia, h1, m1), fin: f(dia, h2, m2), invitados: reunion ? ["Lucía Pérez"] : [], esReunion: reunion)
}

@Test("El foco es la reunión en curso; luego vienen las que siguen, en orden")
func focoEnCurso() {
    let p = PlanDelDia.armar(reuniones: [ev("c", 17, 0, 18), ev("a", 14, 0, 15), ev("b", 15, 30, 16)], huecos: [], ahora: f(16, 14, 20), calendario: cal)
    #expect(p.foco?.id == "a")
    #expect(p.enCurso)
    #expect(p.despues.map(\.id) == ["b", "c"])
    #expect(p.restantes == 3)
    #expect(p.sinMostrar == 0)
}

@Test("Lo que ya terminó o es de otro día no cuenta; los bloques sin invitados no son el foco si hay una reunión")
func filtraYPrefiereReuniones() {
    let p = PlanDelDia.armar(reuniones: [ev("pasada", 8, 0, 9), ev("manana", 9, 0, 10, dia: 17), ev("almuerzo", 12, 0, 13, reunion: false), ev("cliente", 15, 0, 16)],
                             huecos: [], ahora: f(16, 11), calendario: cal)
    #expect(p.foco?.id == "cliente")
    #expect(!p.enCurso)
    #expect(p.despues.isEmpty)   // el almuerzo empieza antes que el foco
    #expect(p.restantes == 2)
}

@Test("Sin reuniones, el foco es el primer bloque; sin nada, no hay foco")
func sinReuniones() {
    #expect(PlanDelDia.armar(reuniones: [ev("almuerzo", 12, 0, 13, reunion: false)], huecos: [], ahora: f(16, 11), calendario: cal).foco?.id == "almuerzo")
    #expect(PlanDelDia.armar(reuniones: [], huecos: [], ahora: f(16, 11), calendario: cal).foco == nil)
}

@Test("Cuando hay más de las que caben, cuenta las que quedan fuera")
func cuentaLasQueNoCaben() {
    let todas = (0..<6).map { ev("e\($0)", 9 + $0, 0, 9 + $0, 45) }
    let p = PlanDelDia.armar(reuniones: todas, huecos: [], ahora: f(16, 7), calendario: cal)
    #expect(p.despues.count == 2)
    #expect(p.sinMostrar == 3)
}

@Test("Los huecos son solo los de hoy, desde ahora, y el primero")
func huecosDeHoy() {
    let h = [Intervalo(inicio: f(16, 8), fin: f(16, 9)), Intervalo(inicio: f(16, 16), fin: f(16, 17, 30)),
             Intervalo(inicio: f(16, 10), fin: f(16, 12)), Intervalo(inicio: f(17, 8), fin: f(17, 18))]
    let p = PlanDelDia.armar(reuniones: [], huecos: h, ahora: f(16, 9, 30), calendario: cal)
    #expect(p.huecos == [Intervalo(inicio: f(16, 10), fin: f(16, 12))])
}

@Test("Quiénes van: primeros nombres, con 'y N más'")
func quienes() {
    #expect(PlanDelDia.quienes([]) == "")
    #expect(PlanDelDia.quienes(["Lucía Pérez"]) == "Lucía")
    #expect(PlanDelDia.quienes(["Lucía Pérez", "Marcos Díaz"]) == "Lucía y Marcos")
    #expect(PlanDelDia.quienes(["Lucía", "Marcos", "Elena", "Pedro"]) == "Lucía, Marcos y 2 más")
}

private func fila(_ id: String, _ e: FilaTarjetaAgentes.Estado, hace: Double? = nil) -> FilaTarjetaAgentes {
    FilaTarjetaAgentes(id: id, nombre: id, estado: e, desde: hace.map { f(16, 12).addingTimeInterval(-$0) })
}

@Test("Agentes: primero lo que espera, luego alertas, trabajo, calma y terminado; lo más reciente primero")
func ordenAgentes() {
    let o = PlanAgentes.ordenar([fila("t1", .termino), fila("w-viejo", .trabaja, hace: 3600), fila("e", .espera), fila("w-nuevo", .trabaja, hace: 60), fila("a", .alerta)])
    #expect(o.map(\.id) == ["e", "a", "w-nuevo", "w-viejo", "t1"])
}

@Test("Agentes: las que caben y cuántas quedan fuera")
func visiblesAgentes() {
    let r = PlanAgentes.visibles((0..<5).map { fila("s\($0)", .trabaja, hace: Double($0)) }, maximo: 3)
    #expect(r.filas.count == 3)
    #expect(r.ocultas == 2)
}

@Test("Agentes: la cabecera cuenta lo que espera y, si nada espera, lo que trabaja")
func cabeceraAgentes() {
    #expect(PlanAgentes.cabecera([fila("e", .espera), fila("w", .trabaja)]) == (1, "espera tu sí"))
    #expect(PlanAgentes.cabecera([fila("e", .espera), fila("a", .alerta)]).leyenda == "esperan tu sí")
    #expect(PlanAgentes.cabecera([fila("w", .trabaja), fila("v", .trabaja)]).numero == 2)
    #expect(PlanAgentes.cabecera([fila("t", .termino)]) == (0, "en calma"))
}

@Test("Agentes: duración legible")
func duraciones() {
    let ahora = f(16, 12)
    #expect(PlanAgentes.duracion(desde: ahora.addingTimeInterval(-20), hasta: ahora) == "ahora")
    #expect(PlanAgentes.duracion(desde: ahora.addingTimeInterval(-185), hasta: ahora) == "3 min")
    #expect(PlanAgentes.duracion(desde: ahora.addingTimeInterval(-3900), hasta: ahora) == "1 h 05")
    #expect(PlanAgentes.duracion(desde: ahora.addingTimeInterval(-7200), hasta: ahora) == "2 h")
    #expect(PlanAgentes.duracion(desde: ahora.addingTimeInterval(-9 * 3600), hasta: ahora) == "9 h")
    #expect(PlanAgentes.duracion(desde: ahora.addingTimeInterval(-3 * 86_400), hasta: ahora) == "3 d")
}

@Test("Agentes: el rótulo y la acción de cada estado")
func rotulosAgentes() {
    #expect(fila("a", .espera).accion == "Responder")
    #expect(fila("a", .termino).accion == "Revisar")
    #expect(fila("a", .trabaja).accion == "Abrir")
    #expect(fila("a", .trabaja).rotulo == "Trabajando")
}

@Test("Disco: gira 200° por segundo, se queda donde estaba al pausar y sigue desde ahí")
func giroDelDisco() {
    var g = GiroDisco()
    #expect(g.angulo(en: f(16, 12)) == 0)
    g.cambiar(girando: true, ahora: f(16, 12))
    #expect(abs(g.angulo(en: f(16, 12).addingTimeInterval(0.5)) - 100) < 0.001)
    #expect(abs(g.angulo(en: f(16, 12).addingTimeInterval(2)) - 40) < 0.001)   // 400° = 40°
    g.cambiar(girando: false, ahora: f(16, 12).addingTimeInterval(0.9))
    #expect(abs(g.angulo(en: f(16, 12).addingTimeInterval(60)) - 180) < 0.001)
    g.cambiar(girando: true, ahora: f(16, 12).addingTimeInterval(60))
    #expect(abs(g.angulo(en: f(16, 12).addingTimeInterval(60.1)) - 200) < 0.001)
    let antes = g
    g.cambiar(girando: true, ahora: f(16, 12).addingTimeInterval(99))   // pedir lo mismo no reinicia
    #expect(g == antes)
}

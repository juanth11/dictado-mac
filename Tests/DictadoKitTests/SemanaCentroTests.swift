import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
/// Martes 17 de noviembre de 2026, 10:00 (la semana empieza el lunes 16).
private let ahora = f(17, 10)

private func evento(_ id: String, _ dia: Int, _ h1: Int, _ m1: Int = 0, _ h2: Int, _ m2: Int = 0) -> EventoSemana {
    EventoSemana(id: id, titulo: id, inicio: f(dia, h1, m1), fin: f(dia, h2, m2))
}

private func semana(_ n: Int = 0, eventos: [EventoSemana] = [], huecos: [Intervalo] = [], tareas: [TareaSemana] = []) -> VistaSemanal {
    SemanaCentro.armar(desplazamiento: n, eventos: eventos, huecos: huecos, tareas: tareas, ahora: ahora, calendario: cal)
}

@Test("Semana: siete días de lunes a domingo, con hoy marcado; la siguiente empieza el lunes 23")
func semanaDias() {
    let s = semana()
    #expect(s.dias.count == 7)
    #expect(s.dias.map(\.etiqueta) == ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"])
    #expect(s.dias.map(\.numero) == [16, 17, 18, 19, 20, 21, 22])
    #expect(s.dias.map(\.esHoy) == [false, true, false, false, false, false, false])
    #expect(s.titulo == "16 – 22 nov")
    let p = semana(1)
    #expect(p.dias.first?.numero == 23 && p.dias.allSatisfy { !$0.esHoy } && p.titulo == "23 – 29 nov")
    #expect(SemanaCentro.titulo(f(30, 0), cal) == "30 nov – 6 dic")
}

@Test("Semana: los eventos son bloques en fracciones del alto de la ventana (8 a 18 por omisión)")
func semanaBloques() {
    let s = semana(eventos: [evento("a", 17, 9, 0, 10, 0)])
    #expect(s.horaDesde == 8 && s.horaHasta == 18)
    let b = s.dias[1].bloques
    #expect(b.count == 1 && b[0].carril == 0 && b[0].carriles == 1)
    #expect(abs(b[0].arriba - 0.1) < 1e-9 && abs(b[0].alto - 0.1) < 1e-9)
    #expect(s.dias[0].bloques.isEmpty)
}

@Test("Semana: un evento fuera del horario laboral amplía la ventana de las siete columnas")
func semanaVentana() {
    let s = semana(eventos: [evento("temprano", 18, 6, 30, 7, 30), evento("tarde", 19, 19, 0, 21, 15)])
    #expect(s.horaDesde == 6 && s.horaHasta == 22)
    #expect(s.dias[0].bloques.isEmpty && s.dias[2].bloques.count == 1 && s.dias[3].bloques.count == 1)
}

@Test("Semana: los eventos que se encinan se reparten en carriles")
func semanaCarriles() {
    let s = semana(eventos: [evento("a", 17, 9, 0, 11, 0), evento("b", 17, 10, 0, 12, 0), evento("c", 17, 11, 0, 11, 30), evento("d", 17, 14, 0, 15, 0)])
    let b = s.dias[1].bloques
    func de(_ id: String) -> BloqueSemana? { b.first { $0.id == id } }
    #expect(de("a")?.carril == 0 && de("b")?.carril == 1 && de("c")?.carril == 0)
    #expect(de("a")?.carriles == 2 && de("b")?.carriles == 2 && de("c")?.carriles == 2)
    #expect(de("d")?.carril == 0 && de("d")?.carriles == 1)
}

@Test("Semana: los huecos libres van en su día y la marca de ahora solo en hoy")
func semanaHuecosYAhora() {
    let s = semana(huecos: [Intervalo(inicio: f(17, 11), fin: f(17, 12)), Intervalo(inicio: f(18, 8), fin: f(18, 9, 30))])
    #expect(s.dias[1].huecos.count == 1 && abs(s.dias[1].huecos[0].arriba - 0.3) < 1e-9 && abs(s.dias[1].huecos[0].alto - 0.1) < 1e-9)
    #expect(s.dias[2].huecos.count == 1)
    #expect(s.dias[1].ahora != nil && abs((s.dias[1].ahora ?? 0) - 0.2) < 1e-9)
    #expect(s.dias.filter { $0.ahora != nil }.count == 1)
    #expect(semana(1).dias.allSatisfy { $0.ahora == nil })
}

@Test("Semana: las tareas van bajo el día en que vencen; las vencidas, hoy; las sin fecha, aparte")
func semanaTareas() {
    let tareas = [TareaSemana(id: "1", texto: "Hoy", vence: "2026-11-17"), TareaSemana(id: "2", texto: "Viernes", vence: "2026-11-20"),
                  TareaSemana(id: "3", texto: "Vencida", vence: "2026-11-10"), TareaSemana(id: "4", texto: "Sin fecha"),
                  TareaSemana(id: "5", texto: "Lejana", vence: "2027-01-05"), TareaSemana(id: "6", texto: "Próxima", vence: "2026-11-24"),
                  TareaSemana(id: "7", texto: "Fecha rara", vence: "pronto")]
    let s = semana(tareas: tareas)
    #expect(s.dias[1].tareas.map(\.id) == ["3", "1"])   // la vencida primero
    #expect(s.dias[1].tareas.first?.vencida == true && s.dias[1].tareas.last?.vencida == false)
    #expect(s.dias[4].tareas.map(\.id) == ["2"])
    #expect(s.sinFecha.map(\.id) == ["4"])
    let p = semana(1, tareas: tareas)
    #expect(p.dias[1].tareas.map(\.id) == ["6"])   // la vencida no se repite en la semana que viene
    #expect(p.dias.flatMap(\.tareas).count == 1 && p.sinFecha.map(\.id) == ["4"])
}

@Test("Semana: las tareas de hoy son las que vencen hoy o antes y las sin fecha")
func tareasDeHoy() {
    let tareas = [TareaSemana(id: "1", texto: "a", vence: "2026-11-17"), TareaSemana(id: "2", texto: "b", vence: "2026-11-16"),
                  TareaSemana(id: "3", texto: "c", vence: "2026-11-18"), TareaSemana(id: "4", texto: "d"), TareaSemana(id: "5", texto: "e", vence: "x")]
    #expect(SemanaCentro.tareasDeHoy(tareas, ahora: ahora, calendario: cal) == 3)
    #expect(SemanaCentro.tareasDeHoy([], ahora: ahora, calendario: cal) == 0)
}

@Test("Semana: eventos de todo el día aparte y la regla de horas cada dos")
func semanaTodoElDiaYMarcas() {
    let s = SemanaCentro.armar(desplazamiento: 0, eventos: [], todoElDia: [(dia: f(19, 0), titulo: "Festivo")], huecos: [], tareas: [], ahora: ahora, calendario: cal)
    #expect(s.dias[3].todoElDia == ["Festivo"] && s.dias[0].todoElDia.isEmpty)
    #expect(s.marcas.map(\.hora) == [8, 10, 12, 14, 16, 18])
    #expect(s.marcas.last?.fraccion == 1)
}

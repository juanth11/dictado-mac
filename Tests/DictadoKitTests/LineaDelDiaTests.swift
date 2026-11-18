import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()
private func i(_ h1: Int, _ m1: Int = 0, _ h2: Int, _ m2: Int = 0) -> Intervalo { Intervalo(inicio: f(16, h1, m1), fin: f(16, h2, m2)) }
private func linea(_ ev: [Intervalo], libre: Intervalo? = nil, ahora: Fecha = f(16, 11)) -> LineaDelDia {
    LineaDelDia.armar(dia: f(16, 12), eventos: ev, libre: libre, ahora: ahora, inicioHora: 8, finHora: 18, calendario: cal)
}

@Test("Línea: las horas de 8 a 18 caen en fracciones de 0 a 1 con marcas cada 2 horas")
func lineaMarcas() {
    let l = linea([])
    #expect(l.marcas.map { $0.etiqueta } == ["8", "10", "12", "2", "4", "6"])
    #expect(l.marcas.first?.fraccion == 0 && l.marcas.last?.fraccion == 1)
}

@Test("Línea: un evento de 10 a 11 ocupa el 10 % que empieza en el 20 %")
func lineaEvento() {
    let l = linea([i(10, 0, 11, 0)])
    #expect(l.eventos.count == 1)
    #expect(abs(l.eventos[0].inicio - 0.2) < 1e-9 && abs(l.eventos[0].ancho - 0.1) < 1e-9)
}

@Test("Línea: lo que cae fuera del horario se recorta o se descarta; lo encimado se funde")
func lineaRecorte() {
    let l = linea([i(7, 0, 9, 0), i(17, 0, 19, 0), i(5, 0, 6, 0), i(12, 0, 13, 0), i(12, 30, 14, 0)])
    #expect(l.eventos.count == 3)
    #expect(l.eventos[0].inicio == 0 && abs(l.eventos[0].ancho - 0.1) < 1e-9)
    #expect(abs(l.eventos[2].fin - 1) < 1e-9)
    #expect(abs(l.eventos[1].inicio - 0.4) < 1e-9 && abs(l.eventos[1].ancho - 0.2) < 1e-9)
}

@Test("Línea: el hueco libre se dibuja solo si es de ese día, y ahora solo dentro del horario de hoy")
func lineaLibreYAhora() {
    let libre = i(16, 0, 17, 30)
    #expect(abs((linea([], libre: libre).libre?.inicio ?? 0) - 0.8) < 1e-9)
    let otroDia = Intervalo(inicio: f(17, 16), fin: f(17, 17))
    #expect(linea([], libre: otroDia).libre == nil)
    #expect(abs((linea([], ahora: f(16, 13)).ahora ?? 0) - 0.5) < 1e-9)
    #expect(linea([], ahora: f(16, 7)).ahora == nil)
    #expect(linea([], ahora: f(16, 19)).ahora == nil)
    #expect(linea([], ahora: f(17, 13)).ahora == nil)
}

@Test("Semana: cinco barras de lunes a viernes con su cuenta y la marca de hoy")
func semanaBarras() {
    let ev = [i(9, 0, 10, 0), i(14, 0, 15, 0), Intervalo(inicio: f(18, 9), fin: f(18, 12)), Intervalo(inicio: f(21, 9), fin: f(21, 10))]
    let b = SemanaBarras.armar(eventos: ev, ahora: f(18, 11), calendario: cal)
    #expect(b.map(\.etiqueta) == ["lun 16", "mar 17", "mié 18", "jue 19", "vie 20"])
    #expect(b.map(\.eventos) == [2, 0, 1, 0, 0])
    #expect(b.map(\.esHoy) == [false, false, true, false, false])
    #expect(b[0].ocupado.count == 2)
}

@Test("Semana: un domingo cuenta dentro de la semana que termina")
func semanaDomingo() {
    let b = SemanaBarras.armar(eventos: [], ahora: f(15, 12), calendario: cal)
    #expect(b.first?.etiqueta == "lun 9" && b.last?.etiqueta == "vie 13")
}

@Test("Cuenta regresiva: horas y minutos, o solo minutos, redondeando hacia arriba")
func cuentaRegresiva() {
    let ahora = f(16, 9)
    #expect(CuentaRegresiva.texto(hasta: ahora.addingTimeInterval(135 * 60), desde: ahora)?.texto == "2:15")
    #expect(CuentaRegresiva.texto(hasta: ahora.addingTimeInterval(135 * 60), desde: ahora)?.unidad == "h")
    #expect(CuentaRegresiva.texto(hasta: ahora.addingTimeInterval(12 * 60 + 10), desde: ahora)?.texto == "13")
    #expect(CuentaRegresiva.texto(hasta: ahora.addingTimeInterval(60 * 60), desde: ahora)?.texto == "1:00")
    #expect(CuentaRegresiva.texto(hasta: ahora.addingTimeInterval(59 * 60), desde: ahora)?.unidad == "min")
    #expect(CuentaRegresiva.texto(hasta: ahora, desde: ahora) == nil)
}

@Test("Cambio de la agenda: libre hasta el próximo evento, u ocupado hasta que termine")
func cambioAgenda() {
    let ev = [i(10, 0, 11, 0), i(10, 30, 12, 0)]
    let libre = CambioAgenda.proximo(ocupados: ev, ahora: f(16, 9))
    #expect(libre == CambioAgenda.Estado(ocupadoAhora: false, cambio: f(16, 10)))
    let ocupado = CambioAgenda.proximo(ocupados: ev, ahora: f(16, 10, 45))
    #expect(ocupado == CambioAgenda.Estado(ocupadoAhora: true, cambio: f(16, 12)))
    #expect(CambioAgenda.proximo(ocupados: ev, ahora: f(16, 13)) == CambioAgenda.Estado(ocupadoAhora: false, cambio: nil))
}

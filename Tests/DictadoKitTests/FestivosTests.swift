import Testing
@testable import DictadoKit

// Las fechas esperadas están escritas a mano desde la ley (Ley 51 de 1983 y la Pascua), no sacadas del código.

@Test("La Pascua gregoriana: 2026 es el 5 de abril y 2027 el 28 de marzo (y 2024, 31 de marzo)")
func pascua() {
    #expect(Festivos.domingoDePascua(año: 2026) == (4, 5))
    #expect(Festivos.domingoDePascua(año: 2027) == (3, 28))
    #expect(Festivos.domingoDePascua(año: 2024) == (3, 31))
}

@Test("Colombia 2026: los 18 festivos")
func colombia2026() {
    #expect(clavesFestivos("CO", 2026) == [
        "2026-01-01",  // Año Nuevo (jueves)
        "2026-01-12",  // Reyes: 6 de enero es martes, pasa al lunes 12
        "2026-03-23",  // San José: 19 de marzo es jueves, pasa al lunes 23
        "2026-04-02",  // Jueves Santo (Pascua 5 de abril − 3)
        "2026-04-03",  // Viernes Santo
        "2026-05-01",  // Día del Trabajo (viernes)
        "2026-05-18",  // Ascensión: Pascua + 43
        "2026-06-08",  // Corpus Christi: Pascua + 64
        "2026-06-15",  // Sagrado Corazón: Pascua + 71
        "2026-06-29",  // San Pedro y San Pablo: ya es lunes
        "2026-07-20",  // Independencia (lunes)
        "2026-08-07",  // Batalla de Boyacá (viernes)
        "2026-08-17",  // Asunción: 15 de agosto es sábado, pasa al lunes 17
        "2026-10-12",  // Día de la Raza (lunes)
        "2026-11-02",  // Todos los Santos: 1 de noviembre es domingo, pasa al lunes 2
        "2026-11-16",  // Independencia de Cartagena: 11 de noviembre es miércoles, pasa al lunes 16
        "2026-12-08",  // Inmaculada Concepción (martes)
        "2026-12-25",  // Navidad (viernes)
    ])
}

@Test("Colombia 2027: los 18 festivos")
func colombia2027() {
    #expect(clavesFestivos("CO", 2027) == [
        "2027-01-01",  // Año Nuevo (viernes)
        "2027-01-11",  // Reyes: 6 de enero es miércoles, pasa al lunes 11
        "2027-03-22",  // San José: 19 de marzo es viernes, pasa al lunes 22
        "2027-03-25",  // Jueves Santo (Pascua 28 de marzo − 3)
        "2027-03-26",  // Viernes Santo
        "2027-05-01",  // Día del Trabajo (sábado, fijo: no se traslada)
        "2027-05-10",  // Ascensión: Pascua + 43
        "2027-05-31",  // Corpus Christi: Pascua + 64
        "2027-06-07",  // Sagrado Corazón: Pascua + 71
        "2027-07-05",  // San Pedro y San Pablo: 29 de junio es martes, pasa al lunes 5 de julio
        "2027-07-20",  // Independencia (martes, fijo)
        "2027-08-07",  // Batalla de Boyacá (sábado, fijo)
        "2027-08-16",  // Asunción: 15 de agosto es domingo, pasa al lunes 16
        "2027-10-18",  // Día de la Raza: 12 de octubre es martes, pasa al lunes 18
        "2027-11-01",  // Todos los Santos (ya es lunes)
        "2027-11-15",  // Independencia de Cartagena: 11 de noviembre es jueves, pasa al lunes 15
        "2027-12-08",  // Inmaculada Concepción (miércoles)
        "2027-12-25",  // Navidad (sábado)
    ])
}

@Test("Los trasladados y los de Pascua (salvo Jueves y Viernes Santo) siempre caen en lunes")
func lunes() {
    let que = ["Reyes Magos", "San José", "Ascensión del Señor", "Corpus Christi", "Sagrado Corazón", "San Pedro y San Pablo",
               "Asunción de la Virgen", "Día de la Raza", "Todos los Santos", "Independencia de Cartagena"]
    for año in 2024...2032 {
        for f in Festivos.colombia(año: año) where que.contains(f.nombre) {
            #expect(Festivos.diaDeSemana(Festivos.diasDesdeEpoca(año: f.año, mes: f.mes, dia: f.dia)) == 1, "\(f.nombre) \(f.clave)")
        }
        #expect(Festivos.colombia(año: año).count == 18)
    }
}

@Test("La aritmética de días: 2026-11-16 es lunes y la ida y vuelta coincide")
func aritmetica() {
    let n = Festivos.diasDesdeEpoca(año: 2026, mes: 11, dia: 16)
    #expect(Festivos.diaDeSemana(n) == 1)
    #expect(Festivos.civil(desdeEpoca: n) == (2026, 11, 16))
    #expect(Festivos.diasDesdeEpoca(año: 1970, mes: 1, dia: 1) == 0)
    #expect(Festivos.diaDeSemana(0) == 4)  // jueves
}

@Test("Otro país no tiene lista incorporada")
func otroPais() {
    #expect(Festivos.de(pais: "MX", año: 2026).isEmpty)
    #expect(Festivos.de(pais: "co", año: 2026).count == 18)
}

@Test("Los festivos puestos sobre fechas: 16 de noviembre de 2026 está y el 17 no")
func festivosEnFechas() {
    let cal = calendarioDePrueba()
    let mapa = DiasFestivos.entre(fe(2026, 11, 1), fe(2026, 12, 31), pais: "CO", calendario: cal)
    #expect(mapa[cal.startOfDay(for: fe(2026, 11, 16))] == "Independencia de Cartagena")
    #expect(mapa[cal.startOfDay(for: fe(2026, 11, 17))] == nil)
    #expect(mapa.count == 4)  // 2 de noviembre, 16 de noviembre, 8 y 25 de diciembre
}

@Test("Un calendario del Mac con festivos manda sobre la lista incorporada; el título se reconoce o se nombra")
func combinarYTitulos() {
    let c = calendarioDePrueba()
    let a = c.startOfDay(for: fe(2026, 11, 16)), b = c.startOfDay(for: fe(2026, 12, 8))
    #expect(DiasFestivos.combinar(delCalendario: [a: "Festivo"], incorporados: [b: "Inmaculada"]) == [a: "Festivo"])
    #expect(DiasFestivos.combinar(delCalendario: [:], incorporados: [b: "Inmaculada"]) == [b: "Inmaculada"])
    #expect(DiasFestivos.pareceDeFestivos("Festivos en Colombia"))
    #expect(DiasFestivos.pareceDeFestivos("Holidays in Colombia"))
    #expect(!DiasFestivos.pareceDeFestivos("Trabajo"))
    #expect(DiasFestivos.pareceDeFestivos("Mis fiestas", nombreExplicito: "mis fiestas"))
    #expect(!DiasFestivos.pareceDeFestivos("Festivos en Colombia", nombreExplicito: "Otro"))
}

import Testing
@testable import DictadoKit

@Test("Nuevo evento: franja en UTC (Bogotá 3:00 p. m. = 20:00Z) y 30 minutos por omisión")
func nuevoEventoUTC() throws {
    let url = try #require(EnlacesCalendario.nuevoEvento(inicio: f(17, 15, 0), titulo: "Reunión"))
    #expect(url.absoluteString == "https://calendar.google.com/calendar/render?action=TEMPLATE&dates=20261117T200000Z/20261117T203000Z&text=Reuni%C3%B3n")
}

@Test("La misma hora absoluta da el mismo enlace sin importar la zona del Mac")
func mismaHoraOtraZona() throws {
    let a = try #require(EnlacesCalendario.nuevoEvento(inicio: f(17, 15, 0, zona: "America/Bogota"), titulo: "X"))
    let b = try #require(EnlacesCalendario.nuevoEvento(inicio: f(17, 21, 0, zona: "Europe/Madrid"), titulo: "X"))
    #expect(a == b)
}

@Test("Cruzar la medianoche en UTC cambia el día de la fecha")
func cruceUTC() throws {
    let url = try #require(EnlacesCalendario.nuevoEvento(inicio: f(17, 19, 45), duracionMin: 30, titulo: "X"))
    #expect(url.absoluteString.contains("dates=20261118T004500Z/20261118T011500Z"))
}

@Test("El título se codifica: espacios, &, # y tildes no rompen el enlace")
func tituloCodificado() throws {
    let url = try #require(EnlacesCalendario.nuevoEvento(inicio: f(17, 9, 0), duracionMin: 45, titulo: "Cliente & socio #1: revisión"))
    let s = url.absoluteString
    #expect(s.hasSuffix("&text=Cliente%20%26%20socio%20%231%3A%20revisi%C3%B3n"))
    #expect(s.contains("20261117T140000Z/20261117T144500Z"))
    #expect(!s.contains(" "))
}

@Test("La cuenta solo se agrega si parece un correo")
func cuentaOpcional() throws {
    let con = try #require(EnlacesCalendario.nuevoEvento(inicio: f(17, 9, 0), titulo: "X", cuenta: "alguien@ejemplo.com"))
    #expect(con.absoluteString.hasSuffix("&authuser=alguien%40ejemplo.com"))
    let sin = try #require(EnlacesCalendario.nuevoEvento(inicio: f(17, 9, 0), titulo: "X", cuenta: "Google"))
    #expect(!sin.absoluteString.contains("authuser"))
}

@Test("Vista del día con el formato de Google (mes y día sin ceros)")
func vistaDia() throws {
    let url = try #require(EnlacesCalendario.dia(f(5, 10, 0), calendario: calendarioDePrueba()))
    #expect(url.absoluteString == "https://calendar.google.com/calendar/r/day/2026/11/5")
}

@Test("Evento de Google: eid es base64 sin relleno de «id correo»")
func eventoGoogle() throws {
    // "abc123 yo@ejemplo.com" en base64 = YWJjMTIzIHlvQGVqZW1wbG8uY29t
    let url = try #require(EnlacesCalendario.eventoGoogle(uid: "abc123@google.com", calendario: "yo@ejemplo.com"))
    #expect(url.absoluteString == "https://calendar.google.com/calendar/event?eid=YWJjMTIzIHlvQGVqZW1wbG8uY29t")
}

@Test("Sin UID de Google o sin correo del calendario no hay enlace directo")
func eventoGoogleNo() {
    #expect(EnlacesCalendario.eventoGoogle(uid: "7F3A-1B2C", calendario: "yo@ejemplo.com") == nil)
    #expect(EnlacesCalendario.eventoGoogle(uid: "abc@google.com", calendario: "Trabajo") == nil)
    #expect(EnlacesCalendario.eventoGoogle(uid: nil, calendario: "yo@ejemplo.com") == nil)
}

import Testing
@testable import DictadoKit

@Test("Lugar: un texto normal se queda y los espacios se colapsan")
func lugarNormal() {
    #expect(LugarEvento.limpiar("Calle 10 #20-30,\n  Bogotá") == "Calle 10 #20-30, Bogotá")
    #expect(LugarEvento.limpiar("  Oficina de Lumina ") == "Oficina de Lumina")
}

@Test("Lugar: vacío o nil no muestran nada")
func lugarVacio() {
    #expect(LugarEvento.limpiar(nil) == nil)
    #expect(LugarEvento.limpiar("  \n ") == nil)
}

@Test("Lugar: una URL de videollamada no se duplica (ya está «Unirse»)")
func lugarVideollamada() {
    #expect(LugarEvento.limpiar("https://meet.google.com/abc-defg-hij") == nil)
    #expect(LugarEvento.limpiar("Zoom: zoom.us/j/123456") == nil)
    #expect(LugarEvento.limpiar("www.ejemplo.com/sala") == nil)
    #expect(LugarEvento.limpiar("Sala 3", enlace: "https://meet.google.com/abc") == "Sala 3")
    #expect(LugarEvento.limpiar("Sala 3 https://x.co/abc", enlace: "https://x.co/abc") == nil)
}

@Test("Lugar: las direcciones muy largas se recortan con puntos suspensivos")
func lugarLargo() {
    let largo = String(repeating: "a", count: 200)
    let r = LugarEvento.limpiar(largo, maximo: 20)
    #expect(r?.count == 20)
    #expect(r?.hasSuffix("…") == true)
}

@Test("Lugar: el enlace a Mapas escapa espacios, acentos, # y &")
func lugarMapas() {
    #expect(LugarEvento.urlMapas("Calle 93 #11-27")?.absoluteString == "maps://?q=Calle%2093%20%2311-27")
    #expect(LugarEvento.urlMapas("Café & Té, Bogotá")?.absoluteString == "maps://?q=Caf%C3%A9%20%26%20T%C3%A9%2C%20Bogot%C3%A1")
}

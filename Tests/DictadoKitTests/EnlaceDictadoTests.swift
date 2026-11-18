import Testing
@testable import DictadoKit

private func orden(_ s: String) -> OrdenEnlace? { EnlaceDictado.analizar(texto: s) }

@Test("Enlaces: grabar alterna, empieza o termina")
func enlacesGrabar() {
    #expect(orden("dictado://grabar") == .grabar(.alternar))
    #expect(orden("dictado://grabar/empezar") == .grabar(.empezar))
    #expect(orden("dictado://Grabar/Terminar") == .grabar(.terminar))
    #expect(orden("dictado:grabar/empezar") == .grabar(.empezar))
    #expect(orden("dictado://grabar/bailar") == nil)
}

@Test("Enlaces: espacio por número, por nombre con tildes, siguiente y anterior")
func enlacesEspacio() {
    #expect(orden("dictado://espacio/2") == .espacio(.destino(.numero(2))))
    #expect(orden("dictado://espacio/siguiente") == .espacio(.destino(.siguiente)))
    #expect(orden("dictado://espacio/anterior") == .espacio(.destino(.anterior)))
    #expect(orden("dictado://espacio/Ma%C3%B1ana") == .espacio(.nombre("Mañana")))
    #expect(orden("dictado://espacio") == .espacio(.destino(.siguiente)))
    #expect(EnlaceDictado.indiceDeEspacio("manana", en: ["Mañana", "Trabajo", "Foco"]) == 0)
    #expect(EnlaceDictado.indiceDeEspacio(" FOCO ", en: ["Mañana", "Trabajo", "Foco"]) == 2)
    #expect(EnlaceDictado.indiceDeEspacio("Juego", en: ["Mañana"]) == nil)
}

@Test("Enlaces: el resto de las órdenes y lo que no es de Dictado")
func enlacesResto() {
    #expect(orden("dictado://lanzador") == .lanzador)
    #expect(orden("dictado://hoy") == .centro)
    #expect(orden("dictado://centro") == .centro)
    #expect(orden("dictado://centro/abrir") == .abrirCentro)
    #expect(orden("dictado://hoy/Abrir") == .abrirCentro)
    #expect(orden("dictado://foco") == .foco)
    #expect(orden("dictado://unirse") == .unirse)
    #expect(orden("dictado://ultima-grabacion") == .ultimaGrabacion)
    #expect(orden("dictado://nada") == nil)
    #expect(orden("https://grabar") == nil)
}

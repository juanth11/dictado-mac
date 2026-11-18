import Testing
@testable import DictadoKit

@Test("Medidas del notch: 968 de ancho si cabe y se achica en pantallas angostas sin pasar del mínimo")
func medidasAncho() {
    #expect(MedidasNotch.ancho(pantalla: 1440) == 968)
    #expect(MedidasNotch.ancho(pantalla: 1050) == 968)
    #expect(MedidasNotch.ancho(pantalla: 1000) == 1000 - 76)
    #expect(MedidasNotch.ancho(pantalla: 600) == MedidasNotch.anchoMinimo)
    #expect(MedidasNotch.ancho(pantalla: 0) == 968)
}

@Test("Medidas del notch: el alto suma notch, pestañas y tarjetas de 178")
func medidasAlto() {
    #expect(MedidasNotch.alto(notch: 32) == 264)
    #expect(MedidasNotch.alto(notch: 24) == 256)
}

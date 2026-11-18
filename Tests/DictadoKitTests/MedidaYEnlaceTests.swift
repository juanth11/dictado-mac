import Testing
@testable import DictadoKit

@Test("Bytes legibles", arguments: [(8_900_000_000.0, "8,9 GB"), (640_000_000.0, "640 MB"), (12_000.0, "12 KB")])
func bytes(valor: Double, esperado: String) {
    #expect(Medida.bytes(valor) == esperado)
}

@Test("Porcentaje redondea")
func porcentaje() {
    #expect(Medida.porcentaje(0.456) == "46 %")
    #expect(Medida.porcentaje(0) == "0 %")
}

@Test("El enlace a Claude codifica el texto")
func enlaceCodificado() throws {
    let url = try #require(EnlaceClaude.url("¿Qué opinas? Sí & no"))
    #expect(url.absoluteString.hasPrefix("claude://claude.ai/new?q="))
    #expect(!url.absoluteString.contains(" "))
    #expect(url.absoluteString.contains("%26"))
}

@Test("Sin enlace: vacío, empieza por / o demasiado largo", arguments: ["", "   ", "/compact", String(repeating: "a", count: 15_000)])
func sinEnlace(texto: String) {
    #expect(EnlaceClaude.url(texto) == nil)
}

import Testing
@testable import DictadoKit

private func uso(_ id: String, _ usos: Int, _ dias: Int? = nil) -> UsoApp {
    UsoApp(bundleID: id, usos: usos, ultimoUso: dias.map { f(16, 9).addingTimeInterval(-Double($0) * 86_400) })
}

@Test("Ranking: más usos primero, el uso reciente desempata y el identificador cierra")
func rankingOrden() {
    let todas: Set = ["a", "b", "c", "d"]
    let r = MasUsadas.ranking([uso("a", 5, 3), uso("b", 9), uso("c", 5, 1), uso("d", 5, 1)], instaladas: todas, cuantas: 4)
    #expect(r == ["b", "c", "d", "a"])
}

@Test("Ranking: sin instalar, sin usos o excluidas no entran, y una app repetida cuenta una vez")
func rankingFiltros() {
    let r = MasUsadas.ranking([uso("a", 4), uso("a", 7), uso("b", 0), uso("fantasma", 99), uso("yo", 50), uso("c", 1)],
                              instaladas: ["a", "b", "c", "yo"], excluir: ["yo"], cuantas: 6)
    #expect(r == ["a", "c"])
}

@Test("Ranking: las fijadas a mano van primero, en su orden, y el uso completa hasta seis")
func rankingPreferidas() {
    let usos = (1...8).map { uso("app\($0)", $0 * 10) }
    let instaladas = Set((1...8).map { "app\($0)" })
    let r = MasUsadas.ranking(usos, instaladas: instaladas, preferidas: ["app1", "no-instalada", "app2", "app1"], cuantas: 6)
    #expect(r == ["app1", "app2", "app8", "app7", "app6", "app5"])
}

@Test("Ranking: cuantas = 0 devuelve vacío")
func rankingVacio() {
    #expect(MasUsadas.ranking([uso("a", 1)], instaladas: ["a"], cuantas: 0).isEmpty)
}

@Test("Fijas: las instaladas van primero y en su orden; las que no están se saltan; el resto sigue sin repetirlas")
func fijasOrden() {
    let r = MasUsadas.conFijas(fijas: ["com.spotify.client", "no.esta", "b"], instaladas: ["com.spotify.client", "a", "b", "c"], resto: ["a", "b", "c"])
    #expect(r == ["com.spotify.client", "b", "a", "c"])
    #expect(MasUsadas.conFijas(fijas: [], instaladas: ["a"], resto: ["a"]) == ["a"])
    #expect(MasUsadas.fijasPorOmision == ["com.spotify.client"])
}

@Test("Espacios: el archivo inicial ya no menciona Música (Apple Music); Descanso pone Spotify primero")
func espaciosSinAppleMusic() {
    let e = EspaciosIsla.leer(EspaciosIsla.inicial)
    #expect(e.flatMap(\.primero).allSatisfy { $0 != "Música" })
    #expect(e.first { $0.nombre == "Descanso" }?.primero.first == "Spotify")
}

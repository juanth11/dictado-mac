import Testing
@testable import DictadoKit

@Test("Inicio con el panel ideal (968): cabe todo, el lanzador no baja de 330 y la música queda cerca de 300")
func inicioIdeal() {
    let total = MedidasNotch.anchoIdeal - 2 * MedidasNotch.relleno
    for foco in [false, true] {
        let d = DisposicionInicio.repartir(total: total, foco: foco)
        #expect(abs(d.suma + 30 - total) < 0.001, "foco \(foco)")
        #expect(d.apps >= 330)
        #expect(d.musica >= 250 && d.reunion >= 150)
    }
    let sin = DisposicionInicio.repartir(total: total, foco: false)
    #expect(sin.musica == 300)       // la música sigue siendo la tarjeta principal
    #expect(sin.derecha >= 130 && sin.reunion >= 150)
    let con = DisposicionInicio.repartir(total: total, foco: true)
    #expect(con.derecha >= 176)      // el foco tiene sitio para sus tres botones
}

@Test("Inicio en el panel más angosto (800): las piezas bajan a su mínimo y el lanzador sigue en 330 o más")
func inicioAngosto() {
    let d = DisposicionInicio.repartir(total: MedidasNotch.anchoMinimo - 2 * MedidasNotch.relleno, foco: false)
    #expect(d.apps >= 330)
    #expect(d.musica >= 250 && d.reunion >= 150 && d.derecha >= 130)
}

@Test("Inicio en una pantalla más ancha: lo que sobra va al lanzador")
func inicioAncho() {
    let d = DisposicionInicio.repartir(total: 1200, foco: false)
    #expect(d.musica == 300 && d.reunion == 170 && d.derecha == 150)
    #expect(d.apps > 330)
}

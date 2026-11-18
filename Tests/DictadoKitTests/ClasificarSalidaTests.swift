import Testing
@testable import DictadoKit

@Suite struct ClasificarSalidaTests {
    @Test func codigosDeCuatroLetras() {
        #expect(ClasificarSalida.codigo("grup") == 0x67727570)
        #expect(ClasificarSalida.agregado == 0x67727570)
        #expect(ClasificarSalida.virtual == 0x76697274)
    }

    @Test func laSalidaMultipleSeOfreceYSeMarca() {
        let t = ClasificarSalida.agregado
        #expect(ClasificarSalida.tipo(transporte: t) == .multiple)
        #expect(ClasificarSalida.seOfrece(tieneSalida: true, oculto: false, transporte: t))
    }

    @Test func virtualesOcultasYSinSalidaNoSeOfrecen() {
        #expect(!ClasificarSalida.seOfrece(tieneSalida: true, oculto: false, transporte: ClasificarSalida.virtual))
        #expect(!ClasificarSalida.seOfrece(tieneSalida: true, oculto: true, transporte: ClasificarSalida.agregado))
        #expect(!ClasificarSalida.seOfrece(tieneSalida: false, oculto: false, transporte: ClasificarSalida.codigo("bltn")))
    }

    @Test func fisicasPrimeroYMultiplesDespues() {
        let lista: [(nombre: String, multiple: Bool)] = [("MacBook + Echo", true), ("Echo", false), ("Altavoces del MacBook", false)]
        let ordenada = lista.sorted(by: ClasificarSalida.orden).map(\.nombre)
        #expect(ordenada == ["Altavoces del MacBook", "Echo", "MacBook + Echo"])
    }
}
